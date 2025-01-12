module replatform64.commonplatform;

import replatform64.assets;
import replatform64.backend.common;
import replatform64.dumping;
import replatform64.framestat;
import replatform64.ui;
import replatform64.util;
import replatform64.watchdog;

import imgui.flamegraph;

import core.stdc.stdlib;
import core.thread;
import std.algorithm.comparison;
import std.algorithm.iteration;
import std.algorithm.mutation;
import std.concurrency;
import std.conv;
import std.exception;
import std.file;
import std.format;
import std.logger;
import std.stdio;
import std.string;
import siryul;

enum settingsFile = "settings.yaml";

struct PlatformCommon {
	PlatformBackend backend;
	InputState inputState;
	bool paused;
	Fiber game;
	string gameID;
	BackendSettings settings;
	DebugFunction debugMenu;
	DebugFunction platformDebugMenu;
	DebugFunction debugState;
	DebugFunction platformDebugState;
	Resolution nativeResolution;
	private const(RecordedInputState)[] inputPlayback;
	private uint inputPlaybackFrameCounter;
	private HookState[][string] hooks;
	private ubyte[][uint] sramSlotBuffer;
	private bool metricsEnabled;
	private bool uiMetricsEnabled;
	private ImGui.ImGuiContext* imguiContext;
	private bool renderUI = true;
	private bool debuggingEnabled;
	alias EntryPoint = void delegate();
	static struct MemoryEditorState {
		string name;
		ubyte[] range;
		MemoryEditor editor;
		bool active;
	}
	MemoryEditorState[] memoryEditors;
	void playbackDemo(const RecordedInputState[] demo) @safe pure {
		inputPlayback = demo;
	}
	auto loadSettings(SystemSettings, GameSettings)() {
		alias Settings = FullSettings!(SystemSettings, GameSettings);
		if (!settingsFile.exists) {
			Settings defaults;
			defaults.toFile!YAML(settingsFile);
		}
		auto result = fromFile!(Settings, YAML, DeSiryulize.optionalByDefault)(settingsFile);
		settings = result.backend;
		return result;
	}

	void saveSettings(SystemSettings, GameSettings)(SystemSettings systemSettings, GameSettings gameSettings) {
		alias Settings = FullSettings!(SystemSettings, GameSettings);
		settings.video.ui = strip(ImGui.SaveIniSettingsToMemory());
		settings.video.window = backend.video.getWindowState();
		Settings(systemSettings, gameSettings, settings).toFile!YAML(settingsFile);
	}
	void initialize(EntryPoint dg, Backend backendType = Backend.autoSelect) {
		detachConsoleIfUnneeded();
		this.game = new Fiber(dg);
		infof("Loading backend");
		backend = loadBackend(backendType, settings);

		infof("Initializing UI");
		IMGUI_CHECKVERSION();
		imguiContext = ImGui.CreateContext();
		ImGui.LoadIniSettingsFromMemory(settings.video.ui);
		ImGuiIO* io = &ImGui.GetIO();
		io.IniFilename = "";
		ImGui.StyleColorsDark();
		ImGui.GetStyle().ScaleAllSizes(settings.video.uiZoom);
		io.FontGlobalScale = settings.video.uiZoom;
		tracef("UI initialized");

		renderUI = false;
		infof("Initializing watchdog");
		startWatchDog();
	}
	void deinitialize() {
		ImGui.DestroyContext(imguiContext);
		backend.deinitialize();
	}
	void installAudioCallback(void* data, AudioCallback callback) @safe {
		backend.audio.installCallback(data, callback);
	}
	void enableDebuggingFeatures() @safe {
		debuggingEnabled = true;
		if (settings.video.window.width.isNull) {
			//resetWindowSize(true);
		}
	}
	void registerMemoryRange(string name, ubyte[] range) @safe pure {
		static MemoryEditor initMemoryEditor() {
			MemoryEditor editor;
			editor.Cols = 8;
			editor.OptShowOptions = false;
			editor.OptShowDataPreview = false;
			editor.OptShowAscii = false;
			return editor;
		}
		memoryEditors ~= MemoryEditorState(
			name: name,
			range: range,
			editor: initMemoryEditor(),
			active: false,
		);
	}
	void debuggingUI(const UIState) {
		if (ImGui.BeginMainMenuBar()) {
			if (ImGui.BeginMenu("Debugging")) {
				ImGui.MenuItem("Enable metrics", null, &metricsEnabled);
				ImGui.MenuItem("Enable UI metrics", null, &uiMetricsEnabled);
				if (ImGui.BeginMenu("Memory")) {
					foreach (ref memoryEditor; memoryEditors) {
						ImGui.MenuItem(memoryEditor.name, null, &memoryEditor.active);
					}
					ImGui.EndMenu();
				}
				if (ImGui.MenuItem("Force crash")) {
					assert(0, "Forced crash");
				}
				ImGui.EndMenu();
			}
			ImGui.EndMainMenuBar();
		}
		foreach (ref memoryEditor; memoryEditors) {
			if (memoryEditor.active) {
				memoryEditor.active = memoryEditor.editor.DrawWindow(memoryEditor.name, memoryEditor.range);
			}
		}
		if (metricsEnabled) {
			if (ImGui.Begin("Metrics")) {
				PlotFlame("Frame time", (start, end, level, caption, data, idx) {
					const times = *cast(typeof(frameStatTracker.history)*)data;
					if (caption) {
						*caption = frameStatisticLabels[idx];
					}
					if (level) {
						*level = 0;
					}
					if (start) {
						*start = times[].map!(x => (x.statistics[idx][0] - x.start).total!"hnsecs" / 10_000.0).mean;
					}
					if (end) {
						*end = times[].map!(x => (x.statistics[idx][1] - x.start).total!"hnsecs" / 10_000.0).mean;
					}
				}, &frameStatTracker.history, cast(int)(FrameStatistic.max + 1), 0, "", float.max, float.max, ImVec2(400.0, 0.0));
				ImGui.PlotLines("Frame History", (data, idx) {
					const times = *cast(typeof(frameStatTracker.history)*)data;
					return (times[idx].end - times[idx].start).total!"hnsecs" / 10_000.0;
				}, &frameStatTracker.history, cast(int)frameStatTracker.history.length);
			}
			ImGui.End();
		}
		if (uiMetricsEnabled) {
			ImGui.ShowMetricsWindow(&uiMetricsEnabled);
		}
	}
	void showUI() {
		renderUI = true;
	}
	bool runFrame(scope void delegate() interrupt, scope void delegate() draw) {
		// pet the dog each frame so it knows we're ok
		watchDog.pet();
		const lastInput = inputState;
		{
			frameStatTracker.startFrame();
			scope(exit) frameStatTracker.endFrame();
			if (backend.processEvents()) {
				return true;
			}
			updateInput();
			frameStatTracker.checkpoint(FrameStatistic.events);
			if (inputState.exit) {
				return true;
			}

			if (!paused || inputState.step) {
				inputState.step = false;
				if (game.state != Fiber.State.HOLD) {
					infof("Game exited normally");
					return true;
				}
				if (auto thrown = game.call(Fiber.Rethrow.no)) {
					writeDebugDump(thrown.msg, thrown.info);
					return true;
				}
				interrupt();
			}
			frameStatTracker.checkpoint(FrameStatistic.gameLogic);
			backend.video.startFrame();
			draw();
			frameStatTracker.checkpoint(FrameStatistic.ppu);
			renderUIElements();
			backend.video.finishFrame();
		}
		if (!inputState.fastForward) {
			backend.video.waitNextFrame();
		}

		if (inputState.pause && !lastInput.pause) {
			paused = !paused;
		}
		return false;
	}
	void updateInput() @safe {
		if (inputPlayback.length > 0) {
			inputState = inputPlayback[0].state;
			if (inputPlaybackFrameCounter == inputPlayback[0].frames) {
				inputPlaybackFrameCounter = 0;
				inputPlayback = inputPlayback[1 .. $];
			}
		} else {
			inputState = backend.input.getState();
		}
	}
	void wait(scope void delegate() interrupt) {
		if (Fiber.getThis) {
			Fiber.yield();
		} else {
			interrupt();
		}
	}
	void handleAssets(Modules...)(immutable(ubyte)[] romData, ExtractFunction extractor = null, LoadFunction loader = null, bool toFilesystem = false) {
		if (!assetsExist) {
			extractAssets!Modules(extractor, romData, toFilesystem);
		}
		loadAssets!Modules(loader);
	}
	bool assetsExist() {
		return (gameID~".planet").exists;
	}
	PlanetArchive assets() {
		if ((gameID~".planet").exists) {
			return PlanetArchive.read(cast(ubyte[])read(gameID~".planet"));
		}
		throw new Exception("Not found");
	}
	void extractAssets(Modules...)(ExtractFunction extractor, immutable(ubyte)[] data, bool toFilesystem = false) {
		import std.path : buildPath, dirName;
		static void extractAllData(Tid main, immutable(ubyte)[] rom, bool toFilesystem, ExtractFunction extractor, string gameID) {
			try {
				PlanetArchive archive;
				void addFile(string name, const ubyte[] data) {
					archive.addFile(name, data);
					if (toFilesystem) {
						auto fullPath = buildPath("data", name);
						mkdirRecurse(fullPath.dirName);
						File(fullPath, "w").rawWrite(data);
					}
				}
				send(main, "Loading ROM");

				//handle generic data
				static foreach (asset; SymbolData!Modules) {{
					static if (asset.metadata.sources.length > 0) {
						foreach (i, element; asset.metadata.sources) {{
							{
								enum str = "Extracting " ~ asset.metadata.name;
								send(main, Progress(str, cast(uint)i, cast(uint)asset.metadata.sources.length));
							}
							addFile(asset.metadata.assetPath(i), saveROMAsset(rom[element.offset .. element.offset + element.length], asset.metadata));
						}}
					} else {
						if (asset.metadata.type == DataType.structured) {
							addFile(asset.metadata.name, cast(immutable(ubyte)[])asset.data.toString!YAML);
						}
					}
				}}

				// extract extra game data that needs special handling
				if (extractor !is null) {
					extractor(&addFile, (str) { send(main, str); }, rom);
				}

				// write the archive
				if (!archive.empty) {
					archive.write(File(gameID~".planet", "w").lockingBinaryWriter);
				}

			} catch (Throwable e) {
				errorf("%s", e);
				exit(1);
			}
			// done
			send(main, true);
		}
		auto extractorThread = spawn(cast(shared)&extractAllData, thisTid, data, toFilesystem, extractor, gameID);
		bool extractionDone;
		auto progress = Progress("Initializing");
		void renderExtractionUI() {
			ImGui.SetNextWindowPos(ImGui.GetMainViewport().GetCenter(), ImGuiCond.Appearing, ImVec2(0.5f, 0.5f));
			ImGui.Begin("Creating planet archive", null, ImGuiWindowFlags.NoMove | ImGuiWindowFlags.NoResize | ImGuiWindowFlags.NoCollapse | ImGuiWindowFlags.NoSavedSettings);
				Spinner("##spinning", 15, 6, ImGui.GetColorU32(ImGuiCol.ButtonHovered));
				ImGui.SameLine();
				ImGui.Text("Extracting assets. Please wait.");
				ImGui.Text(progress.title);
				if (progress.totalItems == 0) {
					ImGui.ProgressBar(0, ImVec2(0, 0));
				} else {
					ImGui.ProgressBar(cast(float)progress.completedItems / progress.totalItems, ImVec2(ImGui.GetContentRegionAvail().x, 0), format!"%s/%s"(progress.completedItems, progress.totalItems));
				}
			ImGui.End();
		}
		while (!extractionDone) {
			while (receiveTimeout(0.seconds,
				(bool) { extractionDone = true; },
				(const Progress msg) { progress = msg; }
			)) {}
			watchDog.pet();
			if (backend) {
				if (backend.processEvents() || backend.input.getState().exit) {
					exit(0);
				}
				backend.video.startFrame();
				renderExtractionUI();
				backend.video.finishFrame();
				backend.video.waitNextFrame();
			}
		}
	}
	void loadAssets(Modules...)(LoadFunction func) {
		import std.algorithm.sorting : sort;
		//import std.path : buildPath;
		PlanetArchive archive;
		if (assetsExist) {
			archive = assets;
		}
		const(ubyte)[][string] arrayAssets;
		foreach (asset; archive.entries) {
			bool matched;
			static foreach (Symbol; SymbolData!Modules) {
				if (asset.name.matches(Symbol.metadata)) {
					matched = true;
					auto data = loadROMAsset(asset.data, Symbol.metadata);
					static if (Symbol.metadata.array) {
						arrayAssets[asset.name] = data;
						Symbol.data = [];
					} else {
						tracef("Loading %s", asset.name);
						static if (Symbol.metadata.type == DataType.structured) {
							Symbol.data = (cast(const(char)[])data).fromString!(typeof(Symbol.data), YAML)(asset.name);
						} else {
							Symbol.data = cast(Symbol.ReadableElementType!())data;
						}
					}
				}
			}
			if (!matched) {
				func(asset.name, asset.data, backend);
			}
		}
		foreach (file; arrayAssets.keys.sort) {
			static foreach (Symbol; SymbolData!Modules) {
				static if (Symbol.metadata.array) {
					if (file.matches(Symbol.metadata)) {
						tracef("Loading %s", file);
						static if (Symbol.metadata.type == DataType.structured) {
							Symbol.data ~= (cast(const(char)[])arrayAssets[file]).fromString!(typeof(Symbol.data), YAML)(file);
						} else {
							Symbol.data ~= cast(Symbol.ReadableElementType!())arrayAssets[file];
						}
					}
				}
			}
		}
	}
	void runHook(string id) {
		if (auto matchingHooks = id in hooks) {
			for (int i = 0; i < matchingHooks.length; i++) {
				(*matchingHooks)[i].func();
				if ((*matchingHooks)[i].settings.type == HookType.once) {
					*matchingHooks = (*matchingHooks).remove(i);
				}
			}
		}
	}
	void registerHook(string id, HookDelegate hook, HookSettings settings = HookSettings.init) {
		hooks.require(id, []) ~= HookState(hook, settings);
	}
	private void prepareSRAM(uint slot, size_t size) {
		sramSlotBuffer.require(slot, () {
			auto buffer = new ubyte[](size);
			const name = saveFileName(slot);
			if (name.exists) {
				infof("Reading SRAM file %s", name);
				File(name, "r").rawRead(buffer);
			}
			return buffer;
		}());
	}

	ref T sram(T)(uint slot) {
		prepareSRAM(slot, T.sizeof);
		return (cast(T[])sramSlotBuffer[slot][0 .. T.sizeof])[0];
	}
	void commitSRAM() {
		foreach (slot, data; sramSlotBuffer) {
			const name = saveFileName(slot);
			infof("Writing %s", name);
			File(name, "wb").rawWrite(data);
		}
	}
	void deleteSlot(uint slot) {
		remove(saveFileName(slot));
	}
	private string saveFileName(uint slot) {
		return format!"%s.%s.sav"(gameID, slot);
	}
	private void renderUIElements() {
		UIState state;
		state.window = backend.video.getWindowState();
		const gameWidth = nativeResolution.width * settings.video.zoom;
		const gameHeight = nativeResolution.height * settings.video.zoom;
		void renderGameWindow(bool fill) {
			if (fill) {
				ImGui.GetStyle().WindowPadding = ImVec2(0, 0);
				ImGui.GetStyle().WindowBorderSize = 0;
				ImGui.SetNextWindowSize(ImGui.ImVec2(state.window.width.get(gameWidth), state.window.height.get(gameHeight)));
				ImGui.SetNextWindowPos(ImGui.ImVec2(0, 0));
				ImGui.Begin("Game", null, ImGuiWindowFlags.NoDecoration | ImGuiWindowFlags.NoInputs | ImGuiWindowFlags.NoBringToFrontOnFocus | ImGuiWindowFlags.NoSavedSettings);
			} else {
				ImGui.SetNextWindowSize(ImGui.ImVec2(gameWidth, gameHeight), ImGuiCond.FirstUseEver);
				ImGui.Begin("Game", null, ImGuiWindowFlags.NoScrollbar);
			}
			auto drawSize = ImGui.GetContentRegionAvail();
			if (settings.video.keepAspectRatio) {
				const scaleFactor = min(drawSize.x / cast(float)gameWidth, drawSize.y / cast(float)gameHeight);
				drawSize = ImGui.ImVec2(gameWidth * scaleFactor, gameHeight * scaleFactor);
			}
			ImGui.Image(backend.video.getRenderingTexture(), drawSize);
			ImGui.End();
		}
		if (renderUI) {
			renderGameWindow(!debuggingEnabled);
			if (debuggingEnabled) {
				int areaHeight;
				if (ImGui.BeginMainMenuBar()) {
					areaHeight = cast(int)ImGui.GetWindowSize().y;
					ImGui.EndMainMenuBar();
				}
				if (platformDebugMenu) {
					platformDebugMenu(state);
				}
				debuggingUI(state);
				if (debugMenu) {
					debugMenu(state);
				}
				if (platformDebugState) {
					ImGui.Begin("Platform", null, ImGuiWindowFlags.None);
					platformDebugState(state);
					ImGui.End();
				}
				if (debugState) {
					enum debugWidth = 500;
					ImGui.SetNextWindowSize(ImGui.ImVec2(debugWidth, state.window.height.get(0) - (areaHeight - 1)), ImGuiCond.FirstUseEver);
					ImGui.SetNextWindowPos(ImGui.ImVec2(0, areaHeight - 1), ImGuiCond.FirstUseEver);
					ImGui.Begin("Debugging");
					debugState(state);
					ImGui.End();
				}
			}
		}
	}
}

@system unittest {
	static struct FakeModule {
		static struct SomeStruct {
			ubyte a;
			int[] b;
			string c;
		}
		@ROMSource(0x0, 0x4)
		@Asset("test/bytes", DataType.raw)
		static ubyte[] sample;
		@([ROMSource(0x0, 0x1), ROMSource(0x1, 0x1), ROMSource(0x2, 0x1), ROMSource(0x3, 0x1)])
		@Asset("test/bytes2", DataType.raw)
		static ubyte[] sample2;
		@([ROMSource(0, 1), ROMSource(1, 3)])
		static immutable(ubyte[])[] sample3;
		@Asset("test/structure.yaml", DataType.structured)
		static SomeStruct someStruct = SomeStruct(4, [1, 2, 3], "blah");
		@Asset("test/structures.yaml", DataType.structured)
		static SomeStruct[] someStructArray = [SomeStruct(2, [2, 3], "bleh"), SomeStruct(6, [222, 3], "!!!")];
	}
	immutable(ubyte)[] fakeData = [0, 1, 2, 3];
	static void extractor(scope AddFileFunction addFile, scope ProgressUpdateFunction, immutable(ubyte)[]) {
		addFile("big test.bin", [4, 6, 8, 10]);
	}
	static count = 0;
	static void loader(const scope char[] name, const scope ubyte[] data, scope PlatformBackend) {
		assert(name == "big test.bin");
		assert(data == [4, 6, 8, 10]);
		count++;
	}
	PlatformCommon sample;
	sample.gameID = "TEST";
	sample.handleAssets!(FakeModule)(fakeData, &extractor, &loader, toFilesystem: false);
	assert("TEST.planet".exists);
	assert(count == 1);
	scope(exit) std.file.remove("TEST.planet");
	assert(FakeModule.sample == [0, 1, 2, 3]);
	assert(FakeModule.sample2 == [0, 1, 2, 3]);
	assert(FakeModule.sample3 == [[0], [1, 2, 3]]);
	assert(FakeModule.someStruct == FakeModule.SomeStruct(4, [1, 2, 3], "blah"));
	assert(FakeModule.someStructArray == [FakeModule.SomeStruct(2, [2, 3], "bleh"), FakeModule.SomeStruct(6, [222, 3], "!!!")]);
	FakeModule.sample = [];
	FakeModule.sample2 = [];
	FakeModule.sample3 = [];
	FakeModule.someStruct = FakeModule.SomeStruct(2, [], "???");
	FakeModule.someStructArray = [];
	sample.handleAssets!(FakeModule)(fakeData, &extractor, &loader, toFilesystem: false);
	assert(FakeModule.sample == [0, 1, 2, 3]);
	assert(FakeModule.sample2 == [0, 1, 2, 3]);
	assert(FakeModule.sample3 == [[0], [1, 2, 3]]);
	assert(FakeModule.someStruct == FakeModule.SomeStruct(4, [1, 2, 3], "blah"));
	assert(FakeModule.someStructArray == [FakeModule.SomeStruct(2, [2, 3], "bleh"), FakeModule.SomeStruct(6, [222, 3], "!!!")]);
	assert(count == 2);
}

mixin template PlatformCommonForwarders() {
	DebugFunction debugMenuRenderer;
	DebugFunction gameStateMenu;
	void commonInitialization(Resolution resolution, PlatformCommon.EntryPoint entry, Backend backendType) {
		platform.nativeResolution = resolution;
		platform.initialize(entry, backendType);
		platform.debugMenu = debugMenuRenderer;
		platform.platformDebugMenu = &commonDebugMenu;
		platform.debugState = gameStateMenu;
		platform.platformDebugState = &commonDebugState;
	}
	auto ref gameID() {
		return platform.gameID;
	}
	void run() {
		if (settings.debugging) {
			platform.enableDebuggingFeatures();
		}
		platform.showUI();
		while (true) {
			if (platform.runFrame({ static if (__traits(hasMember, this, "interruptHandlerVBlank")) { interruptHandlerVBlank(); } }, { renderer.draw(); })) {
				break;
			}
			copyInputState(platform.inputState);
		}
	}
	void wait() {
		platform.wait({ interruptHandlerVBlank(); });
	}
	T loadSettings(T)() {
		auto allSettings = platform.loadSettings!(Settings, T)();
		settings = allSettings.system;
		return allSettings.game;
	}
	void saveSettings(T)(T gameSettings) {
		platform.saveSettings(settings, gameSettings);
	}
	void runHook(string id) {
		platform.runHook(id);
	}
	void registerHook(string id, HookFunction hook, HookSettings settings = HookSettings.init) {
		platform.registerHook(id, hook.toDelegate(), settings);
	}
	void registerHook(string id, HookDelegate hook, HookSettings settings = HookSettings.init) {
		platform.registerHook(id, hook, settings);
	}
	void handleAssets(Modules...)(ExtractFunction extractor = null, LoadFunction loader = null, bool toFilesystem = false) {
		platform.handleAssets!Modules(romData, extractor, loader, toFilesystem);
	}
	void loadWAV(const(ubyte)[] data) {
		platform.backend.audio.loadWAV(data);
	}
	ref T sram(T)(uint slot) {
		return platform.sram!T(slot);
	}
	void commitSRAM() {
		platform.commitSRAM();
	}
	void deleteSlot(uint slot) {
		platform.deleteSlot(slot);
	}
	void playbackDemo(const RecordedInputState[] demo) @safe pure {
		platform.playbackDemo(demo);
	}
}

enum HookType {
	once,
	repeat
}

alias HookDelegate = void delegate();
alias HookFunction = void function();
struct HookState {
	HookDelegate func;
	HookSettings settings;
}
struct HookSettings {
	HookType type;
}

private struct FullSettings(SystemSettings, GameSettings) {
	SystemSettings system;
	GameSettings game;
	BackendSettings backend;
}

/// Make sure we only have a console window when needed.
void detachConsoleIfUnneeded() {
	// windows handles consoles awkwardly. with the WINDOWS subsystem, manual detection is necessary to get a console with STDOUT, and even then it doesn't seem to work seamlessly.
	// With the CONSOLE subsystem, a console window is ALWAYS created. At least we're able to detach from it immediately if there wasn't one there before, which is mostly invisible.
	// It still messes with focus if you're using windows terminal, but that's tolerable, at least...
	version(Windows) {
		import core.sys.windows.wincon : CONSOLE_SCREEN_BUFFER_INFO, FreeConsole, GetConsoleScreenBufferInfo;
		import core.sys.windows.winbase : GetStdHandle, STD_OUTPUT_HANDLE;
		import std.windows.syserror : wenforce;
		CONSOLE_SCREEN_BUFFER_INFO info;
		wenforce(GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &info), "Buffer info retrieval failed");
		// (0, 0) cursor coords means we probably don't have an existing console, detach
		// might still happen if console was cleared immediately before running, but that's an unlikely case
		if ((info.dwCursorPosition.X == 0) && (info.dwCursorPosition.Y == 0)) {
			wenforce(FreeConsole(), "Console detaching failed");
		}
	}
}

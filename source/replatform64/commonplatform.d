module replatform64.commonplatform;

import replatform64.assets;
import replatform64.backend.common;
import replatform64.common;
import replatform64.dumping;
import replatform64.framestat;
import replatform64.planet;
import replatform64.ui;
import replatform64.watchdog;

import imgui.flamegraph;

import core.stdc.stdlib;
import core.thread;
import std.algorithm.comparison;
import std.algorithm.iteration;
import std.algorithm.mutation;
import std.concurrency;
import std.conv;
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
	void initialize(void delegate() dg, Backend backendType = Backend.autoSelect) {
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
		if (settings.video.window.width == settings.video.window.width.max) {
			//resetWindowSize(true);
		}
	}
	void debuggingUI(const UIState) {
		if (ImGui.BeginMainMenuBar()) {
			if (ImGui.BeginMenu("Debugging")) {
				ImGui.MenuItem("Enable metrics", null, &metricsEnabled);
				ImGui.MenuItem("Enable UI metrics", null, &uiMetricsEnabled);
				if (ImGui.MenuItem("Force crash")) {
					assert(0, "Forced crash");
				}
				ImGui.EndMenu();
			}
			ImGui.EndMainMenuBar();
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
				Throwable t = game.call(Fiber.Rethrow.no);
				if(t) {
					writeDebugDump(t.msg, t.info);
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

		if (inputState.pause) {
			paused = !paused;
			inputState.pause = false;
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
	bool assetsExist() {
		return (gameID~".planet").exists;
	}
	PlanetArchive assets() {
		if ((gameID~".planet").exists) {
			return PlanetArchive.read(cast(ubyte[])read(gameID~".planet"));
		}
		throw new Exception("Not found");
	}
	void saveAssets(PlanetArchive archive) {
		archive.write(File(gameID~".planet", "w").lockingBinaryWriter);
	}
	void extractAssets(Modules...)(ExtractFunction extractor, immutable(ubyte)[] data) {
		void extractAllData(Tid main, immutable(ubyte)[] rom) {
		    PlanetArchive archive;
		    send(main, "Loading ROM");

		    //handle data that can just be copied as-is
		    static foreach (asset; SymbolData!Modules) {{
		        static foreach (i, element; asset.sources) {
			        {
						enum str = "Extracting " ~ asset.name;
			            send(main, Progress(str, i, cast(uint)asset.sources.length));
			        }
			        archive.addFile(asset.name, rom[element.offset .. element.offset + element.length]);
		        }
		    }}

		    // extract extra game data that needs special handling
			extractor(archive, (str) { send(main, str); }, rom);

		    // write the archive
		    saveAssets(archive);

		    // done
		    send(main, true);
		}
		auto extractorThread = spawn(cast(shared)&extractAllData, thisTid, data);
		bool extractionDone;
		auto progress = Progress("Initializing");
		void renderExtractionUI() {
			ImGui.SetNextWindowPos(ImGui.GetMainViewport().GetCenter(), ImGuiCond.Appearing, ImVec2(0.5f, 0.5f));
			ImGui.Begin("Creating planet archive", null, ImGuiWindowFlags.NoMove | ImGuiWindowFlags.NoResize | ImGuiWindowFlags.NoCollapse | ImGuiWindowFlags.NoSavedSettings);
				Spinner("##spinning", 15, 6,  ImGui.GetColorU32(ImGuiCol.ButtonHovered));
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
			assert(backend);
			if (backend.processEvents() || backend.input.getState().exit) {
				exit(0);
			}
			backend.video.startFrame();
			watchDog.pet();
			renderExtractionUI();
			backend.video.finishFrame();
			backend.video.waitNextFrame();
		}
	}
	void loadAssets(Modules...)(LoadFunction func) {
		const archive = assets;
		tracef("Loaded %s assets", archive.entries.length);
		foreach (asset; archive.entries) {
			const data = archive.getData(asset);
		    sw: switch (asset.name) {
		        static foreach (Symbol; SymbolData!Modules) {
		            case Symbol.name:
		                static if (Symbol.array) {
		                    Symbol.data ~= cast(typeof(Symbol.data[0]))data;
		                } else {
		                    Symbol.data = cast(typeof(Symbol.data))(data);
		                }
		                break sw;
		        }
		        default:
		            func(archive, asset, backend);
		            break;
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
		if (renderUI) {
			if (debuggingEnabled) {
				ImGui.SetNextWindowSize(ImGui.ImVec2(gameWidth, gameHeight), ImGuiCond.FirstUseEver);
				ImGui.Begin("Game", null, ImGuiWindowFlags.NoScrollbar);
				ImGui.Image(backend.video.getRenderingTexture(), ImGui.GetContentRegionAvail());
				ImGui.End();
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
					ImGui.SetNextWindowSize(ImGui.ImVec2(debugWidth, state.window.height - (areaHeight - 1)), ImGuiCond.FirstUseEver);
					ImGui.SetNextWindowPos(ImGui.ImVec2(0, areaHeight - 1), ImGuiCond.FirstUseEver);
					ImGui.Begin("Debugging");
					debugState(state);
					ImGui.End();
				}
			} else {
				ImGui.GetStyle().WindowPadding = ImVec2(0, 0);
				ImGui.GetStyle().WindowBorderSize = 0;
				ImGui.SetNextWindowSize(ImGui.ImVec2(state.window.width, state.window.height));
				ImGui.SetNextWindowPos(ImGui.ImVec2(0, 0));
				ImGui.Begin("Game", null, ImGuiWindowFlags.NoDecoration | ImGuiWindowFlags.NoInputs | ImGuiWindowFlags.NoBringToFrontOnFocus | ImGuiWindowFlags.NoSavedSettings);
				auto drawSize = ImGui.GetContentRegionAvail();
				if (settings.video.keepAspectRatio) {
					const scaleFactor = min(state.window.width / cast(float)gameWidth, state.window.height / cast(float)gameHeight);
					drawSize = ImGui.ImVec2(gameWidth * scaleFactor, gameHeight * scaleFactor);
				}
				ImGui.Image(backend.video.getRenderingTexture(), drawSize);
				ImGui.End();
			}
		}

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

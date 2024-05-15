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
import std.algorithm.iteration;
import std.algorithm.mutation;
import std.concurrency;
import std.conv;
import std.file;
import std.format;
import std.logger;
import std.stdio;
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
	private const(RecordedInputState)[] inputPlayback;
	private uint inputPlaybackFrameCounter;
	private HookState[][string] hooks;
	private ubyte[][uint] sramSlotBuffer;
	private bool metricsEnabled;
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
		settings.video = backend.video.getUIState();
		Settings(systemSettings, gameSettings, settings).toFile!YAML(settingsFile);
	}
	void initialize(void delegate() dg, Backend backendType = Backend.autoSelect) {
		this.game = new Fiber(dg);
		backend = loadBackend(backendType, settings);
		backend.video.hideUI();
		startWatchDog();
	}
	void installAudioCallback(void* data, AudioCallback callback) @safe {
		backend.audio.installCallback(data, callback);
	}
	void enableDebuggingFeatures() @safe {
		backend.video.setDebuggingFunctions(&debuggingUI, debugMenu, platformDebugMenu, debugState, platformDebugState);
	}
	void debuggingUI(const UIState) {
		if (ImGui.BeginMainMenuBar()) {
			if (ImGui.BeginMenu("Debugging")) {
				ImGui.MenuItem("Enable metrics", null, &metricsEnabled);
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
	}
	void showUI() {
		backend.video.showUI();
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
			draw();
			frameStatTracker.checkpoint(FrameStatistic.ppu);
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
		    const(char)[] last;

		    //handle data that can just be copied as-is
		    static foreach (asset; SymbolData!Modules) {{
		        static foreach (i, element; asset.sources) {
			        if (last != asset.name) {
			            last = asset.name;
			            immutable str = text("Extracting ", asset.name);
			            send(main, str);
			        }
			        infof("Extracting %s", asset.name);
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
		string lastMessage = "Initializing";
		void renderExtractionUI() {
			ImGui.SetNextWindowPos(ImGui.GetMainViewport().GetCenter(), ImGuiCond.Appearing, ImVec2(0.5f, 0.5f));
			ImGui.Begin("Creating planet archive", null, ImGuiWindowFlags.NoMove | ImGuiWindowFlags.NoResize | ImGuiWindowFlags.NoCollapse);
				Spinner("##spinning", 15, 6,  ImGui.GetColorU32(ImGuiCol.ButtonHovered));
				ImGui.SameLine();
				ImGui.Text("Extracting assets. Please wait.");
				ImGui.Text(lastMessage);
			ImGui.End();
		}
		while (!extractionDone) {
			receiveTimeout(0.seconds,
				(bool) { extractionDone = true; },
				(string msg) { lastMessage = msg; }
			);
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
		            func(archive, asset);
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

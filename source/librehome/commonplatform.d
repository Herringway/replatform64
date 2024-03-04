module librehome.commonplatform;

import librehome.backend.common;
import librehome.dumping;
import librehome.framestat;
import librehome.planet;
import librehome.watchdog;

import core.thread;
import std.algorithm.mutation;
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
	private HookState[][string] hooks;
	private ubyte[][uint] sramSlotBuffer;
	auto loadSettings(SystemSettings, GameSettings)() {
		alias Settings = FullSettings!(SystemSettings, GameSettings);
		if (!settingsFile.exists) {
			Settings defaults;
			defaults.toFile!YAML(settingsFile);
		}
		auto result = fromFile!(Settings, YAML)(settingsFile);
		settings = result.backend;
		return result;
	}

	void saveSettings(SystemSettings, GameSettings)(SystemSettings systemSettings, GameSettings gameSettings) {
		alias Settings = FullSettings!(SystemSettings, GameSettings);
		settings.ui = backend.video.getUIState();
		Settings(systemSettings, gameSettings, settings).toFile!YAML(settingsFile);
	}
	void initialize(void delegate() dg) {
		this.game = new Fiber(dg);
		backend = loadBackend(settings);
		backend.video.hideUI();
		//startWatchDog();
	}
	void installAudioCallback(void* data, AudioCallback callback) {
		backend.audio.installCallback(data, callback);
	}
	void enableDebuggingFeatures() {
		backend.video.setDebuggingFunctions(debugMenu, platformDebugMenu, debugState, platformDebugState);
	}
	void showUI() {
		backend.video.showUI();
	}
	bool runFrame(scope void delegate() interrupt, scope void delegate() draw) {
		// pet the dog each frame so it knows we're ok
		watchDog.pet();
		frameStatTracker.startFrame();
		if (backend.processEvents()) {
			return true;
		}
		inputState = backend.input.getState();
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

		if (!inputState.fastForward) {
			backend.video.waitNextFrame();
		}

		if (inputState.pause) {
			paused = !paused;
			inputState.pause = false;
		}
		frameStatTracker.endFrame();
		return false;
	}
	void wait() {
		Fiber.yield();
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

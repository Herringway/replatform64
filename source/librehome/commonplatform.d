module librehome.commonplatform;

import librehome.backend.common;
import librehome.dumping;
import librehome.framestat;
import librehome.watchdog;

import core.thread;
import std.file;
import siryul;

enum settingsFile = "settings.yaml";

struct PlatformCommon {
	PlatformBackend backend;
	InputState inputState;
	bool paused;
	Fiber game;
	BackendSettings settings;
	DebugFunction debugMenu;
	DebugFunction platformDebugMenu;
	DebugFunction debugState;
	DebugFunction platformDebugState;
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
	void initialize(Fiber game) {
		this.game = game;
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
}

private struct FullSettings(SystemSettings, GameSettings) {
	SystemSettings system;
	GameSettings game;
	BackendSettings backend;
}

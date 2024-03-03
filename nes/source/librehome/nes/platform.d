module librehome.nes.platform;

import librehome.backend.common;
import librehome.backend.sdl2;
import librehome.common;
import librehome.nes.apu;
import librehome.nes.ppu;
import librehome.nes.renderer;
import librehome.planet;
import librehome.ui;
import librehome.watchdog;

import siryul;

import core.thread;
import std.file;

enum settingsFile = "settings.yaml";

struct Settings {
	VideoSettings video;
	InputSettings input;
	bool debugging;
}

enum Register {
	PPUCTRL = 0x2000,
	PPUMASK = 0x2001,
	PPUSTATUS = 0x2002,
	OAMADDR = 0x2003,
	OAMDATA = 0x2004,
	PPUSCROLL = 0x2005,
	PPUADDR = 0x2006,
	PPUDATA = 0x2007,
	SQ1 = 0x4000,
	SQ1_VOL = 0x4000,
	SQ1_SWEEP = 0x4001,
	SQ1_LO = 0x4002,
	SQ1_HI = 0x4003,
	SQ2 = 0x4004,
	SQ2_VOL = 0x4004,
	SQ2_SWEEP = 0x4005,
	SQ2_LO = 0x4006,
	SQ2_HI = 0x4007,
	TRI = 0x4008,
	TRI_LINEAR = 0x4008,
	TRI_LO = 0x400A,
	TRI_HI = 0x400B,
	NOISE = 0x400C,
	NOISE_VOL = 0x400C,
	NOISE_LO = 0x400E,
	NOISE_HI = 0x400F,
	DMC = 0x4010,
	DMC_FREQ = 0x4010,
	DMC_RAW = 0x4011,
	DMC_START = 0x4012,
	DMC_LEN = 0x4013,
	OAMDMA = 0x4014,
	SND_CHN = 0x4015,
	JOY1 = 0x4016,
	JOY2 = 0x4017,
}

struct NES {
	void function() entryPoint;
	void function() interruptHandler;
	string title;
	DebugFunction debugMenuRenderer;
	bool interruptsEnabled;

	private Settings settings;
	private PlatformBackend backend;
	private APU apu;
	private Renderer renderer;

	void initialize() {
		backend = new SDL2Platform;
		backend.initialize();
		backend.audio.initialize(&apu, &audioCallback, defaultFrequency, 2, AUDIO_BUFFER_LENGTH);
		backend.input.initialize(settings.input);
		renderer.initialize(title, settings.video, backend.video, settings.debugging, debugMenuRenderer, &commonNESDebugging);
	}
	int run() {
		auto game = new Fiber({ entryPoint(); });
		bool paused;

		bool pauseWasPressed;
		while (true) {
			if (backend.processEvents()) {
				break;
			}
			auto input = backend.input.getState();
			//copyInputState(input);
			if (!paused) {
				if (auto t = game.call(Fiber.Rethrow.no)) {
					writeDebugDump(t.msg, t.info);
					return 1;
				}
				if (game.state == Fiber.State.TERM) {
					break;
				}
				if (interruptsEnabled) {
					interruptHandler();
				}
			}
			renderer.draw();
			if (input.pause && !pauseWasPressed) {
				paused ^= true;
			}
			if (!input.fastForward) {
				renderer.waitNextFrame();
			}
			pauseWasPressed = input.pause;
		}
		return 0;
	}
	void wait() {
		Fiber.yield();
	}
	bool assetsExist() {
		return false;
	}
	void extractAssets(ExtractFunction) {}

	T loadSettings(T)() {
		static struct FullSettings {
			Settings system;
			T game;
		}
		if (!settingsFile.exists) {
			FullSettings defaults;
			//defaults.system.input = getDefaultInputSettings();
			defaults.toFile!YAML(settingsFile);
		}
		auto allSettings = fromFile!(FullSettings, YAML)(settingsFile);
		settings = allSettings.system;
		return allSettings.game;
	}
	void saveSettings(T)(T gameSettings) {
		static struct FullSettings {
			Settings system;
			T game;
		}
		FullSettings(settings, gameSettings).toFile!YAML(settingsFile);
	}
	private void commonNESDebugging(const UIState state) {}
	void PPUCTRL(ubyte val) {
		renderer.ppu.writeRegister(Register.PPUCTRL, val);
	}
	void PPUMASK(ubyte val) {
		renderer.ppu.writeRegister(Register.PPUMASK, val);
	}
	void PPUSTATUS(ubyte val) {
		renderer.ppu.writeRegister(Register.PPUSTATUS, val);
	}
	void OAMADDR(ubyte val) {
		renderer.ppu.writeRegister(Register.OAMADDR, val);
	}
	void OAMDATA(ubyte val) {
		renderer.ppu.writeRegister(Register.OAMDATA, val);
	}
	void PPUSCROLL(ubyte val) {
		renderer.ppu.writeRegister(Register.PPUSCROLL, val);
	}
	void PPUADDR(ubyte val) {
		renderer.ppu.writeRegister(Register.PPUADDR, val);
	}
	void PPUDATA(ubyte val) {
		renderer.ppu.writeRegister(Register.PPUDATA, val);
	}
	void SQ1(ubyte val) {
		apu.writeRegister(Register.SQ1, val);
	}
	void SQ1_VOL(ubyte val) {
		apu.writeRegister(Register.SQ1_VOL, val);
	}
	void SQ1_SWEEP(ubyte val) {
		apu.writeRegister(Register.SQ1_SWEEP, val);
	}
	void SQ1_LO(ubyte val) {
		apu.writeRegister(Register.SQ1_LO, val);
	}
	void SQ1_HI(ubyte val) {
		apu.writeRegister(Register.SQ1_HI, val);
	}
	void SQ2(ubyte val) {
		apu.writeRegister(Register.SQ2, val);
	}
	void SQ2_VOL(ubyte val) {
		apu.writeRegister(Register.SQ2_VOL, val);
	}
	void SQ2_SWEEP(ubyte val) {
		apu.writeRegister(Register.SQ2_SWEEP, val);
	}
	void SQ2_LO(ubyte val) {
		apu.writeRegister(Register.SQ2_LO, val);
	}
	void SQ2_HI(ubyte val) {
		apu.writeRegister(Register.SQ2_HI, val);
	}
	void TRI(ubyte val) {
		apu.writeRegister(Register.TRI, val);
	}
	void TRI_LINEAR(ubyte val) {
		apu.writeRegister(Register.TRI_LINEAR, val);
	}
	void TRI_LO(ubyte val) {
		apu.writeRegister(Register.TRI_LO, val);
	}
	void TRI_HI(ubyte val) {
		apu.writeRegister(Register.TRI_HI, val);
	}
	void NOISE(ubyte val) {
		apu.writeRegister(Register.NOISE, val);
	}
	void NOISE_VOL(ubyte val) {
		apu.writeRegister(Register.NOISE_VOL, val);
	}
	void NOISE_LO(ubyte val) {
		apu.writeRegister(Register.NOISE_LO, val);
	}
	void NOISE_HI(ubyte val) {
		apu.writeRegister(Register.NOISE_HI, val);
	}
	void DMC(ubyte val) {
		apu.writeRegister(Register.DMC, val);
	}
	void DMC_FREQ(ubyte val) {
		apu.writeRegister(Register.DMC_FREQ, val);
	}
	void DMC_RAW(ubyte val) {
		apu.writeRegister(Register.DMC_RAW, val);
	}
	void DMC_START(ubyte val) {
		apu.writeRegister(Register.DMC_START, val);
	}
	void DMC_LEN(ubyte val) {
		apu.writeRegister(Register.DMC_LEN, val);
	}
	void SND_CHN(ubyte val) {
		apu.writeRegister(Register.SND_CHN, val);
	}
	void JOY1(ubyte val) {
	}
	void JOY2(ubyte val) {
	}
	void setNametableMirroring(MirrorType type) {
		renderer.ppu.mirrorMode = type;
	}
}

module replatform64.nes.platform;

import replatform64.assets;
import replatform64.backend.common;
import replatform64.commonplatform;
import replatform64.nes.apu;
import replatform64.nes.ppu;
import replatform64.nes.renderer;
import replatform64.registers;
import replatform64.ui;
import replatform64.util;

import siryul;

import std.file;
import std.functional;

enum settingsFile = "settings.yaml";

struct Settings {
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
	void function() interruptHandlerVBlank;
	deprecated("Use interruptHandlerVBlank instead") alias interruptHandler = interruptHandlerVBlank;
	string title;
	bool interruptsEnabled;

	private Settings settings;
	private APU apu;
	private Renderer renderer;
	private immutable(ubyte)[] romData;

	private PlatformCommon platform;

	mixin PlatformCommonForwarders;

	void initialize(Backend backendType = Backend.autoSelect) {
		commonInitialization(Resolution(PPU.width, PPU.height), { entryPoint(); }, backendType);
		renderer.initialize(title, platform.backend.video);
		platform.installAudioCallback(&apu, &audioCallback);
	}
	private void copyInputState(InputState state) @safe pure {}
	private void commonDebugMenu(const UIState state) {}
	private void commonDebugState(const UIState state) {}
	mixin RegisterRedirect!("PPUCTRL", "renderer", Register.PPUCTRL);
	mixin RegisterRedirect!("PPUMASK", "renderer", Register.PPUMASK);
	mixin RegisterRedirect!("PPUSTATUS", "renderer", Register.PPUSTATUS);
	mixin RegisterRedirect!("OAMADDR", "renderer", Register.OAMADDR);
	mixin RegisterRedirect!("OAMDATA", "renderer", Register.OAMDATA);
	mixin RegisterRedirect!("PPUSCROLL", "renderer", Register.PPUSCROLL);
	mixin RegisterRedirect!("PPUADDR", "renderer", Register.PPUADDR);
	mixin RegisterRedirect!("PPUDATA", "renderer", Register.PPUDATA);
	mixin RegisterRedirect!("SQ1", "apu", Register.SQ1);
	mixin RegisterRedirect!("SQ1_VOL", "apu", Register.SQ1_VOL);
	mixin RegisterRedirect!("SQ1_SWEEP", "apu", Register.SQ1_SWEEP);
	mixin RegisterRedirect!("SQ1_LO", "apu", Register.SQ1_LO);
	mixin RegisterRedirect!("SQ1_HI", "apu", Register.SQ1_HI);
	mixin RegisterRedirect!("SQ2", "apu", Register.SQ2);
	mixin RegisterRedirect!("SQ2_VOL", "apu", Register.SQ2_VOL);
	mixin RegisterRedirect!("SQ2_SWEEP", "apu", Register.SQ2_SWEEP);
	mixin RegisterRedirect!("SQ2_LO", "apu", Register.SQ2_LO);
	mixin RegisterRedirect!("SQ2_HI", "apu", Register.SQ2_HI);
	mixin RegisterRedirect!("TRI", "apu", Register.TRI);
	mixin RegisterRedirect!("TRI_LINEAR", "apu", Register.TRI_LINEAR);
	mixin RegisterRedirect!("TRI_LO", "apu", Register.TRI_LO);
	mixin RegisterRedirect!("TRI_HI", "apu", Register.TRI_HI);
	mixin RegisterRedirect!("NOISE", "apu", Register.NOISE);
	mixin RegisterRedirect!("NOISE_VOL", "apu", Register.NOISE_VOL);
	mixin RegisterRedirect!("NOISE_LO", "apu", Register.NOISE_LO);
	mixin RegisterRedirect!("NOISE_HI", "apu", Register.NOISE_HI);
	mixin RegisterRedirect!("DMC", "apu", Register.DMC);
	mixin RegisterRedirect!("DMC_FREQ", "apu", Register.DMC_FREQ);
	mixin RegisterRedirect!("DMC_RAW", "apu", Register.DMC_RAW);
	mixin RegisterRedirect!("DMC_START", "apu", Register.DMC_START);
	mixin RegisterRedirect!("DMC_LEN", "apu", Register.DMC_LEN);
	mixin RegisterRedirect!("SND_CHN", "apu", Register.SND_CHN);
	void JOY1(ubyte val) {
	}
	void JOY2(ubyte val) {
	}
	void setNametableMirroring(MirrorType type) {
		renderer.ppu.mirrorMode = type;
	}
}

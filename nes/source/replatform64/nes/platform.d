module replatform64.nes.platform;

import replatform64.nes.apu;
import replatform64.nes.hardware;
import replatform64.nes.ppu;
import replatform64.nes.renderer;

import replatform64.assets;
import replatform64.backend.common;
import replatform64.commonplatform;
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
	string title;
	bool interruptsEnabled;
	enum width = Renderer.width;
	enum height = Renderer.height;

	private Settings settings;
	private APU apu;
	private Renderer renderer;
	private immutable(ubyte)[] romData;
	private ubyte[2] pads;

	private PlatformCommon platform;

	mixin PlatformCommonForwarders;

	void initialize(Backend backendType = Backend.autoSelect) {
		commonInitialization(Resolution(PPU.width, PPU.height), { entryPoint(); }, backendType);
		renderer.initialize(title, platform.backend.video);
		platform.installAudioCallback(&apu, &audioCallback);
		platform.registerMemoryRange("CHR", renderer.ppu.chr[]);
		platform.registerMemoryRange("Nametable", renderer.ppu.nametable[]);
		platform.registerMemoryRange("Palette", renderer.ppu.palette[]);
	}
	private void copyInputState(InputState state) @safe pure {
		pads = 0;
		foreach (idx, ref pad; pads) {
			if (platform.inputState.controllers[idx] & ControllerMask.b) { pad |= Pad.b; }
			if (platform.inputState.controllers[idx] & ControllerMask.a) { pad |= Pad.a; }
			if (platform.inputState.controllers[idx] & ControllerMask.start) { pad |= Pad.start; }
			if (platform.inputState.controllers[idx] & ControllerMask.select) { pad |= Pad.select; }
			if (platform.inputState.controllers[idx] & ControllerMask.up) { pad |= Pad.up; }
			if (platform.inputState.controllers[idx] & ControllerMask.down) { pad |= Pad.down; }
			if (platform.inputState.controllers[idx] & ControllerMask.left) { pad |= Pad.left; }
			if (platform.inputState.controllers[idx] & ControllerMask.right) { pad |= Pad.right; }
		}
	}
	ubyte getControllerState(ubyte playerID) const @safe pure {
		return pads[playerID];
	}
	private void commonDebugMenu(const UIState state) {}
	private void commonDebugState(const UIState state) {
		if (ImGui.BeginTabBar("platformdebug")) {
			if (ImGui.BeginTabItem("PPU")) {
				renderer.ppu.debugUI(state, platform.backend.video);
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("APU")) {
				apu.debugUI(state, platform.backend.video);
				ImGui.EndTabItem();
			}
			ImGui.EndTabBar();
		}
	}
	void writeRegisterPlatform(ushort addr, ubyte value) {
		if ((addr >= Register.PPUCTRL) && (addr <= Register.PPUDATA)) {
			renderer.writeRegister(addr, value);
		} else if (((addr >= Register.SQ1) && (addr <= Register.DMC_LEN)) || (addr == Register.SND_CHN)) {
			apu.writeRegister(addr, value);
		} else {
			assert(0, "Unknown/unsupported write");
		}
	}
	ubyte readRegister(ushort addr) {
		if ((addr >= Register.PPUCTRL) && (addr <= Register.PPUDATA)) {
			return renderer.readRegister(addr);
		} else if (((addr >= Register.SQ1) && (addr <= Register.DMC_LEN)) || (addr == Register.SND_CHN)) {
			return apu.readRegister(addr);
		} else {
			assert(0, "Unknown/unsupported write");
		}
	}
	void JOY1(ubyte val) {
	}
	void JOY2(ubyte val) {
	}
	void setNametableMirroring(MirrorType type) {
		renderer.ppu.mirrorMode = type;
	}
	void handleOAMDMA(const(ubyte)[] src, ushort dest) {
		const data = cast(OAMEntry[])src;
		handleOAMDMA(data, dest);
	}
	void handleOAMDMA(const(OAMEntry)[] src, ushort dest) {
		renderer.ppu.oam[0 .. src.length] = src;
	}
}

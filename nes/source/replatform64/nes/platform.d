module replatform64.nes.platform;

import replatform64.nes.hardware;

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

struct NES {
	void function() entryPoint;
	void function() interruptHandlerVBlank;
	string title;
	string sourceFile;
	bool interruptsEnabled;
	enum width = PPU.width;
	enum height = PPU.height;
	enum renderWidth = width;
	enum renderHeight = height;
	alias RenderPixelFormat = PixelFormatOf!(PPU.ColourFormat);

	private Settings settings;
	private immutable(ubyte)[] originalData;
	private APU apu;
	private PPU ppu;
	private ubyte[2] pads;

	private PlatformCommon platform;

	mixin PlatformCommonForwarders;

	void initialize(Backend backendType = Backend.autoSelect) {
		commonInitialization(Resolution(PPU.width, PPU.height), { entryPoint(); }, backendType);

		ppu.chr = new ubyte[](0x2000);
		ppu.nametable = new ubyte[](0x1000);

		platform.installAudioCallback(&apu, &audioCallback);
		platform.registerMemoryRange("CHR", ppu.chr[]);
		platform.registerMemoryRange("Nametable", ppu.nametable[]);
		platform.registerMemoryRange("Palette", ppu.palette[]);
	}
	auto preDraw() => interruptHandlerVBlank();
	auto draw()  {
		Texture texture;
		platform.backend.video.getDrawingTexture(texture);
		ppu.render(texture.asArray2D!(PPU.ColourFormat));
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
	private void commonDebugMenu(UIState state) {}
	private void commonDebugState(UIState state) {
		if (ImGui.BeginTabBar("platformdebug")) {
			if (ImGui.BeginTabItem("PPU")) {
				ppu.debugUI(state);
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("APU")) {
				apu.debugUI(state);
				ImGui.EndTabItem();
			}
			ImGui.EndTabBar();
		}
	}
	void writeRegisterPlatform(ushort addr, ubyte value) {
		if ((addr >= Register.PPUCTRL) && (addr <= Register.PPUDATA)) {
			ppu.writeRegister(addr, value);
		} else if (((addr >= Register.SQ1) && (addr <= Register.DMC_LEN)) || (addr == Register.SND_CHN)) {
			apu.writeRegister(addr, value);
		} else {
			assert(0, "Unknown/unsupported write");
		}
	}
	ubyte readRegister(ushort addr) {
		if ((addr >= Register.PPUCTRL) && (addr <= Register.PPUDATA)) {
			return ppu.readRegister(addr);
		} else if (((addr >= Register.SQ1) && (addr <= Register.DMC_LEN)) || (addr == Register.SND_CHN)) {
			return apu.readRegister(addr);
		} else {
			assert(0, "Unknown/unsupported write");
		}
	}
	immutable(ubyte)[] romData() {
		if (!originalData && sourceFile.exists) {
			originalData = (cast(ubyte[])read(sourceFile)).idup;
		}
		return originalData;
	}
	void JOY1(ubyte val) {
	}
	void JOY2(ubyte val) {
	}
	void setNametableMirroring(MirrorType type) {
		ppu.mirrorMode = type;
	}
	void handleOAMDMA(const(ubyte)[] src, ushort dest) {
		const data = cast(OAMEntry[])src;
		handleOAMDMA(data, dest);
	}
	void handleOAMDMA(const(OAMEntry)[] src, ushort dest) {
		ppu.oam[0 .. src.length] = src;
	}
}

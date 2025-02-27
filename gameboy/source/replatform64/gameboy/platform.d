module replatform64.gameboy.platform;

import replatform64.gameboy.hardware;
import replatform64.gameboy.renderer;

import replatform64.assets;
import replatform64.backend.common;
import replatform64.commonplatform;
import replatform64.dumping;
import replatform64.registers;
import replatform64.ui;
import replatform64.util;

import d_imgui.imgui_h;
import ImGui = d_imgui;
import imgui.hexeditor;

import std.file;
import std.format;
import std.functional;
import std.logger;
import std.random;
import std.stdio;

import siryul;

enum GBPalette {
	dmg,
	pocket,
}

struct Settings {
	bool yamlSave;
	bool debugging;
	GBPalette gbPalette = GBPalette.pocket;
}

enum settingsFile = "settings.yaml";

enum LCDYUpdateStrategy {
	increasing,
	constant,
	random,
}

enum GameBoyModel : ushort {
	dmg = 1, /// Original Game Boy
	mgb = 0x00FF, /// Game Boy Pocket
	cgb = 0x0011, /// Game Boy Color
	gba = 0x0111, /// Game Boy Advance
}

struct GameBoySimple {
	void function(ushort) entryPoint;
	void function() interruptHandlerVBlank = () {};
	string title;
	string sourceFile;
	ubyte lcdYUpdateValue = 1;
	LCDYUpdateStrategy lcdYUpdateStrategy;
	uint seed = 0x12345678;
	GameBoyModel model;
	private Random rng;
	private Settings settings;
	private Renderer renderer;
	private APU apu;
	private immutable(ubyte)[] originalData;
	private KEY key1;
	private JOY joy;

	private PlatformCommon platform;

	mixin PlatformCommonForwarders;

	void initialize(Backend backendType = Backend.autoSelect) {
		rng = Random(seed);
		if (model >= GameBoyModel.cgb) {
			renderer.ppu.cgbMode = true;
		}
		final switch (settings.gbPalette) {
			case GBPalette.dmg: renderer.ppu.gbPalette = dmgPaletteCGB; break;
			case GBPalette.pocket: renderer.ppu.gbPalette = pocketPaletteCGB; break;
		}
		renderer.ppu.paletteRAM[] = renderer.ppu.gbPalette[0 .. 16];

		apu.initialize(platform.settings.audio.sampleRate);
		commonInitialization(Resolution(PPU.width, PPU.height), { entryPoint(model); }, backendType);
		platform.installAudioCallback(&apu, &audioCallback);
		renderer.initialize(title, platform.backend.video);
		platform.registerMemoryRange("VRAM", renderer.ppu.vram.raw);
		platform.registerMemoryRange("OAM", renderer.ppu.oam);
		platform.registerMemoryRange("Palette RAM", cast(ubyte[])renderer.ppu.paletteRAM);
	}
	immutable(ubyte)[] romData() {
		if (!originalData && sourceFile.exists) {
			originalData = (cast(ubyte[])read(sourceFile)).idup;
		}
		return originalData;
	}
	void enableSRAM() {
		//enableSRAM(saveSize);
	}
	alias disableSRAM = commitSRAM;
	void interruptHandlerSTAT(void function() fun) {
		renderer.statInterrupt = fun;
	}
	void interruptHandlerTimer(void function() fun) {
		// having the renderer handle this lets us hijack the scanline handler for accurate-enough timing
		renderer.timerInterrupt = fun;
	}
	void interruptHandlerSerial(void function() fun) {}
	void interruptHandlerJoypad(void function() fun) {}
	void waitHBlank() {
		renderer.holdWritesUntilHBlank = true;
	}
	ubyte[] vram() {
		const offset = renderer.ppu.cgbMode * renderer.ppu.registers.vbk;
		return renderer.ppu.vram.raw[0x2000 * offset .. 0x2000 * (offset + 1)];
	}
	private void copyInputState(InputState state) @safe pure {
		joy.pad = 0;
		if (state.controllers[0] & ControllerMask.y) { joy.pad |= Pad.b; }
		if (state.controllers[0] & ControllerMask.b) { joy.pad |= Pad.a; }
		if (state.controllers[0] & ControllerMask.start) { joy.pad |= Pad.start; }
		if (state.controllers[0] & ControllerMask.select) { joy.pad |= Pad.select; }
		if (state.controllers[0] & ControllerMask.up) { joy.pad |= Pad.up; }
		if (state.controllers[0] & ControllerMask.down) { joy.pad |= Pad.down; }
		if (state.controllers[0] & ControllerMask.left) { joy.pad |= Pad.left; }
		if (state.controllers[0] & ControllerMask.right) { joy.pad |= Pad.right; }
	}
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
	private void commonDebugMenu(const UIState state) {
		bool dumpVRAM;
		if (ImGui.BeginMainMenuBar()) {
			if (ImGui.BeginMenu("RAM")) {
				ImGui.MenuItem("Dump VRAM", null, &dumpVRAM);
				ImGui.EndMenu();
			}
			ImGui.EndMainMenuBar();
		}
		if (dumpVRAM) {
			File("vram.bin", "w").rawWrite(renderer.ppu.vram.raw);
			dumpVRAM = false;
		}
	}
	ref auto waveRAM() {
		static struct WaveRAM {
			GameBoySimple* gb;
			void opIndexAssign(ubyte val, size_t offset) {
				gb.writeRegister(cast(ushort)(0xFF30 + offset), val);
			}
			ubyte opIndex(size_t offset) {
				return gb.readRegister(cast(ushort)(0xFF30 + offset));
			}
		}
		return WaveRAM(&this);
	}
	ubyte IF; /// NYI
	ubyte IE; /// NYI
	ubyte SB; /// NYI
	ubyte SC; /// NYI
	ubyte DIV; /// NYI
	ubyte RP; /// NYI
	void stop() {
		key1.commitSpeedChange();
		if (key1.pretendDoubleSpeed) {
			renderer.timer.timerMultiplier = 2;
		} else {
			assert(0, "STOP should not be used except to switch speeds!");
		}
	}
	void writeRegisterPlatform(ushort addr, ubyte value) {
		if ((addr >= Register.NR10) && (addr <= Register.WAVEEND)) {
			apu.writeRegister(addr, value);
		} else if ((addr >= Register.TIMA) && (addr <= Register.TAC)) {
			renderer.timer.writeRegister(addr, value);
		} else if ((addr >= Register.LCDC) && (addr <= Register.WX) || ((addr >= Register.BCPS) && (addr <= Register.SVBK)) || (addr == Register.VBK)) {
			renderer.writeRegister(addr, value);
		} else if (addr == Register.KEY1) {
			key1.writeRegister(addr, value);
		} else if (addr == Register.JOYP) {
			joy.writeRegister(addr, value);
		} else {
			assert(0, format!"Not yet implemented: %04X"(addr));
		}
	}
	ubyte readRegister(ushort addr) const {
		if ((addr >= Register.NR10) && (addr <= Register.WAVEEND)) {
			return apu.readRegister(addr);
		} else if ((addr >= Register.TIMA) && (addr <= Register.TAC)) {
			return renderer.timer.readRegister(addr);
		} else if ((addr >= Register.LCDC) && (addr <= Register.WX) || ((addr >= Register.BCPS) && (addr <= Register.SVBK)) || (addr == Register.VBK)) {
			return renderer.readRegister(addr);
		} else if (addr == Register.KEY1) {
			return key1.readRegister(addr);
		} else if (addr == Register.JOYP) {
			return joy.readRegister(addr);
		} else {
			assert(0, format!"Not yet implemented: %04X"(addr));
		}
	}
	ubyte[] tileBlockA() return @safe pure => cast(ubyte[])renderer.ppu.vram.tileBlockA;
	ubyte[] tileBlockB() return @safe pure => cast(ubyte[])renderer.ppu.vram.tileBlockB;
	ubyte[] tileBlockC() return @safe pure => cast(ubyte[])renderer.ppu.vram.tileBlockC;
	ubyte[] screenA() return @safe pure => renderer.ppu.vram.screenA;
	ubyte[] screenB() return @safe pure => renderer.ppu.vram.screenB;
	ubyte[] oam() return @safe pure => renderer.ppu.oam;
	ubyte[] bgScreen() return @safe pure => renderer.ppu.bgScreen;
	ubyte[] windowScreen() return @safe pure => renderer.ppu.windowScreen;
}

module replatform64.gameboy.platform;

import replatform64.gameboy.apu;
import replatform64.gameboy.common;
import replatform64.gameboy.hardware;
import replatform64.gameboy.ppu;
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
	private ubyte pad;
	private bool dpad;
	private bool noneSelected;
	private bool pretendDoubleSpeed;
	private bool preparingDoubleSpeed;

	private PlatformCommon platform;

	mixin PlatformCommonForwarders;

	void initialize(Backend backendType = Backend.autoSelect) {
		rng = Random(seed);
		if (model >= GameBoyModel.cgb) {
			renderer.ppu.cgbMode = true;
		}
		final switch (settings.gbPalette) {
			case GBPalette.dmg: renderer.ppu.gbPalette = dmgPalette; break;
			case GBPalette.pocket: renderer.ppu.gbPalette = pocketPalette; break;
		}
		renderer.ppu.vram = new ubyte[](renderer.ppu.cgbMode ? 0x4000 : 0x2000);

		apu.initialize(platform.settings.audio.sampleRate);
		commonInitialization(Resolution(PPU.width, PPU.height), { entryPoint(model); }, backendType);
		platform.installAudioCallback(&apu, &audioCallback);
		renderer.initialize(title, platform.backend.video);
		platform.registerMemoryRange("VRAM", renderer.ppu.vram);
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
	void interruptHandlerTimer(void function() fun) {}
	void interruptHandlerSerial(void function() fun) {}
	void interruptHandlerJoypad(void function() fun) {}
	void updateReadableRegisters() {
		final switch (lcdYUpdateStrategy) {
			case LCDYUpdateStrategy.constant:
				//registers.LY = lcdYUpdateValue;
				break;
			case LCDYUpdateStrategy.increasing:
				//registers.LY = ++lcdYUpdateValue;
				break;
			case LCDYUpdateStrategy.random:
				//registers.LY = uniform!ubyte(rng);
				break;
		}
	}
	ref ubyte[0x400] getBGTilemap() @safe {
		return renderer.ppu.bgScreen[0 .. 0x400];
	}
	ref ubyte[0x400] getWindowTilemap() @safe {
		return renderer.ppu.windowScreen[0 .. 0x400];
	}
	void waitHBlank() {
		renderer.holdWritesUntilHBlank = true;
	}
	ubyte[] vram() {
		const offset = renderer.ppu.cgbMode * renderer.ppu.registers.vbk;
		return renderer.ppu.vram[0x2000 * offset .. 0x2000 * (offset + 1)];
	}

	void writeJoy(ubyte v) {
		dpad = (v & 0x30) == 0x20;
		noneSelected = (v & 0x30) == 0x30;
	}

	ubyte readJoy() {
		if (noneSelected) {
			return 0xF;
		}
		if (dpad) {
			return ((~pad) >> 4) & 0xF;
		}
		return ~pad & 0xF;
	}
	private void copyInputState(InputState state) @safe pure {
		pad = 0;
		if (state.controllers[0] & ControllerMask.y) { pad |= Pad.b; }
		if (state.controllers[0] & ControllerMask.b) { pad |= Pad.a; }
		if (state.controllers[0] & ControllerMask.start) { pad |= Pad.start; }
		if (state.controllers[0] & ControllerMask.select) { pad |= Pad.select; }
		if (state.controllers[0] & ControllerMask.up) { pad |= Pad.up; }
		if (state.controllers[0] & ControllerMask.down) { pad |= Pad.down; }
		if (state.controllers[0] & ControllerMask.left) { pad |= Pad.left; }
		if (state.controllers[0] & ControllerMask.right) { pad |= Pad.right; }
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
			File("vram.bin", "w").rawWrite(renderer.ppu.vram);
			dumpVRAM = false;
		}
	}
	ref auto waveRAM() {
		static struct WaveRAM {
			APU* apu;
			void opIndexAssign(ubyte val, size_t offset) {
				apu.writeRegister(cast(ushort)(0xFF30 + offset), val);
			}
			ubyte opIndex(size_t offset) {
				return apu.readRegister(cast(ushort)(0xFF30 + offset));
			}
		}
		return WaveRAM(&apu);
	}
	mixin RegisterRedirect!("SCX", "renderer", GameBoyRegister.SCX);
	mixin RegisterRedirect!("SCY", "renderer", GameBoyRegister.SCY);
	mixin RegisterRedirect!("WX", "renderer", GameBoyRegister.WX);
	mixin RegisterRedirect!("WY", "renderer", GameBoyRegister.WY);
	mixin RegisterRedirect!("LY", "renderer", GameBoyRegister.LY);
	mixin RegisterRedirect!("LYC", "renderer", GameBoyRegister.LYC);
	mixin RegisterRedirect!("LCDC", "renderer", GameBoyRegister.LCDC);
	mixin RegisterRedirect!("STAT", "renderer", GameBoyRegister.STAT);
	mixin RegisterRedirect!("BGP", "renderer", GameBoyRegister.BGP);
	mixin RegisterRedirect!("OBP0", "renderer", GameBoyRegister.OBP0);
	mixin RegisterRedirect!("OBP1", "renderer", GameBoyRegister.OBP1);
	mixin RegisterRedirect!("BCPS", "renderer", GameBoyRegister.BCPS);
	mixin RegisterRedirect!("BCPD", "renderer", GameBoyRegister.BCPD);
	mixin RegisterRedirect!("OCPS", "renderer", GameBoyRegister.OCPS);
	mixin RegisterRedirect!("OCPD", "renderer", GameBoyRegister.OCPD);
	mixin RegisterRedirect!("VBK", "renderer", GameBoyRegister.VBK);
	mixin RegisterRedirect!("NR10", "apu", GameBoyRegister.NR10);
	mixin RegisterRedirect!("NR11", "apu", GameBoyRegister.NR11);
	mixin RegisterRedirect!("NR12", "apu", GameBoyRegister.NR12);
	mixin RegisterRedirect!("NR13", "apu", GameBoyRegister.NR13);
	mixin RegisterRedirect!("NR14", "apu", GameBoyRegister.NR14);
	mixin RegisterRedirect!("NR21", "apu", GameBoyRegister.NR21);
	mixin RegisterRedirect!("NR22", "apu", GameBoyRegister.NR22);
	mixin RegisterRedirect!("NR23", "apu", GameBoyRegister.NR23);
	mixin RegisterRedirect!("NR24", "apu", GameBoyRegister.NR24);
	mixin RegisterRedirect!("NR30", "apu", GameBoyRegister.NR30);
	mixin RegisterRedirect!("NR31", "apu", GameBoyRegister.NR31);
	mixin RegisterRedirect!("NR32", "apu", GameBoyRegister.NR32);
	mixin RegisterRedirect!("NR33", "apu", GameBoyRegister.NR33);
	mixin RegisterRedirect!("NR34", "apu", GameBoyRegister.NR34);
	mixin RegisterRedirect!("NR41", "apu", GameBoyRegister.NR41);
	mixin RegisterRedirect!("NR42", "apu", GameBoyRegister.NR42);
	mixin RegisterRedirect!("NR43", "apu", GameBoyRegister.NR43);
	mixin RegisterRedirect!("NR44", "apu", GameBoyRegister.NR44);
	mixin RegisterRedirect!("NR50", "apu", GameBoyRegister.NR50);
	mixin RegisterRedirect!("NR51", "apu", GameBoyRegister.NR51);
	mixin RegisterRedirect!("NR52", "apu", GameBoyRegister.NR52);
	alias P1 = JOYP;
	alias AUD1SWEEP = NR10;
	alias AUD1LEN = NR11;
	alias AUD1ENV = NR12;
	alias AUD1LOW = NR13;
	alias AUD1HIGH = NR14;
	alias AUD2LEN = NR21;
	alias AUD2ENV = NR22;
	alias AUD2LOW = NR23;
	alias AUD2HIGH = NR24;
	alias AUD3ENA = NR30;
	alias AUD3LEN = NR31;
	alias AUD3LEVEL = NR32;
	alias AUD3LOW = NR33;
	alias AUD3HIGH = NR34;
	alias AUD4LEN = NR41;
	alias AUD4ENV = NR42;
	alias AUD4POLY = NR43;
	alias AUD4GO = NR44;
	alias AUDVOL = NR50;
	alias AUDTERM = NR51;
	alias AUDENA = NR52;
	ubyte IF; /// NYI
	ubyte IE; /// NYI
	ubyte SB; /// NYI
	ubyte SC; /// NYI
	ubyte TIMA; /// NYI
	ubyte TMA; /// NYI
	ubyte TAC; /// NYI
	ubyte DIV; /// NYI
	ubyte RP; /// NYI
	alias JOYP = readJoy;
	alias JOYP = writeJoy;
	ubyte SVBK; /// NYI
	ubyte KEY1() const @safe pure {
		return pretendDoubleSpeed << 7;
	}
	void KEY1(ubyte value) @safe pure {
		debug tracef("Preparing to switch to %s mode", ["single-speed", "double-speed"][!!(value & 1)]);
		preparingDoubleSpeed = !!(value & 1);
	}
	void stop() {
		if (preparingDoubleSpeed) {
			debug tracef("Switched to double speed mode");
			pretendDoubleSpeed = true;
		} else {
			assert(0, "STOP should not be used except to switch speeds!");
		}
	}
	void writeRegister(ushort addr, ubyte value) {
		if ((addr >= GameBoyRegister.NR10) && (addr <= GameBoyRegister.NR52)) {
			apu.writeRegister(addr, value);
		} else if ((addr >= GameBoyRegister.LCDC) && (addr <= GameBoyRegister.WX)) {
			renderer.writeRegister(addr, value);
		} else {
			assert(0, "Not yet implemented");
		}
	}
	ubyte[] tileBlockA() @safe pure {
		return renderer.ppu.tileBlockA;
	}
	ubyte[] tileBlockB() @safe pure {
		return renderer.ppu.tileBlockB;
	}
	ubyte[] tileBlockC() @safe pure {
		return renderer.ppu.tileBlockC;
	}
	ubyte[] screenA() @safe pure {
		return renderer.ppu.screenA;
	}
	ubyte[] screenB() @safe pure {
		return renderer.ppu.screenB;
	}
	ubyte[] oam() return @safe pure {
		return renderer.ppu.oam;
	}
	ubyte[] bgScreen() @safe pure {
		return renderer.ppu.bgScreen;
	}
	ubyte[] windowScreen() @safe pure {
		return renderer.ppu.windowScreen;
	}
}

//unittest {
//	writeJoy(0x30);
//	assert(readJoy() == 0xF);
//	writeJoy(0x10);
//	assert(readJoy() == 0xF);
//	input = 0xF0;
//	assert(readJoy() == 0);
//	writeJoy(0x20);
//	assert(readJoy() == 0xF);
//}

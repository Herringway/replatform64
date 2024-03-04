module librehome.gameboy.platform;

import librehome.gameboy.apu;
import librehome.gameboy.ppu;
import librehome.gameboy.renderer;

import librehome.backend.common;

import librehome.commonplatform;
import librehome.registers;
import librehome.ui;

import d_imgui.imgui_h;
import ImGui = d_imgui;
import imgui.hexeditor;

import core.thread;
import std.file;
import std.logger;
import std.random;
import std.stdio;

import siryul;

struct Settings {
	bool yamlSave;
	bool debugging;
}

enum settingsFile = "settings.yaml";

enum LCDYUpdateStrategy {
	increasing,
	constant,
	random,
}

enum GameBoyRegister : ushort {
	JOYP = 0xFF00,
	SB = 0xFF01,
	SC = 0xFF02,
	DIV = 0xFF04,
	TIMA = 0xFF05,
	TMA = 0xFF06,
	TAC = 0xFF07,
	IF = 0xFF0F,
	NR10 = 0xFF10,
	NR11 = 0xFF11,
	NR12 = 0xFF12,
	NR13 = 0xFF13,
	NR14 = 0xFF14,
	NR21 = 0xFF16,
	NR22 = 0xFF17,
	NR23 = 0xFF18,
	NR24 = 0xFF19,
	NR30 = 0xFF1A,
	NR31 = 0xFF1B,
	NR32 = 0xFF1C,
	NR33 = 0xFF1D,
	NR34 = 0xFF1E,
	NR41 = 0xFF20,
	NR42 = 0xFF21,
	NR43 = 0xFF22,
	NR44 = 0xFF23,
	NR50 = 0xFF24,
	NR51 = 0xFF25,
	NR52 = 0xFF26,
	LCDC = 0xFF40,
	STAT = 0xFF41,
	SCY = 0xFF42,
	SCX = 0xFF43,
	LY = 0xFF44,
	LYC = 0xFF45,
	DMA = 0xFF46,
	BGP = 0xFF47,
	OBP0 = 0xFF48,
	OBP1 = 0xFF49,
	WY = 0xFF4A,
	WX = 0xFF4B,
	KEY1 = 0xFF4D,
	VBK = 0xFF4F,
	HDMA1 = 0xFF51,
	HDMA2 = 0xFF52,
	HDMA3 = 0xFF53,
	HDMA4 = 0xFF54,
	HDMA5 = 0xFF55,
	RP = 0xFF56,
	BCPS = 0xFF68,
	BCPD = 0xFF69,
	OCPS = 0xFF6A,
	OCPD = 0xFF6B,
	SVBK = 0xFF70,
	IE = 0xFFFF,
}

enum GameBoyModel : ushort {
	dmg = 1, /// Original Game Boy
	mgb = 0x00FF, /// Game Boy Pocket
	cgb = 0x0011, /// Game Boy Color
	gba = 0x0111, /// Game Boy Advance
}

struct GameBoySimple {
	void function(ushort) entryPoint;
	void function() interruptHandler;
	DebugFunction debugMenuRenderer;
	string title;
	string sourceFile;
	string saveFile;
	ubyte lcdYUpdateValue = 1;
	LCDYUpdateStrategy lcdYUpdateStrategy;
	uint seed = 0x12345678;
	GameBoyModel model;
	uint saveSize;
	private Random rng;
	private Settings settings;
	private Renderer renderer;
	private APU apu;
	private const(ubyte)[] originalData;
	private ubyte[] sramBuffer;
	private bool vramEditorActive;
	private MemoryEditor memoryEditorVRAM;
	private bool oamEditorActive;
	private MemoryEditor memoryEditorOAM;
	alias width = renderer.ppu.width;
	alias height = renderer.ppu.height;

	private PlatformCommon platform;
	T loadSettings(T)() {
		auto allSettings = platform.loadSettings!(Settings, T)();
		settings = allSettings.system;
		return allSettings.game;
	}
	void saveSettings(T)(T gameSettings) {
		platform.saveSettings(settings, gameSettings);
	}
	void initialize() {
		static void initMemoryEditor(ref MemoryEditor editor) {
			editor.Cols = 8;
			editor.OptShowOptions = false;
			editor.OptShowDataPreview = false;
			editor.OptShowAscii = false;
		}
		initMemoryEditor(memoryEditorVRAM);
		initMemoryEditor(memoryEditorOAM);
		rng = Random(seed);
		renderer.ppu.vram = new ubyte[](0x10000);

		auto game = new Fiber({ entryPoint(model); });

		apu.initialize();
		platform.initialize(game);
		platform.installAudioCallback(&apu, &audioCallback);
		renderer.initialize(title, platform.backend.video);
		platform.debugMenu = debugMenuRenderer;
		platform.platformDebugMenu = &commonGBDebugging;
		platform.debugState = null;
		platform.platformDebugState = null;
	}
	void run() {
		if (settings.debugging) {
			platform.enableDebuggingFeatures();
		}
		platform.showUI();
		while (true) {
			if (platform.runFrame({ interruptHandler(); }, { renderer.draw(); })) {
				break;
			}
			copyInputState(platform.inputState);
		}
	}
	private void prepareSRAM(size_t size) {
		if (!sramBuffer) {
			sramBuffer = new ubyte[](size);
		}
	}
	void loadSRAM(size_t size) {
		prepareSRAM(size);
		static bool loaded;
		if (loaded || !saveFileName.exists) {
			return;
		}
		auto file = File(saveFileName, "r");
		if (file.size != sramBuffer.length) {
			infof("Discarding save file with incorrect size: Expected %s, got %s", sramBuffer.length, file.size);
			return;
		}
		infof("Loaded save file %s", saveFileName);
		file.rawRead(sramBuffer);
		loaded = true;
	}
	void saveSRAM(size_t size) {
		prepareSRAM(size);
		File(saveFileName, "w").rawWrite(sramBuffer);
	}

	void loadSRAMSerialized(T)() {
		static bool loaded;
		if (loaded || !saveFileName.exists) {
			return;
		}
		sram!T() = fromFile!(T, YAML)(saveFileName);
		loaded = true;
	}
	void saveSRAMSerialized(T)() {
		sram!T.toFile!YAML(saveFileName);
	}
	private string saveFileName() {
		if (settings.yamlSave) {
			return saveFile~".yaml";
		} else {
			return saveFile;
		}
	}
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
		return renderer.ppu.vram[0x9800 .. 0x9C00];
	}
	ref ubyte[0x400] getWindowTilemap() @safe {
		return renderer.ppu.vram[0x9C00 .. 0xA000];
	}
	void wait() {
		Fiber.yield();
	}
	void waitHBlank() {
		// do nothing, we don't enforce the read/writeability of the different PPU modes
	}
	ubyte[] vram() {
		return renderer.ppu.vram;
	}
	const(ubyte)[] romData() {
		if (!originalData) {
			originalData = cast(ubyte[])read(sourceFile);
		}
		return originalData;
	}
	void enableSRAM(T)() {
		enableSRAM!T(saveSize);
	}
	void enableSRAM(T)(size_t size) {
		if (settings.yamlSave) {
			loadSRAMSerialized!T();
		} else {
			loadSRAM(size);
		}
	}
	void disableSRAM(T)() {
		disableSRAM!T(saveSize);
	}
	void disableSRAM(T)(size_t size) {
		if (settings.yamlSave) {
			saveSRAMSerialized!T();
		} else {
			saveSRAM(size);
		}
	}
	ref T sram(T)() {
		return (cast(T[])sramBuffer[0 .. T.sizeof])[0];
	}
	private ubyte pad;

	private bool dpad;
	private bool noneSelected;

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
	private void commonGBDebugging(const UIState state) {
		bool dumpVRAM;
		if (ImGui.BeginMainMenuBar()) {
			if (ImGui.BeginMenu("RAM")) {
				ImGui.MenuItem("Dump VRAM", null, &dumpVRAM);
				ImGui.MenuItem("VRAM", null, &vramEditorActive);
				ImGui.MenuItem("OAM", null, &oamEditorActive);
				ImGui.EndMenu();
			}
			ImGui.EndMainMenuBar();
		}
		if (vramEditorActive) {
			vramEditorActive = memoryEditorVRAM.DrawWindow("VRAM", vram[0x8000 .. 0xA000]);
		}
		if (oamEditorActive) {
			oamEditorActive = memoryEditorOAM.DrawWindow("OAM", vram[0xFE00 .. 0xFEA0]);
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
				apu.write(cast(ushort)(0xFF30 + offset), val);
			}
			ubyte opIndex(size_t offset) {
				return apu.read(cast(ushort)(0xFF30 + offset));
			}
		}
		return WaveRAM(&apu);
	}
	mixin RegisterRedirect!("SCX", "renderer.ppu.registers.scx");
	mixin RegisterRedirect!("SCY", "renderer.ppu.registers.scy");
	mixin RegisterRedirect!("WX", "renderer.ppu.registers.wx");
	mixin RegisterRedirect!("WY", "renderer.ppu.registers.wy");
	mixin RegisterRedirect!("LY", "renderer.ppu.registers.ly");
	mixin RegisterRedirect!("LYC", "renderer.ppu.registers.lyc");
	mixin RegisterRedirect!("LCDC", "renderer.ppu.registers.lcdc");
	mixin RegisterRedirect!("STAT", "renderer.ppu.registers.stat");
	mixin RegisterRedirect!("BGP", "renderer.ppu.registers.bgp");
	mixin RegisterRedirect!("OBP0", "renderer.ppu.registers.obp0");
	mixin RegisterRedirect!("OBP1", "renderer.ppu.registers.obp1");
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
	ubyte TMA; /// NYI
	ubyte DIV; /// NYI
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
	ubyte[] oam() @safe pure {
		return renderer.ppu.oam;
	}
	ubyte[] bgScreen() @safe pure {
		return renderer.ppu.bgScreen;
	}
	ubyte[] windowScreen() @safe pure {
		return renderer.ppu.windowScreen;
	}
}


enum Pad : ubyte {
	a = 1 << 0,
	b = 1 << 1,
	select = 1 << 2,
	start = 1 << 3,
	right = 1 << 4,
	left = 1 << 5,
	up = 1 << 6,
	down = 1 << 7,
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

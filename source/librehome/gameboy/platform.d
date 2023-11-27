module librehome.gameboy.platform;

import librehome.gameboy.apu;
import librehome.gameboy.ppu;
import librehome.gameboy.renderer;

import librehome.backend.common;
import librehome.backend.sdl2;

import librehome.ui;

import core.thread;
import std.file;
import std.logger;
import std.random;
import std.stdio;

import siryul;

struct Settings {
	VideoSettings video;
	InputSettings input;
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
	private Random rng;
	private Settings settings;
	private Renderer renderer;
	private APU apu;
	private PlatformBackend backend;
	private const(ubyte)[] originalData;
	private ubyte[] sramBuffer;
	T loadSettings(T)() {
		static struct FullSettings {
			Settings system;
			T game;
		}
		if (!settingsFile.exists) {
			FullSettings defaults;
			defaults.system.input = getDefaultInputSettings();
			defaults.toFile!YAML(settingsFile);
		}
		auto allSettings = fromFile!(FullSettings, YAML)(settingsFile);
		settings = allSettings.system;
		return allSettings.game;
	}
	void run() {
		rng = Random(seed);
		renderer.ppu.vram = new ubyte[](0x10000);

		auto game = new Fiber({ entryPoint(model); });

		bool paused;
		apu.initialize();
		backend = new SDL2Platform;
		backend.initialize();
		backend.audio.initialize(&apu, &audioCallback, AUDIO_SAMPLE_RATE, 2);
		backend.input.initialize(settings.input);
		renderer.initialize(title, settings.video, backend.video, settings.debugging, debugMenuRenderer);

		while (true) {
			if (backend.processEvents()) {
				break;
			}
			auto input = backend.input.getState();
			copyInputState(input);
			if (!paused) {
				game.call(Fiber.Rethrow.yes);
			}
			if (game.state == Fiber.State.TERM) {
				break;
			}
			interruptHandler();
			renderer.draw();
			if (input.pause) {
				paused ^= true;
				input.pause = false;
			}
			if (!input.fastForward) {
				renderer.waitNextFrame();
			}
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
	ubyte[] vram() {
		return renderer.ppu.vram;
	}
	const(ubyte)[] romData() {
		if (!originalData) {
			originalData = cast(ubyte[])read(sourceFile);
		}
		return originalData;
	}
	void enableSRAM(T)(size_t size) {
		if (settings.yamlSave) {
			loadSRAMSerialized!T();
		} else {
			loadSRAM(size);
		}
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
	ref auto waveRAM() {
		static struct WaveRAM {
			APU* apu;
			void opIndexAssign(ubyte val, size_t offset) {
				infof("WRITE: %04X %02X", 0xFF30 + offset, val);
				apu.audio_write(cast(ushort)(0xFF30 + offset), val);
			}
			ubyte opIndex(size_t offset) {
				return apu.audio_read(cast(ushort)(0xFF30 + offset));
			}
		}
		return WaveRAM(&apu);
	}
	template Register(alias gb, ushort addr) {
		static if ((addr >= GameBoyRegister.NR10) && (addr <= GameBoyRegister.NR52)) {
			static ubyte Register() {
				return gb.apu.audio_read(addr);
			}
			static void Register(ubyte val, string file = __FILE__, ulong line = __LINE__) {
				infof("%s:%s WRITE: %04X %02X", file, line, addr, val);
				gb.apu.audio_write(addr, val);
			}
		} else static if (addr == GameBoyRegister.SCY) {
			static ubyte Register() {
				return gb.renderer.ppu.registers.scy;
			}
			static void Register(ubyte val) {
				gb.renderer.ppu.registers.scy = val;
			}
		} else static if (addr == GameBoyRegister.SCX) {
			static ubyte Register() {
				return gb.renderer.ppu.registers.scx;
			}
			static void Register(ubyte val) {
				gb.renderer.ppu.registers.scx = val;
			}
		} else static if (addr == GameBoyRegister.WY) {
			static ubyte Register() {
				return gb.renderer.ppu.registers.wy;
			}
			static void Register(ubyte val) {
				gb.renderer.ppu.registers.wy = val;
			}
		} else static if (addr == GameBoyRegister.WX) {
			static ubyte Register() {
				return gb.renderer.ppu.registers.wx;
			}
			static void Register(ubyte val) {
				gb.renderer.ppu.registers.wx = val;
			}
		} else static if (addr == GameBoyRegister.STAT) {
			static ubyte Register() {
				return gb.renderer.ppu.registers.stat;
			}
			static void Register(ubyte val) {
				gb.renderer.ppu.registers.stat = val;
			}
		} else static if (addr == GameBoyRegister.LCDC) {
			static ubyte Register() {
				return gb.renderer.ppu.registers.lcdc;
			}
			static void Register(ubyte val) {
				gb.renderer.ppu.registers.lcdc = val;
			}
		} else static if (addr == GameBoyRegister.OBP0) {
			static ubyte Register() {
				return gb.renderer.ppu.registers.obp0;
			}
			static void Register(ubyte val) {
				gb.renderer.ppu.registers.obp0 = val;
			}
		} else static if (addr == GameBoyRegister.OBP1) {
			static ubyte Register() {
				return gb.renderer.ppu.registers.obp1;
			}
			static void Register(ubyte val) {
				gb.renderer.ppu.registers.obp1 = val;
			}
		} else static if (addr == GameBoyRegister.BGP) {
			static ubyte Register() {
				return gb.renderer.ppu.registers.bgp;
			}
			static void Register(ubyte val) {
				gb.renderer.ppu.registers.bgp = val;
			}
		} else static if (addr == GameBoyRegister.LY) {
			static ubyte Register() {
				return gb.renderer.ppu.registers.ly;
			}
			static void Register(ubyte val) {
				gb.renderer.ppu.registers.ly = val;
			}
		} else static if (addr == GameBoyRegister.LYC) {
			static ubyte Register() {
				return gb.renderer.ppu.registers.lyc;
			}
			static void Register(ubyte val) {
				gb.renderer.ppu.registers.lyc = val;
			}
		} else { //unimplemented
			static ubyte Register() {
				return 0;
			}
			static void Register(ubyte val) {}
		}
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

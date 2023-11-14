module librehome.gameboy.platform;

import librehome.gameboy.apu;
import librehome.gameboy.ppu;
import librehome.gameboy.renderer;

import librehome.backend.common;
import librehome.backend.sdl2;

import core.thread;
import std.file;
import std.logger;
import std.random;
import std.stdio;

import siryul;

struct Settings {
	WindowSettings window;
	InputSettings input;
	bool yamlSave;
}

enum settingsFile = "settings.yaml";

enum LCDYUpdateStrategy {
	increasing,
	constant,
	random,
}

struct GameBoySimple {
	void function() entryPoint;
	void function() interruptHandler;
	string title;
	string sourceFile;
	string saveFile;
	Registers registers;
	ubyte lcdYUpdateValue = 1;
	LCDYUpdateStrategy lcdYUpdateStrategy;
	uint seed = 0x12345678;
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

		auto game = new Fiber(entryPoint);

		bool paused;
		apu.initialize();
		backend = new SDL2Platform;
		backend.initialize();
		backend.audio.initialize(&apu, &audioCallback, AUDIO_SAMPLE_RATE, 2);
		backend.input.initialize(settings.input);
		renderer.initialize(title, settings.window, backend.video);

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
			copyRegisters();
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
				registers.LY = lcdYUpdateValue;
				break;
			case LCDYUpdateStrategy.increasing:
				registers.LY = ++lcdYUpdateValue;
				break;
			case LCDYUpdateStrategy.random:
				registers.LY = uniform!ubyte(rng);
				break;
		}
	}
	void copyRegisters() {
		renderer.ppu.registers.stat = registers.STAT;
		renderer.ppu.registers.lcdc = registers.LCDC;
		renderer.ppu.registers.scy = registers.SCY;
		renderer.ppu.registers.scx = registers.SCX;
		renderer.ppu.registers.ly = registers.LY;
		renderer.ppu.registers.lyc = registers.LYC;
		renderer.ppu.registers.bgp = registers.BGP;
		renderer.ppu.registers.obp0 = registers.OBP0;
		renderer.ppu.registers.obp1 = registers.OBP1;
		renderer.ppu.registers.wy = registers.WY;
		renderer.ppu.registers.wx = registers.WX;
		apu.audio_write(0xFF10, registers.NR10);
		apu.audio_write(0xFF11, registers.NR11);
		apu.audio_write(0xFF12, registers.NR12);
		apu.audio_write(0xFF13, registers.NR13);
		apu.audio_write(0xFF14, registers.NR14);
		apu.audio_write(0xFF16, registers.NR21);
		apu.audio_write(0xFF17, registers.NR22);
		apu.audio_write(0xFF18, registers.NR23);
		apu.audio_write(0xFF19, registers.NR24);
		apu.audio_write(0xFF1A, registers.NR30);
		apu.audio_write(0xFF1B, registers.NR31);
		apu.audio_write(0xFF1C, registers.NR32);
		apu.audio_write(0xFF1D, registers.NR33);
		apu.audio_write(0xFF1E, registers.NR34);
		apu.audio_write(0xFF20, registers.NR41);
		apu.audio_write(0xFF21, registers.NR42);
		apu.audio_write(0xFF22, registers.NR43);
		apu.audio_write(0xFF23, registers.NR44);
		apu.audio_write(0xFF24, registers.NR50);
		apu.audio_write(0xFF25, registers.NR51);
		apu.audio_write(0xFF26, registers.NR52);
		foreach (idx, w; registers.waveRAM) {
			apu.audio_write(cast(ushort)(0xFF30 + idx), w);
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

debug(loggableRegisters) {
	import std.logger;
	struct RegType(string name) {
		private ubyte value;
		alias this = get;
		void opAssign(ubyte n) {
			infof("%s: Writing %02X", name, n);
			value = n;
		}
		ubyte get() {
			infof("%s: Reading %02X", name, value);
			return value;
		}
	}
} else {
	alias RegType(string _) = ubyte;
}
struct Registers {
	RegType!"JOYP" JOYP; //FF00
	RegType!"SB" SB; //FF01
	RegType!"SC" SC; //FF02
	RegType!"DIV" DIV; //FF04
	RegType!"TIMA" TIMA; //FF05
	RegType!"TMA" TMA; //FF06
	RegType!"TAC" TAC; //FF07
	RegType!"IF" IF; // FF0F
	RegType!"LCDC" LCDC; //FF40
	RegType!"STAT" STAT; //FF41
	RegType!"SCY" SCY; //FF42
	RegType!"SCX" SCX; //FF43
	RegType!"LY" LY; //FF44
	RegType!"LYC" LYC; //FF45
	RegType!"BGP" BGP; //FF47
	RegType!"OBP0" OBP0; //FF48
	RegType!"OBP1" OBP1; //FF49
	RegType!"WY" WY; //FF4A
	RegType!"WX" WX; //FF4B
	RegType!"IE" IE; //FFFF

	RegType!"NR10" NR10; //FF10
	alias AUD1SWEEP = NR10;
	RegType!"NR11" NR11; //FF11
	alias AUD1LEN = NR11;
	RegType!"NR12" NR12; //FF12
	alias AUD1ENV = NR12;
	RegType!"NR13" NR13; //FF13
	alias AUD1LOW = NR13;
	RegType!"NR14" NR14; //FF14
	alias AUD1HIGH = NR14;
	RegType!"NR21" NR21; //FF16
	alias AUD2LEN = NR21;
	RegType!"NR22" NR22; //FF17
	alias AUD2ENV = NR22;
	RegType!"NR23" NR23; //FF18
	alias AUD2LOW = NR23;
	RegType!"NR24" NR24; //FF19
	alias AUD2HIGH = NR24;
	RegType!"NR30" NR30; //FF1A
	alias AUD3ENA = NR30;
	RegType!"NR31" NR31; //FF1B
	alias AUD3LEN = NR31;
	RegType!"NR32" NR32; //FF1C
	alias AUD3LEVEL = NR32;
	RegType!"NR33" NR33; //FF1D
	alias AUD3LOW = NR33;
	RegType!"NR34" NR34; //FF1E
	alias AUD3HIGH = NR34;
	RegType!"NR41" NR41; //FF20
	alias AUD4LEN = NR41;
	RegType!"NR42" NR42; //FF21
	alias AUD4ENV = NR42;
	RegType!"NR43" NR43; //FF22
	alias AUD4POLY = NR43;
	RegType!"NR44" NR44; //FF23
	alias AUD4GO = NR44;
	RegType!"NR50" NR50; //FF24
	alias AUDVOL = NR50;
	RegType!"NR51" NR51; //FF25
	alias AUDTERM = NR51;
	RegType!"NR52" NR52; //FF26
	alias AUDENA = NR52;

	ubyte[16] waveRAM; //FF30

}

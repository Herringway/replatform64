module replatform64.gameboy.platform;

import replatform64.gameboy.hardware;

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
	enum width = PPU.width;
	enum height = PPU.height;
	enum renderWidth = width;
	enum renderHeight = height;
	enum romExtension = ".gb";
	alias RenderPixelFormat = PixelFormatOf!(PPU.ColourFormat);
	void function(ushort) @safe entryPoint = model => throw new Exception("No entry point defined");
	string title;
	string sourceFile;
	ubyte lcdYUpdateValue = 1;
	LCDYUpdateStrategy lcdYUpdateStrategy;
	uint seed = 0x12345678;
	GameBoyModel model;
	private Random rng;
	private Settings settings;
	private APU apu;
	private KEY key1;
	private JOY joy;
	private PPU ppu;
	private Interrupts interrupts;
	Timer timer;
	Serial serial;
	Infrared infrared;
	bool holdWritesUntilHBlank;
	ubyte[ushort] cachedWrites;

	private PlatformCommon platform;

	mixin PlatformCommonForwarders;

	void initialize(Backend backendType = Backend.autoSelect) {
		rng = Random(seed);
		if (model >= GameBoyModel.cgb) {
			ppu.cgbMode = true;
		}
		final switch (settings.gbPalette) {
			case GBPalette.dmg: ppu.gbPalette = dmgPaletteCGB; break;
			case GBPalette.pocket: ppu.gbPalette = pocketPaletteCGB; break;
		}
		ppu.paletteRAM[] = ppu.gbPalette[0 .. 16];

		apu.initialize(platform.settings.audio.sampleRate);
		commonInitialization(Resolution(PPU.width, PPU.height), { entryPoint(model); }, backendType);
		platform.installAudioCallback(&apu, &audioCallback);

		platform.registerMemoryRange("VRAM", ppu.vram.raw);
		platform.registerMemoryRange("OAM", ppu.oam);
		platform.registerMemoryRange("Palette RAM", cast(ubyte[])ppu.paletteRAM);
	}
	void enableSRAM() {
		//enableSRAM(saveSize);
	}
	alias disableSRAM = commitSRAM;
	auto ref interruptHandlerTimer() => interrupts.timer;
	auto ref interruptHandlerSTAT() => interrupts.stat;
	auto ref interruptHandlerVBlank() => interrupts.vblank;
	auto ref interruptHandlerSerial() => interrupts.serial;
	auto ref interruptHandlerJoypad() => interrupts.joypad;
	void waitHBlank() @safe {
		holdWritesUntilHBlank = true;
	}
	ubyte[] vram() @safe return {
		const offset = ppu.cgbMode * ppu.registers.vbk;
		return ppu.vram.raw[0x2000 * offset .. 0x2000 * (offset + 1)];
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
	private void addTab(alias hw)(string label, UIState state) {
		if (ImGui.BeginTabItem(label)) {
			hw.debugUI(state);
			ImGui.EndTabItem();
		}
	}
	private void commonDebugState(UIState state) {
		if (ImGui.BeginTabBar("platformdebug")) {
			addTab!ppu("PPU", state);
			addTab!interrupts("Interrupts", state);
			addTab!apu("APU", state);
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
			File("vram.bin", "w").rawWrite(ppu.vram.raw);
			dumpVRAM = false;
		}
	}
	ref auto waveRAM() @safe {
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
	ubyte DIV; /// NYI
	void stop() @safe {
		key1.commitSpeedChange();
		if (key1.pretendDoubleSpeed) {
			timer.timerMultiplier = 2;
		} else {
			assert(0, "STOP should not be used except to switch speeds!");
		}
	}
	void writeRegisterPlatform(ushort addr, ubyte value) @safe {
		if ((addr >= Register.NR10) && (addr <= Register.WAVEEND)) {
			apu.writeRegister(addr, value);
		} else if ((addr >= Register.TIMA) && (addr <= Register.TAC)) {
			timer.writeRegister(addr, value);
		} else if ((addr >= Register.SB) && (addr <= Register.SC)) {
			serial.writeRegister(addr, value);
		} else if ((addr >= Register.LCDC) && (addr <= Register.WX) || ((addr >= Register.BCPS) && (addr <= Register.SVBK)) || (addr == Register.VBK)) {
			if (holdWritesUntilHBlank) {
				cachedWrites[addr] = value;
				return;
			}
			ppu.writeRegister(addr, value);
		} else if (addr == Register.KEY1) {
			key1.writeRegister(addr, value);
		} else if (addr == Register.RP) {
			infrared.writeRegister(addr, value);
		} else if (addr == Register.JOYP) {
			joy.writeRegister(addr, value);
		} else if ((addr == Register.IE) || (addr == Register.IF)) {
			interrupts.writeRegister(addr, value);
		} else {
			assert(0, format!"Not yet implemented: %04X"(addr));
		}
	}
	ubyte readRegister(ushort addr) @safe {
		if ((addr >= Register.NR10) && (addr <= Register.WAVEEND)) {
			return apu.readRegister(addr);
		} else if ((addr >= Register.TIMA) && (addr <= Register.TAC)) {
			return timer.readRegister(addr);
		} else if ((addr >= Register.SB) && (addr <= Register.SC)) {
			return serial.readRegister(addr);
		} else if ((addr >= Register.LCDC) && (addr <= Register.WX) || ((addr >= Register.BCPS) && (addr <= Register.SVBK)) || (addr == Register.VBK)) {
			if (holdWritesUntilHBlank) {
				if (auto val = addr in cachedWrites) {
					return *val;
				}
			}
			return ppu.readRegister(addr);
		} else if (addr == Register.KEY1) {
			return key1.readRegister(addr);
		} else if (addr == Register.RP) {
			return infrared.readRegister(addr);
		} else if ((addr == Register.IE) || (addr == Register.IF)) {
			return interrupts.readRegister(addr);
		} else if (addr == Register.JOYP) {
			return joy.readRegister(addr);
		} else {
			assert(0, format!"Not yet implemented: %04X"(addr));
		}
	}
	void enableInterrupts() @safe => interrupts.setInterrupts(true);
	void disableInterrupts() @safe => interrupts.setInterrupts(false);
	void draw() @safe {
		Texture texture;
		platform.backend.video.getDrawingTexture(texture);
		draw(texture.asArray2D!(PPU.ColourFormat));
	}
	void draw(scope Array2D!(PPU.ColourFormat) texture) @safe {
		ppu.beginDrawing(texture);
		// draw each line, one at a time
		foreach (i; 0 .. height) {
			timerUpdate();
			// each line starts in mode 2, scanning the OAM
			ppu.registers.stat.mode = 2;
			// trigger the interrupts. LY increments first, so the LYC=LY interrupt triggers first
			if (ppu.registers.ly == ppu.registers.lyc) {
				ppu.registers.stat.lycEqualLY = true;
				if (ppu.registers.stat.lycInterrupt) {
					writeRegister(Register.IF, readRegister(Register.IF) | InterruptFlag.stat);
				}
			} else {
				ppu.registers.stat.lycEqualLY = false;
			}
			// trigger mode 2 interrupt
			if (ppu.registers.stat.mode2Interrupt) {
				writeRegister(Register.IF, readRegister(Register.IF) | InterruptFlag.stat);
			}
			// start actually drawing pixels, mode 3
			// there's no mode 3 interrupt
			ppu.registers.stat.mode = 3;
			ppu.runLine();
			// done drawing. now in hblank, mode 0
			ppu.registers.stat.mode = 0;
			// perform any writes that were held for hblank now
			holdWritesUntilHBlank = false;
			foreach (addr, value; cachedWrites) {
				ppu.writeRegister(addr, value);
			}
			cachedWrites = null;
			// now trigger the mode 0 interrupt
			if (ppu.registers.stat.mode0Interrupt) {
				writeRegister(Register.IF, readRegister(Register.IF) | InterruptFlag.stat);
			}
			ppu.registers.ly++;
		}
		// vblank. rendering is finished, but there's still some other tasks to handle
		ppu.registers.stat.mode = 1;
		writeRegister(Register.IF, readRegister(Register.IF) | InterruptFlag.vblank);
		// mode 1 interrupt has lower priority than vblank interrupt
		if (ppu.registers.stat.mode1Interrupt) {
			writeRegister(Register.IF, readRegister(Register.IF) | InterruptFlag.stat);
		}
		// PPU spends a few extra scanlines in vblank, use 'em for timing
		foreach(i; height .. 154) {
			timerUpdate();
			ppu.registers.ly++;
		}
		// reset to 0 for next frame
		ppu.registers.ly = 0;
	}
	private void timerUpdate() @safe {
		timer.scanlineUpdate();
		if (timer.interruptTriggered) {
			writeRegister(Register.IF, readRegister(Register.IF) | InterruptFlag.timer);
			timer.interruptTriggered = false;
		}
	}
	ubyte[] tileBlockA() return @safe pure => cast(ubyte[])ppu.vram.tileBlockA;
	ubyte[] tileBlockB() return @safe pure => cast(ubyte[])ppu.vram.tileBlockB;
	ubyte[] tileBlockC() return @safe pure => cast(ubyte[])ppu.vram.tileBlockC;
	ubyte[] screenA() return @safe pure => ppu.vram.screenA;
	ubyte[] screenB() return @safe pure => ppu.vram.screenB;
	ubyte[] oam() return @safe pure => ppu.oam;
	ubyte[] bgScreen() return @safe pure => ppu.bgScreen;
	ubyte[] windowScreen() return @safe pure => ppu.windowScreen;
	void dump(StateDumper dumpFunction) @safe {
		static struct DumpState {
			APU apu;
			Infrared infrared;
			Interrupts interrupts;
			JOY joy;
			KEY key1;
			Serial serial;
			Timer timer;
		}
		dumpFunction("platform.state.yaml", DumpState(apu, infrared, interrupts, joy, key1, serial, timer).serialized());
		ppu.dump(dumpFunction);
	}
}

unittest {
	import std.range : iota;
	import std.algorithm.comparison : equal;
	static GameBoySimple currentRenderer;
	static auto ref newRenderer() {
		currentRenderer = GameBoySimple();
		// make sure interrupts are enabled
		currentRenderer.interrupts.setInterrupts(true);
		currentRenderer.writeRegister(Register.IE, InterruptFlag.stat);
		return currentRenderer;
	}
	auto buffer = Array2D!(PPU.ColourFormat)(GameBoySimple.width, GameBoySimple.height);
	with (newRenderer()) {
		draw(buffer);
	}
	with (newRenderer()) { // mode 0 fires every drawn scanline, after drawing is finished
		static ubyte[] scanLines;
		interrupts.stat = () {
			assert((currentRenderer.readRegister(Register.STAT) & STATValues.ppuMode) == 0);
			scanLines ~= currentRenderer.readRegister(Register.LY);
		};
		writeRegister(Register.STAT, STATValues.mode0Interrupt);
		draw(buffer);
		assert(scanLines.equal(iota(0, 144)));
	}
	with (newRenderer()) { // mode 1 fires only once per frame
		static ubyte[] scanLines;
		interrupts.stat = () {
			assert((currentRenderer.readRegister(Register.STAT) & STATValues.ppuMode) == 1);
			scanLines ~= currentRenderer.readRegister(Register.LY);
		};
		writeRegister(Register.STAT, STATValues.mode1Interrupt);
		draw(buffer);
		assert(scanLines.equal([144]));
	}
	with (newRenderer()) { // mode 2 fires every drawn scanline, before drawing starts
		static ubyte[] scanLines;
		interrupts.stat = () {
			assert((currentRenderer.readRegister(Register.STAT) & STATValues.ppuMode) == 2);
			scanLines ~= currentRenderer.readRegister(Register.LY);
		};
		writeRegister(Register.STAT, STATValues.mode2Interrupt);
		draw(buffer);
		assert(scanLines.equal(iota(0, 144)));
	}
	with (newRenderer()) { // LYC=LY interrupts fire only once per frame, at the beginning of the configured scanline (mode 2)
		static ubyte[] scanLines;
		interrupts.stat = () {
			assert((currentRenderer.readRegister(Register.STAT) & STATValues.ppuMode) == 2);
			scanLines ~= currentRenderer.readRegister(Register.LY);
		};
		writeRegister(Register.STAT, STATValues.lycInterrupt);
		writeRegister(Register.LYC, 42);
		draw(buffer);
		assert(scanLines == [42]);
	}
}

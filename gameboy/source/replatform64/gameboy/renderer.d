module replatform64.gameboy.renderer;

import replatform64.backend.common;
import std.exception;
import std.logger;
import std.traits;
import std.string;

import replatform64.gameboy.hardware;
import replatform64.util;

import pixelmancy.colours;

struct Renderer {
	alias PixelFormat = PixelFormatOf!(PPU.ColourFormat);
	PPU ppu;
	enum width = PPU.width;
	enum height = PPU.height;
	private VideoBackend backend;
	void function() statInterrupt;
	void function() timerInterrupt;
	Timer timer;
	bool holdWritesUntilHBlank;
	ubyte[ushort] cachedWrites;
	void initialize(string title, VideoBackend newBackend) {
		WindowSettings window;
		window.baseWidth = width;
		window.baseHeight = height;
		backend = newBackend;
		backend.createWindow(title, window);
		backend.createTexture(width, height, PixelFormat);
	}
	void timerUpdate() {
		timer.scanlineUpdate();
		if (timer.interruptTriggered) {
			timerInterrupt();
			timer.interruptTriggered = false;
		}
	}
	void draw() {
		Texture texture;
		backend.getDrawingTexture(texture);
		draw(texture.asArray2D!(PPU.ColourFormat));
	}
	void draw(scope Array2D!(PPU.ColourFormat) texture) {
		ppu.beginDrawing(texture);
		foreach (i; 0 .. height) {
			timerUpdate();
			ppu.registers.stat.mode = 2;
			if (ppu.registers.ly == ppu.registers.lyc) {
				ppu.registers.stat.lycEqualLY = true;
				if (ppu.registers.stat.lycInterrupt && (statInterrupt !is null)) {
					statInterrupt();
				}
			} else {
				ppu.registers.stat.lycEqualLY = false;
			}
			if (ppu.registers.stat.mode2Interrupt && (statInterrupt !is null)) {
				statInterrupt();
			}
			ppu.registers.stat.mode = 3;
			ppu.runLine();
			ppu.registers.stat.mode = 0;
			holdWritesUntilHBlank = false;
			foreach (addr, value; cachedWrites) {
				ppu.writeRegister(addr, value);
			}
			cachedWrites = null;
			if (ppu.registers.stat.mode0Interrupt && (statInterrupt !is null)) {
				statInterrupt();
			}
			ppu.registers.ly++;
		}
		// PPU spends a few extra scanlines in vblank
		foreach(i; height .. 154) {
			timerUpdate();
			ppu.registers.stat.mode = 1;
			if (ppu.registers.stat.mode1Interrupt && (statInterrupt !is null)) {
				statInterrupt();
			}
			ppu.registers.ly++;
		}
	}
	void waitNextFrame() {
		backend.waitNextFrame();
	}
	ubyte readRegister(ushort addr) const @safe pure {
		if (holdWritesUntilHBlank) {
			if (auto val = addr in cachedWrites) {
				return *val;
			}
		}
		return ppu.readRegister(addr);
	}
	void writeRegister(ushort addr, ubyte val) @safe pure {
		if (holdWritesUntilHBlank) {
			cachedWrites[addr] = val;
			return;
		}
		ppu.writeRegister(addr, val);
	}
}

unittest {
	import replatform64.gameboy.hardware : Register;
	import std.range : iota;
	import std.algorithm.comparison : equal;
	static Renderer currentRenderer;
	static auto ref newRenderer() {
		currentRenderer = Renderer();
		return currentRenderer;
	}
	auto buffer = Array2D!(PPU.ColourFormat)(Renderer.width, Renderer.height);
	with (newRenderer()) {
		draw(buffer);
	}
	with (newRenderer()) {
		static ubyte[] scanLines;
		statInterrupt = () {
			assert((currentRenderer.readRegister(Register.STAT) & STATValues.ppuMode) == 0);
			scanLines ~= currentRenderer.readRegister(Register.LY);
		};
		writeRegister(Register.STAT, STATValues.mode0Interrupt);
		draw(buffer);
		assert(scanLines.equal(iota(0, 144)));
	}
	with (newRenderer()) {
		static ubyte[] scanLines;
		statInterrupt = () {
			assert((currentRenderer.readRegister(Register.STAT) & STATValues.ppuMode) == 1);
			scanLines ~= currentRenderer.readRegister(Register.LY);
		};
		writeRegister(Register.STAT, STATValues.mode1Interrupt);
		draw(buffer);
		assert(scanLines.equal(iota(144, 154)));
	}
	with (newRenderer()) {
		static ubyte[] scanLines;
		statInterrupt = () {
			assert((currentRenderer.readRegister(Register.STAT) & STATValues.ppuMode) == 2);
			scanLines ~= currentRenderer.readRegister(Register.LY);
		};
		writeRegister(Register.STAT, STATValues.mode2Interrupt);
		draw(buffer);
		assert(scanLines.equal(iota(0, 144)));
	}
	with (newRenderer()) {
		static ubyte[] scanLines;
		statInterrupt = () {
			assert((currentRenderer.readRegister(Register.STAT) & STATValues.ppuMode) == 2);
			scanLines ~= currentRenderer.readRegister(Register.LY);
		};
		writeRegister(Register.STAT, STATValues.lycInterrupt);
		writeRegister(Register.LYC, 42);
		draw(buffer);
		assert(scanLines == [42]);
	}
}

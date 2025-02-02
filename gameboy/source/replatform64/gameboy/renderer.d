module replatform64.gameboy.renderer;

import replatform64.backend.common;
import std.exception;
import std.logger;
import std.traits;
import std.string;

import replatform64.gameboy.hardware;
import replatform64.gameboy.ppu;
import replatform64.util;

import tilemagic.colours;

struct Renderer {
	PPU ppu;
	enum width = PPU.width;
	enum height = PPU.height;
	private VideoBackend backend;
	void function() statInterrupt;
	bool holdWritesUntilHBlank;
	ubyte[ushort] cachedWrites;
	void initialize(string title, VideoBackend newBackend) {
		WindowSettings window;
		window.baseWidth = width;
		window.baseHeight = height;
		backend = newBackend;
		backend.createWindow(title, window);
		backend.createTexture(width, height, PixelFormat.bgr555);
	}
	void draw() {
		Texture texture;
		backend.getDrawingTexture(texture);
		draw(texture.asArray2D!BGR555);
	}
	void draw(scope Array2D!BGR555 texture) {
		ppu.beginDrawing(texture);
		foreach (i; 0 .. height) {
			if (ppu.registers.ly == ppu.registers.lyc) {
				ppu.registers.stat |= STATValues.lycEqualLY;
				if ((ppu.registers.stat & STATValues.lycInterrupt) && (statInterrupt !is null)) {
					statInterrupt();
				}
			} else {
				ppu.registers.stat &= ~STATValues.lycEqualLY;
			}
			if ((ppu.registers.stat & STATValues.mode2Interrupt) && (statInterrupt !is null)) {
				statInterrupt();
			}
			ppu.runLine();
			holdWritesUntilHBlank = false;
			foreach (addr, value; cachedWrites) {
				ppu.writeRegister(addr, value);
			}
			cachedWrites = null;
			if ((ppu.registers.stat & STATValues.mode0Interrupt) && (statInterrupt !is null)) {
				statInterrupt();
			}
			if ((ppu.registers.ly == 144) && (ppu.registers.stat & STATValues.mode1Interrupt) && (statInterrupt !is null)) {
				statInterrupt();
			}
		}
	}
	void waitNextFrame() {
		backend.waitNextFrame();
	}
	ubyte readRegister(ushort addr) @safe pure {
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

module replatform64.gameboy.renderer;

import replatform64.backend.common;
import std.exception;
import std.logger;
import std.traits;
import std.string;

import replatform64.gameboy.ppu;
import replatform64.util;

import tilemagic.colours;

struct Renderer {
	PPU ppu;
	enum width = PPU.width;
	enum height = PPU.height;
	private VideoBackend backend;
	void function() statInterrupt;
	void initialize(string title, VideoBackend newBackend) {
		WindowSettings window;
		window.baseWidth = width;
		window.baseHeight = height;
		backend = newBackend;
		backend.createWindow(title, window);
		backend.createTexture(width, height, PixelFormat.rgb555);
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
				ppu.registers.stat |= 0b00000100;
				if ((ppu.registers.stat & 0b01000000) && (statInterrupt !is null)) {
					statInterrupt();
				}
			} else {
				ppu.registers.stat &= ~0b00000100;
			}
			if ((ppu.registers.stat & 0b00100000) && (statInterrupt !is null)) {
				statInterrupt();
			}
			ppu.runLine();
			if ((ppu.registers.stat & 0b00001000) && (statInterrupt !is null)) {
				statInterrupt();
			}
			if ((ppu.registers.ly == 144) && (ppu.registers.stat & 0b00010000) && (statInterrupt !is null)) {
				statInterrupt();
			}
		}
	}
	void waitNextFrame() {
		backend.waitNextFrame();
	}
	ubyte readRegister(ushort addr) @safe pure {
		return ppu.readRegister(addr);
	}
	void writeRegister(ushort addr, ubyte val) @safe pure {
		ppu.writeRegister(addr, val);
	}
}

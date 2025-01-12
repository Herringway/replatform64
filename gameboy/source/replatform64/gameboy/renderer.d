module replatform64.gameboy.renderer;

import replatform64.backend.common;
import std.exception;
import std.logger;
import std.traits;
import std.string;

import replatform64.gameboy.ppu;
import replatform64.util;

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
		draw(texture.buffer[], texture.pitch);
	}
	void draw(scope ubyte[] texture, int pitch) {
		ppu.beginDrawing(texture, pitch);
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
	const(ubyte)[] getRGBA8888() {
		enum pitch = width * ushort.sizeof;
		auto buffer = new ubyte[](width * height * ushort.sizeof);
		draw(buffer, pitch);
		return bgr555ToRGBA8888(buffer, pitch);
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

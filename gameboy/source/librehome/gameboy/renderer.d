module librehome.gameboy.renderer;

import librehome.backend.common;
import std.exception;
import std.logger;
import std.traits;
import std.string;

import librehome.gameboy.ppu;

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
		backend.startFrame();
		{
			Texture texture;
			backend.getDrawingTexture(texture);
			ppu.beginDrawing(texture.buffer[], texture.pitch);
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
		backend.finishFrame();
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

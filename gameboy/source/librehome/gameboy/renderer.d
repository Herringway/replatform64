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
				ppu.runLine();
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

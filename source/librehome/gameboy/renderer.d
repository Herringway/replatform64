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
	void initialize(string title, WindowSettings settings, VideoBackend newBackend) {
		settings.width = width;
		settings.height = height;
		backend = newBackend;
		backend.initialize();
		backend.createWindow(title, settings);
		backend.createTexture(width, height, PixelFormat.rgb555);
	}
	void draw() {
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
}

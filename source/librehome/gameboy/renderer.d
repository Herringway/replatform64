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
	void initialize(string title, VideoSettings settings, VideoBackend newBackend, bool debugging, DebugFunction debugFunc) {
		WindowSettings window;
		window.width = width;
		window.height = height;
		window.userSettings = settings;
		window.debugging = debugging;
		backend = newBackend;
		backend.initialize(debugFunc);
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
}

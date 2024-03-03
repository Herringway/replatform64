module librehome.nes.renderer;

import librehome.backend.common;
import librehome.nes.ppu;

struct Renderer {
	PPU ppu;
	enum width = PPU.width;
	enum height = PPU.height;
	private VideoBackend backend;
	void initialize(string title, VideoSettings settings, VideoBackend newBackend, bool debugging, DebugFunction debugFunc, DebugFunction platformDebugFunc) {
		WindowSettings window;
		window.width = width;
		window.height = height;
		window.userSettings = settings;
		window.debugging = debugging;
		backend = newBackend;
		backend.initialize();
		backend.setDebuggingFunctions(debugFunc, platformDebugFunc, null, null);
		backend.createWindow(title, window);
		backend.createTexture(width, height, PixelFormat.rgb555);
		ppu.nesCPUVRAM = new ubyte[](0x4000);
	}
	void draw() {
		backend.startFrame();
		{
			Texture texture;
			backend.getDrawingTexture(texture);
			ppu.render(cast(uint[])(texture.buffer[]));
		}
		backend.finishFrame();
	}
	void waitNextFrame() {
		backend.waitNextFrame();
	}
}

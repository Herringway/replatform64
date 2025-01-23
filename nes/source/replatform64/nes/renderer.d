module replatform64.nes.renderer;

import replatform64.backend.common;
import replatform64.nes.ppu;

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
		backend.createTexture(width, height, PixelFormat.argb8888);
		ppu.nesCPUVRAM = new ubyte[](0x4000);
	}
	void draw() {
		Texture texture;
		backend.getDrawingTexture(texture);
		ppu.render(cast(uint[])(texture.buffer[]));
	}
	void waitNextFrame() {
		backend.waitNextFrame();
	}
	void writeRegister(ushort addr, ubyte val) @safe pure {
		ppu.writeRegister(addr, val);
	}
	ubyte readRegister(ushort addr) @safe pure {
		return ppu.readRegister(addr);
	}
}

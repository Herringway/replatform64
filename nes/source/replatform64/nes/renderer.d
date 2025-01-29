module replatform64.nes.renderer;

import replatform64.backend.common;
import replatform64.nes.ppu;

import tilemagic.colours;

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
		backend.createTexture(width, height, PixelFormat.bgra8888);
		ppu.chr = new ubyte[](0x2000);
		ppu.nametable = new ubyte[](0x1000);
	}
	void draw() {
		Texture texture;
		backend.getDrawingTexture(texture);
		ppu.render(texture.asArray2D!ARGB8888);
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

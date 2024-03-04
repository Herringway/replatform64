module librehome.nes.renderer;

import librehome.backend.common;
import librehome.nes.ppu;

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
	void writeRegister(ushort addr, ubyte val) @safe pure {
		ppu.writeRegister(addr, val);
	}
	ubyte readRegister(ushort addr) @safe pure {
		return ppu.readRegister(addr);
	}
}

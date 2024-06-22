import replatform64;
import replatform64.gameboy;

import std.format;
import std.functional;
import std.logger;

struct GameSettings {}
GameBoySimple gb;

void main() {
	(cast(Logger)sharedLog).logLevel = LogLevel.trace;
	gb.entryPoint = &start;
	gb.interruptHandlerVBlank = &vblank;
	gb.title = "Hello World";
	gb.sourceFile = "helloworld.gb";
	gb.gameID = "helloworld";
	auto settings = gb.loadSettings!GameSettings();
	gb.initialize();
	gb.loadAssets!(mixin(__MODULE__))(null);
	gb.run();
	gb.saveSettings(settings);
}
@Asset("8x8font.png", DataType.bpp2Intertwined)
immutable(ubyte)[] fontData;

@Asset("obj.png", DataType.bpp2Intertwined)
immutable(ubyte)[] objData;

ubyte inputPressed;
void readInput() {
	gb.writeJoy(0x20);
	ubyte tmp = ((~gb.readJoy()) & 0xF) << 4;
	gb.writeJoy(0x10);
	tmp |= ~gb.readJoy() & 0xF;
	inputPressed = tmp;
	gb.writeJoy(0x30);
}

void printText(ubyte x, ubyte y, string str) {
	foreach (chr; str) {
		if (chr < ' ') {
			continue;
		}
		if (chr > 0x7F) {
			continue;
		}
		gb.vram[0x9800 + y * 32 + x++] = cast(ubyte)(chr - 0x20);
	}
}

void start(ushort system) {
	gb.LCDC = 0;
	gb.vram[0x8000 .. 0x8000 + objData.length] = objData;
	gb.vram[0x9000 .. 0x9000 + fontData.length] = fontData;
	printText(2, 8, "Hello world");
	gb.SCY = 0;
	gb.SCX = 0;
	gb.NR52 = 0;
	gb.BGP = 0b11100100;
	gb.LCDC = 0b10000011;
	(cast(OAMEntry[])gb.oam[])[] = OAMEntry(-1, -1, 64, 0);
	(cast(OAMEntry[])gb.oam[])[0] = OAMEntry(0, 0, 0, 0);
	(cast(OAMEntry[])gb.oam[])[1] = OAMEntry(0, 0, 2, 0);
	(cast(OAMEntry[])gb.oam[])[2] = OAMEntry(0, 0, 3, 0);
	(cast(OAMEntry[])gb.oam[])[3] = OAMEntry(0, 0, 2, OAMFlags.yFlip);
	(cast(OAMEntry[])gb.oam[])[4] = OAMEntry(0, 0, 3, OAMFlags.xFlip);
	short x = 64;
	short y = 64;
	uint altFrames = 0;
	while (true) {
		readInput();
		if (inputPressed & Pad.a) {
			printText(13, 8, "!");
		} else if (inputPressed & Pad.b) {
			printText(13, 8, ".");
		} else {
			printText(13, 8, " ");
		}
		if (inputPressed & Pad.left) {
			x--;
		} else if (inputPressed & Pad.right) {
			x++;
		}
		if (inputPressed & Pad.up) {
			y--;
		} else if (inputPressed & Pad.down) {
			y++;
		}
		if (x > 160) {
			x = 160;
			altFrames = 15;
		} else if (x < 8) {
			x = 8;
			altFrames = 15;
		}
		if (y > 144) {
			y = 144;
			altFrames = 15;
		} else if (y < 8) {
			y = 8;
			altFrames = 15;
		}
		bool useAltFrame;
		if (altFrames != 0) {
			altFrames--;
			useAltFrame = true;
		}
		(cast(OAMEntry[])gb.oam[])[0].x = cast(ubyte)x;
		(cast(OAMEntry[])gb.oam[])[0].y = cast(ubyte)(y + 8);
		(cast(OAMEntry[])gb.oam[])[1].x = cast(ubyte)x;
		(cast(OAMEntry[])gb.oam[])[1].y = cast(ubyte)y;
		(cast(OAMEntry[])gb.oam[])[2].x = cast(ubyte)(x - 8);
		(cast(OAMEntry[])gb.oam[])[2].y = cast(ubyte)(y + 8);
		(cast(OAMEntry[])gb.oam[])[3].x = cast(ubyte)x;
		(cast(OAMEntry[])gb.oam[])[3].y = cast(ubyte)(y + 16);
		(cast(OAMEntry[])gb.oam[])[4].x = cast(ubyte)(x + 8);
		(cast(OAMEntry[])gb.oam[])[4].y = cast(ubyte)(y + 8);
		(cast(OAMEntry[])gb.oam[])[0].tile = useAltFrame ? 1 : 0;
		gb.wait();
	}
}
void vblank() {

}

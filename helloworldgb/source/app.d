import replatform64.gameboy;

import std.format;
import std.functional;
import std.logger;

struct GameSettings {}
GameBoySimple gb;

OAMEntry[5] oam;

void main(string[] args) {
	gb.entryPoint = &start;
	gb.interruptHandlerVBlank = &vblank;
	gb.title = "Hello World (GB)";
	gb.sourceFile = "helloworld.gb";
	gb.gameID = "helloworld";
	if (gb.parseArgs(args)) {
		return;
	}
	auto settings = gb.loadSettings!GameSettings();
	gb.initialize();
	gb.handleAssets!(mixin(__MODULE__))();
	gb.run();
	gb.saveSettings(settings);
}
@Asset("8x8font.png", DataType.bpp2Intertwined)
immutable(ubyte)[] fontData;

@Asset("obj.png", DataType.bpp2Intertwined)
immutable(ubyte)[] objData;

@Asset("config.yaml", DataType.structured)
Config config;

struct Vector {
	ubyte x;
	ubyte y;
}
struct Dimensions {
	ubyte width;
	ubyte height;
}
struct Config {
	ubyte movementSpeed = 1;
	string text = "Hello world";
	Vector textCoordinates = Vector(2, 8);
	Vector startCoordinates = Vector(64, 64);
	Dimensions playerDimensions = Dimensions(width: 10, height: 10);
	ubyte recoilFrames = 15;
}

ubyte inputPressed;
void readInput() {
	gb.writeJoy(0x20);
	ubyte tmp = ((~gb.readJoy()) & 0xF) << 4;
	gb.writeJoy(0x10);
	tmp |= ~gb.readJoy() & 0xF;
	inputPressed = tmp;
	gb.writeJoy(0x30);
}
void writeToVRAM(scope const ubyte[] data, ushort addr) {
	gb.vram[addr .. addr + data.length] = data;
}
void init() {
	gb.LCDC = 0;
}
void load() {
	writeToVRAM(objData, 0x8000);
	assert(objData.length, "Could not load OBJ data");
	writeToVRAM(fontData, 0x9000);
	assert(fontData.length, "Could not load font data");
	printText(config.textCoordinates.x, config.textCoordinates.y, config.text);
}
void startRendering() {
	gb.SCY = 0;
	gb.SCX = 0;
	gb.NR52 = 0;
	gb.BGP = 0b11100100;
	gb.LCDC = 0b10000011;
}
void finishFrame() {
	gb.wait();
}
void printText(ubyte x, ubyte y, string str) {
	ubyte[16] buffer;
	size_t position;
	ushort addr = cast(ushort)(0x9800 + y * 32 + x);
	foreach (chr; str) {
		if (chr < ' ') {
			continue;
		}
		if (chr > 0x7F) {
			continue;
		}
		buffer[position++] = cast(ubyte)(chr - 0x20);
		if (position == 16) {
			writeToVRAM(buffer[], addr);
			addr += 16;
			position = 0;
		}
	}
	if (position != 0) {
		writeToVRAM(buffer[0 .. position], addr);
	}
}
string punctuation = "!";
void start(ushort system) {
	init();
	load();
	startRendering();
	oam[0] = OAMEntry(0, 0, 0, 0);
	oam[1] = OAMEntry(0, 0, 2, 0);
	oam[2] = OAMEntry(0, 0, 3, 0);
	oam[3] = OAMEntry(0, 0, 2, OAMFlags.yFlip);
	oam[4] = OAMEntry(0, 0, 3, OAMFlags.xFlip);
	short x = config.startCoordinates.x;
	short y = config.startCoordinates.y;
	uint altFrames = 0;
	while (true) {
		readInput();
		if (inputPressed & Pad.a) {
			punctuation = "!";
		} else if (inputPressed & Pad.b) {
			punctuation = ".";
		} else {
			punctuation = " ";
		}
		if (inputPressed & Pad.left) {
			x -= config.movementSpeed;
		} else if (inputPressed & Pad.right) {
			x += config.movementSpeed;
		}
		if (inputPressed & Pad.up) {
			y -= config.movementSpeed;
		} else if (inputPressed & Pad.down) {
			y += config.movementSpeed;
		}
		if (x > 160) {
			x = 160;
			altFrames = config.recoilFrames;
		} else if (x < config.playerDimensions.width) {
			x = config.playerDimensions.width;
			altFrames = config.recoilFrames;
		}
		if (y > 144) {
			y = 144;
			altFrames = config.recoilFrames;
		} else if (y < config.playerDimensions.height) {
			y = config.playerDimensions.height;
			altFrames = config.recoilFrames;
		}
		bool useAltFrame;
		if (altFrames != 0) {
			altFrames--;
			useAltFrame = true;
		}
		oam[0].x = cast(ubyte)x;
		oam[0].y = cast(ubyte)(y + 8);
		oam[0].tile = useAltFrame ? 1 : 0;
		oam[1].x = cast(ubyte)x;
		oam[1].y = cast(ubyte)y;
		oam[2].x = cast(ubyte)(x - 8);
		oam[2].y = cast(ubyte)(y + 8);
		oam[3].x = cast(ubyte)x;
		oam[3].y = cast(ubyte)(y + 16);
		oam[4].x = cast(ubyte)(x + 8);
		oam[4].y = cast(ubyte)(y + 8);
		finishFrame();
	}
}
void vblank() {
	(cast(OAMEntry[])(gb.oam))[] = OAMEntry(-1, -1, 64, 0);
	(cast(OAMEntry[])(gb.oam))[0 .. 5] = oam;
	printText(cast(ubyte)(config.textCoordinates.x + config.text.length), config.textCoordinates.y, punctuation);
}

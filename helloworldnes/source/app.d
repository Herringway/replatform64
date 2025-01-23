import replatform64.nes;

import std.format;
import std.functional;
import std.logger;

struct GameSettings {}
NES nes;

ubyte[4][8] palettes = [
	// bg palettes
	// bg
	[ 0x30, 0x0F, 0x30, 0x30 ],
	// unused
	[ 0x0F, 0x0F, 0x0F, 0x0F ],
	[ 0x0F, 0x0F, 0x0F, 0x0F ],
	[ 0x0F, 0x0F, 0x0F, 0x0F ],
	// sprite palettes
	// lil character
	[ 0x30, 0x0F, 0x21, 0x16 ],
	// unused
	[ 0x0F, 0x0F, 0x0F, 0x0F ],
	[ 0x0F, 0x0F, 0x0F, 0x0F ],
	[ 0x0F, 0x0F, 0x0F, 0x0F ],
];

OAMEntry[64] oam = OAMEntry.offscreen;

void main(string[] args) {
	if (nes.parseArgs(args)) {
		return;
	}
	nes.entryPoint = &start;
	nes.interruptHandlerVBlank = &vblank;
	nes.title = "Hello World";
	nes.gameID = "helloworld";
	auto settings = nes.loadSettings!GameSettings();
	nes.initialize();
	nes.handleAssets!(mixin(__MODULE__))();
	nes.run();
	nes.saveSettings(settings);
}
@Asset("8x8font.png", DataType.bpp2Linear)
immutable(ubyte)[] fontData;

@Asset("obj.png", DataType.bpp2Linear)
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
	inputPressed = nes.getControllerState(0);
}
void init() {
	nes.JOY2 = 0x40;
	nes.PPUCTRL = 0;
	nes.PPUMASK = 0;
	nes.DMC_FREQ = 0;
	while ((nes.PPUSTATUS & 0x80) == 0) {}
	while ((nes.PPUSTATUS & 0x80) == 0) {}
}
void writeToVRAM(const(ubyte)[] src, ushort dest) {
	//tracef("Transferring %s bytes to %04X", src.length, dest);
	nes.PPUADDR = dest >> 8;
	nes.PPUADDR = dest & 0xFF;
	while (src.length > 0) {
		nes.PPUDATA = src[0];
		src = src[1 .. $];
	}
}
void load() {
	writeToVRAM(objData, 0x0000);
	writeToVRAM(fontData, 0x1000);
	printText(config.textCoordinates.x, config.textCoordinates.y, config.text);
}
void startRendering() {
	nes.PPUCTRL = 0b1001_0000;
	nes.PPUMASK = 0b0001_1110;
}
void finishFrame() {
	nes.wait();
}
void printText(ubyte x, ubyte y, string str) {
	ubyte[16] buffer;
	size_t position;
	ushort addr = cast(ushort)(0x2000 + y * 32 + x);
	foreach (chr; str) {
		if (chr < ' ') {
			continue;
		}
		if (chr > 0x7F) {
			continue;
		}
		buffer[position++] = cast(ubyte)(chr - 0x20);
		if (position == 16) {
			writeToVRAM(cast(ubyte[])buffer[], addr);
			addr += 16;
			position = 0;
		}
	}
	if (position != 0) {
		writeToVRAM(cast(ubyte[])buffer[0 .. position], addr);
	}
}
void start() {
	string punctuation = "!";
	init();
	load();
	startRendering();
	oam[0] = OAMEntry(0, 0, 0);
	oam[1] = OAMEntry(0, 0, 2);
	oam[2] = OAMEntry(0, 0, 3);
	oam[3] = OAMEntry(0, 0, 2, vFlip: true);
	oam[4] = OAMEntry(0, 0, 3, hFlip: true);
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
		if (x > nes.width - 1) {
			x = nes.width - 1;
			altFrames = config.recoilFrames;
		} else if (x < config.playerDimensions.width + 1) {
			x = config.playerDimensions.width + 1;
			altFrames = config.recoilFrames;
		}
		if (y > nes.height - 1) {
			y = nes.height - 1;
			altFrames = config.recoilFrames;
		} else if (y < config.playerDimensions.height + 1) {
			y = config.playerDimensions.height + 1;
			altFrames = config.recoilFrames;
		}
		bool useAltFrame;
		if (altFrames != 0) {
			altFrames--;
			useAltFrame = true;
		}
		ubyte baseX = cast(ubyte)(x - 8);
		ubyte baseY = cast(ubyte)(y - 8);
		oam[0].x = baseX;
		oam[0].y = baseY;
		oam[0].index = useAltFrame ? 1 : 0;
		oam[1].x = baseX;
		oam[1].y = cast(ubyte)(baseY - 8);
		oam[2].x = cast(ubyte)(baseX - 8);
		oam[2].y = baseY;
		oam[3].x = baseX;
		oam[3].y = cast(ubyte)(baseY + 8);
		oam[4].x = cast(ubyte)(baseX + 8);
		oam[4].y = baseY;
		finishFrame();
		printText(cast(ubyte)(config.textCoordinates.x + config.text.length), config.textCoordinates.y, punctuation);
	}
}
void vblank() {
	nes.handleOAMDMA(oam[], 0);
	writeToVRAM(cast(const(ubyte)[])palettes, 0x3F00);
}

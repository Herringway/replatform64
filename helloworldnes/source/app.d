import replatform64.nes;

import std.format;
import std.functional;
import std.logger;

struct GameState {
	char[5] magic = "HELLO";
	short x;
	short y;
}
struct GameSettings {}
NES!() nes;

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
	nes.entryPoint = &start;
	nes.interruptHandlerVBlank = &vblank;
	nes.title = "Hello World (NES)";
	nes.gameID = "helloworld";
	if (nes.parseArgs(args)) {
		return;
	}
	auto settings = nes.loadSettings!GameSettings();
	nes.initialize();
	nes.handleAssets!(mixin(__MODULE__))(&loadStuff);
	nes.run();
	nes.saveSettings(settings);
}
@Asset("8x8font.png", DataType.bpp2Linear)
immutable(ubyte)[] fontData;

@Asset("obj.png", DataType.bpp2Linear)
immutable(ubyte)[] objData;

@Asset("config.yaml", DataType.structured)
Config config;

void loadStuff(scope AddFileFunction addFile, scope ProgressUpdateFunction reportProgress, immutable(ubyte)[] rom) @safe {}

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

ubyte readInput() @safe {
	return nes.getControllerState(0);
}
void init() @safe {
	nes.JOY2 = JOY2Value(interruptInhibit: true, sequenceMode: SequenceMode.step4);
	nes.PPUCTRL = 0;
	nes.PPUMASK = 0;
	nes.DMC_FREQ = 0;
	while ((nes.PPUSTATUS & 0x80) == 0) {}
	while ((nes.PPUSTATUS & 0x80) == 0) {}
}
void writeToVRAM(const(ubyte)[] src, ushort dest) @safe {
	//tracef("Transferring %s bytes to %04X", src.length, dest);
	nes.PPUADDR = dest >> 8;
	nes.PPUADDR = dest & 0xFF;
	while (src.length > 0) {
		nes.PPUDATA = src[0];
		src = src[1 .. $];
	}
}
void load() @safe {
	writeToVRAM(objData, 0x0000);
	writeToVRAM(fontData, 0x1000);
	printText(config.textCoordinates.x, config.textCoordinates.y, config.text);
}
void startRendering() @safe {
	nes.PPUCTRL = 0b1001_0000;
	nes.PPUMASK = 0b0001_1110;
}
void finishFrame() @safe {
	nes.wait();
}
void printText(ubyte x, ubyte y, string str) @safe {
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
void start() @safe {
	string punctuation = "!";
	init();
	load();
	startRendering();
	oam[0] = OAMEntry(x: 0, y: 0, tile: 0);
	oam[1] = OAMEntry(x: 0, y: 0, tile: 2);
	oam[2] = OAMEntry(x: 0, y: 0, tile: 3);
	oam[3] = OAMEntry(x: 0, y: 0, tile: 2, vFlip: true);
	oam[4] = OAMEntry(x: 0, y: 0, tile: 3, hFlip: true);
	auto state = nes.sram!GameState(0);
	if (state.magic != state.init.magic) {
		state = state.init;
		state.x = config.startCoordinates.x;
		state.y = config.startCoordinates.y;
	}
	uint altFrames = 0;
	int saveFramesLeft;
	ubyte inputPressed;
	while (true) {
		const lastPressed = inputPressed;
		inputPressed = readInput();
		const justPressed = (lastPressed ^ inputPressed) & inputPressed;
		if (inputPressed & Pad.a) {
			punctuation = "!";
		} else if (inputPressed & Pad.b) {
			punctuation = ".";
		} else {
			punctuation = " ";
		}
		if (justPressed & Pad.start) {
			saveFramesLeft = 60;
			nes.sram!GameState(0) = state;
			nes.commitSRAM();
		}
		if (inputPressed & Pad.left) {
			state.x -= config.movementSpeed;
		} else if (inputPressed & Pad.right) {
			state.x += config.movementSpeed;
		}
		if (inputPressed & Pad.up) {
			state.y -= config.movementSpeed;
		} else if (inputPressed & Pad.down) {
			state.y += config.movementSpeed;
		}
		if (state.x > nes.width - 1) {
			state.x = nes.width - 1;
			altFrames = config.recoilFrames;
		} else if (state.x < config.playerDimensions.width + 1) {
			state.x = config.playerDimensions.width + 1;
			altFrames = config.recoilFrames;
		}
		if (state.y > nes.height - 1) {
			state.y = nes.height - 1;
			altFrames = config.recoilFrames;
		} else if (state.y < config.playerDimensions.height + 1) {
			state.y = config.playerDimensions.height + 1;
			altFrames = config.recoilFrames;
		}
		bool useAltFrame;
		if (altFrames != 0) {
			altFrames--;
			useAltFrame = true;
		}
		ubyte baseX = cast(ubyte)(state.x - 8);
		ubyte baseY = cast(ubyte)(state.y - 8);
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
		if (saveFramesLeft > 0) {
			saveFramesLeft--;
			printText(12, 12, "State saved");
		} else {
			printText(12, 12, "           ");
		}
		printText(cast(ubyte)(config.textCoordinates.x + config.text.length), config.textCoordinates.y, punctuation);
		finishFrame();
	}
}
void vblank() @safe {
	nes.handleOAMDMA(oam[], 0);
	writeToVRAM(cast(const(ubyte)[])palettes, 0x3F00);
}

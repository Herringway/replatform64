import replatform64.snes;

import std.format;
import std.functional;
import std.logger;

struct GameState {
	char[5] magic = "HELLO";
	short x;
	short y;
}
struct GameSettings {}
SNES snes;


OAMEntry[128] oam = OAMEntry.offscreen; // all unused sprites should render offscreen

void main(string[] args) {
	snes.entryPoint = &start;
	snes.interruptHandlerVBlank = &vblank;
	snes.title = "Hello World (SNES)";
	snes.gameID = "helloworld";
	if (snes.parseArgs(args)) {
		return;
	}
	auto settings = snes.loadSettings!GameSettings();
	snes.initialize();
	snes.handleAssets!(mixin(__MODULE__))(&loadStuff);
	snes.run();
	snes.saveSettings(settings);
}

@Asset("basepalette.png", DataType.paletteBGR555, paletteDepth: 4)
immutable(BGR555[16])[] palettes;

@Asset("8x8font.png", DataType.bpp4Intertwined)
immutable(ubyte)[] fontData;

@Asset("obj.png", DataType.bpp4Intertwined)
immutable(ubyte)[] objData;

@Asset("config.yaml", DataType.structured)
Config config;
void loadStuff(scope AddFileFunction addFile, scope ProgressUpdateFunction reportProgress, immutable(ubyte)[] rom) @safe {
	infof("Loaded data successfully");
}

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

ushort readInput() @safe {
	return snes.getControllerState(0);
}
void writeToVRAM(scope const ubyte[] data, ushort addr) @safe
	in(data.length)
{
	snes.handleVRAMDMA(0b00000001, 0x18, data, cast(ushort)data.length, addr, 0b10000000);
}
void init() @safe {
	snes.INIDISP = 0x80; // display off while we set up
	snes.BGMODE = 0; // mode 0
	snes.BG1SC = 0x1000 >> 8; // BG1 tilemap at $1000
	snes.BG12NBA = 0x44; // BG 1 + 2 tiles at $4000
	snes.OBSEL = 0x01; // OBJ tiles at $2000
}
void load() @safe {
	writeToVRAM(objData, 0x2000);
	writeToVRAM(fontData, 0x4000);
	printText(config.textCoordinates.x, config.textCoordinates.y, config.text);
}
void startRendering() @safe {
	snes.INIDISP = 0x0F; // screen on, max brightness
	snes.TM = 0x11; // obj + bg 1 enabled
	snes.NMITIMEN = 0x80; // vblank enabled
}
void finishFrame() @safe {
	snes.wait();
}
void printText(ubyte x, ubyte y, string str) @safe {
	ushort[16] buffer;
	size_t position;
	ushort addr = cast(ushort)(0x1000 + y * 32 + x);
	foreach (chr; str) {
		if (chr < ' ') {
			continue;
		}
		if (chr > 0x7F) {
			continue;
		}
		buffer[position++] = cast(ushort)((chr - 0x20) * 2);
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
string punctuation = "!";
void start() @safe {
	init();
	load();
	startRendering();
	oam[0] = OAMEntry(0, 0, 0);
	oam[1] = OAMEntry(0, 0, 2);
	oam[2] = OAMEntry(0, 0, 3);
	oam[3] = OAMEntry(0, 0, 2, vFlip: true);
	oam[4] = OAMEntry(0, 0, 3, hFlip: true);
	auto state = snes.sram!GameState(0);
	if (state.magic != state.init.magic) {
		state = state.init;
		state.x = config.startCoordinates.x;
		state.y = config.startCoordinates.y;
	}
	uint altFrames = 0;
	int saveFramesLeft;
	ushort inputPressed;
	while (true) {
		const lastPressed = inputPressed;
		inputPressed = readInput();
		const justPressed = (lastPressed ^ inputPressed) & inputPressed;
		readInput();
		if (inputPressed & Pad.a) {
			punctuation = "!";
		} else if (inputPressed & Pad.b) {
			punctuation = ".";
		} else {
			punctuation = " ";
		}
		if (justPressed & Pad.start) {
			saveFramesLeft = 60;
			snes.sram!GameState(0) = state;
			snes.commitSRAM();
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
		if (state.x > snes.screenWidth - 1) {
			state.x = cast(short)(snes.screenWidth - 1);
			altFrames = config.recoilFrames;
		} else if (state.x < config.playerDimensions.width + 1) {
			state.x = config.playerDimensions.width + 1;
			altFrames = config.recoilFrames;
		}
		if (state.y > snes.screenHeight - 1) {
			state.y = cast(short)(snes.screenHeight - 1);
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
		oam[0].xCoord = baseX;
		oam[0].yCoord = baseY;
		oam[0].startingTile = useAltFrame ? 1 : 0;
		oam[1].xCoord = baseX;
		oam[1].yCoord = cast(ubyte)(baseY - 8);
		oam[2].xCoord = cast(ubyte)(baseX - 8);
		oam[2].yCoord = baseY;
		oam[3].xCoord = baseX;
		oam[3].yCoord = cast(ubyte)(baseY + 8);
		oam[4].xCoord = cast(ubyte)(baseX + 8);
		oam[4].yCoord = baseY;
		if (saveFramesLeft > 0) {
			saveFramesLeft--;
			printText(0, 16, "State saved");
		} else {
			printText(0, 16, "           ");
		}
		printText(cast(ubyte)(config.textCoordinates.x + config.text.length), config.textCoordinates.y, punctuation);
		finishFrame();
	}
}
void vblank() @safe {
	snes.handleCGRAMDMA(0b00000000, 0x22, cast(const(ubyte)[])palettes[], cast(ushort)(palettes.length * palettes[0].sizeof), 0);
	snes.handleOAMDMA(0b00000000, 0x04, cast(const(ubyte)[])oam[], cast(ushort)(oam.length * OAMEntry.sizeof), 0);
}

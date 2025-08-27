import replatform64.gameboy;

import std.format;
import std.functional;
import std.logger;

struct GameState {
	char[5] magic = "HELLO";
	short x;
	short y;
}
struct GameSettings {}
GameBoySimple gb;

OAMEntry[5] oam;

void main(string[] args) {
	gb.entryPoint = &start;
	gb.interruptHandlerVBlank = &vblank;
	gb.title = "Hello World (GB)";
	gb.gameID = "helloworld";
	if (gb.parseArgs(args)) {
		return;
	}
	auto settings = gb.loadSettings!GameSettings();
	gb.initialize();
	gb.handleAssets!(mixin(__MODULE__))(&loadStuff);
	gb.run();
	gb.saveSettings(settings);
}
@Asset("8x8font.png", DataType.bpp2Intertwined)
immutable(ubyte)[] fontData;

@Asset("obj.png", DataType.bpp2Intertwined)
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
	gb.JOYP = 0x20;
	ubyte inputPressed = (~gb.JOYP & 0xF) << 4;
	gb.JOYP = 0x10;
	inputPressed |= ~gb.JOYP & 0xF;
	gb.JOYP = 0x30;
	return inputPressed;
}
void writeToVRAM(scope const ubyte[] data, ushort addr) @safe {
	gb.vram[addr - 0x8000 .. addr - 0x8000 + data.length] = data;
}
void init() @safe {
	gb.enableInterrupts();
	gb.LCDC = 0;
}
void load() @safe {
	writeToVRAM(objData, 0x8000);
	assert(objData.length, "Could not load OBJ data");
	writeToVRAM(fontData, 0x9000);
	assert(fontData.length, "Could not load font data");
	gb.IE = InterruptFlag.vblank;
	printText(config.textCoordinates.x, config.textCoordinates.y, config.text);
}
void startRendering() @safe {
	gb.SCY = 0;
	gb.SCX = 0;
	gb.NR52 = 0;
	gb.BGP = 0b11100100;
	gb.LCDC = 0b10000011;
}
void finishFrame() @safe {
	gb.wait();
}
void printText(ubyte x, ubyte y, string str) @safe {
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
void start(ushort system) @safe {
	init();
	load();
	startRendering();
	oam[0] = OAMEntry(0, 0, 0, 0);
	oam[1] = OAMEntry(0, 0, 2, 0);
	oam[2] = OAMEntry(0, 0, 3, 0);
	oam[3] = OAMEntry(0, 0, 2, OAMFlags.yFlip);
	oam[4] = OAMEntry(0, 0, 3, OAMFlags.xFlip);
	auto state = gb.sram!GameState(0);
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
			gb.sram!GameState(0) = state;
			gb.commitSRAM();
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
		if (state.x > gb.width - 1) {
			state.x = gb.width - 1;
			altFrames = config.recoilFrames;
		} else if (state.x < config.playerDimensions.width) {
			state.x = config.playerDimensions.width;
			altFrames = config.recoilFrames;
		}
		if (state.y > gb.height - 1) {
			state.y = gb.height - 1;
			altFrames = config.recoilFrames;
		} else if (state.y < config.playerDimensions.height) {
			state.y = config.playerDimensions.height;
			altFrames = config.recoilFrames;
		}
		bool useAltFrame;
		if (altFrames != 0) {
			altFrames--;
			useAltFrame = true;
		}
		ubyte baseX = cast(ubyte)(state.x);
		ubyte baseY = cast(ubyte)(state.y + 8);
		oam[0].x = baseX;
		oam[0].y = baseY;
		oam[0].tile = useAltFrame ? 1 : 0;
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
			printText(0, 16, "State saved");
		} else {
			printText(0, 16, "           ");
		}
		printText(cast(ubyte)(config.textCoordinates.x + config.text.length), config.textCoordinates.y, punctuation);
		finishFrame();
	}
}
void vblank() @safe {
	(cast(OAMEntry[])(gb.oam))[] = OAMEntry(-1, -1, 64, 0);
	(cast(OAMEntry[])(gb.oam))[0 .. 5] = oam;
}

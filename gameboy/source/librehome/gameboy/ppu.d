module librehome.gameboy.ppu;

import librehome.testhelpers;

import std.bitmanip : bitfields;

enum LCDCFlags {
	bgEnabled = 1 << 0,
	spritesEnabled = 1 << 1,
	tallSprites = 1 << 2,
	bgTilemap = 1 << 3,
	useAltBG = 1 << 4,
	windowDisplay = 1 << 5,
	windowTilemap = 1 << 6,
	lcdEnabled = 1 << 7,
}

enum OAMFlags {
	palette = 1 << 4,
	xFlip = 1 << 5,
	yFlip = 1 << 6,
	priority = 1 << 7,
}

struct OAMEntry {
	align(1):
	ubyte y;
	ubyte x;
	ubyte tile;
	ubyte flags;
	this(byte a, byte b, ubyte c, ubyte d) {
		y = a;
		x = b;
		tile = c;
		flags = d;
	}
	this(ubyte a) {
		y = a;
	}
}
struct PPU {
	static struct Registers {
		ubyte stat;
		ubyte lcdc;
		ubyte scy;
		ubyte scx;
		ubyte ly;
		ubyte lyc;
		ubyte bgp;
		ubyte obp0;
		ubyte obp1;
		ubyte wy;
		ubyte wx;
	}
	enum fullTileWidth = 32;
	enum fullTileHeight = 32;
	enum width = 160;
	enum height = 144;
	Registers registers;
	ubyte[] vram;
	immutable(ushort)[] gbPalette = pocketPalette;

	private ubyte scanline;
	private ubyte[] pixels;
	private size_t stride;
	private OAMEntry[] oamSorted;
	void runLine() @safe pure {
		const baseX = registers.scx;
		const baseY = registers.scy + scanline;
		auto pixelRow = cast(ushort[])(pixels[scanline * stride .. (scanline + 1) * stride]);
		const tilemapBase = ((baseY / 8) % fullTileWidth) * 32;
		const tilemapRow = bgScreen[tilemapBase .. tilemapBase + fullTileWidth];
		lineLoop: foreach (x; 0 .. width) {
			size_t highestMatchingSprite = size_t.max;
			int highestX = int.max;
			foreach (idx, sprite; oamSorted) {
				if (scanline.inRange(sprite.y - 16, sprite.y - ((registers.lcdc & LCDCFlags.tallSprites) ? 0 : 8)) && x.inRange(sprite.x - 8, sprite.x)) {
					auto xpos = x - (sprite.x - 8);
					auto ypos = (scanline - (sprite.y - 16));
					if (sprite.flags & OAMFlags.xFlip) {
						xpos = 7 - xpos;
					}
					if (sprite.flags & OAMFlags.yFlip) {
						ypos = 7 - ypos;
					}
					// ignore transparent pixels
					if (getPixel(getTile(cast(short)(sprite.tile + ypos / 8), false)[ypos % 8], xpos) == 0) {
						continue;
					}
					if (sprite.x - 8 < highestX) {
						highestX = sprite.x - 8;
						highestMatchingSprite = idx;
						version(assumeOAMImmutableDiscarded) {
							break;
						}
					}
				}
			}
			if (highestMatchingSprite != size_t.max) {
				const sprite = oamSorted[highestMatchingSprite];
				auto xpos = x - (sprite.x - 8);
				auto ypos = (scanline - (sprite.y - 16));
				if (sprite.flags & OAMFlags.xFlip) {
					xpos = 7 - xpos;
				}
				if (sprite.flags & OAMFlags.yFlip) {
					ypos = 7 - ypos;
				}
				const pixel = getPixel(getTile(cast(short)(sprite.tile + ypos / 8), false)[ypos % 8], xpos);
				if (pixel != 0) {
					pixelRow[x] = getColour(pixel);
					continue;
				}
			}
			if ((registers.lcdc & LCDCFlags.windowDisplay) && (x >= registers.wx - 7) && (scanline >= registers.wy)) {
				const finalX = x - (registers.wx - 7);
				const finalY = scanline - registers.wy;
				const windowTilemapBase = (finalY / 8) * 32;
				const windowTilemapRow = windowScreen[windowTilemapBase .. windowTilemapBase + fullTileWidth];
				pixelRow[x] = getColour(getPixel(getTile(windowTilemapRow[finalX / 8], true)[finalY % 8], finalX % 8));
			} else {
				const finalX = baseX + x;
				pixelRow[x] = getColour(getPixel(getTile(tilemapRow[(finalX / 8) % 32], true)[baseY % 8], finalX % 8));
			}
		}
		scanline++;
	}
	ubyte[] bgScreen() @safe pure {
		return (registers.lcdc & LCDCFlags.bgTilemap) ? screenB : screenA;
	}
	ubyte[] tileBlockA() @safe pure {
		return vram[0x8000 .. 0x8800];
	}
	ubyte[] tileBlockB() @safe pure {
		return vram[0x8800 .. 0x9000];
	}
	ubyte[] tileBlockC() @safe pure {
		return vram[0x9000 .. 0x9800];
	}
	ubyte[] screenA() @safe pure {
		return vram[0x9800 .. 0x9C00];
	}
	ubyte[] screenB() @safe pure {
		return vram[0x9C00 .. 0xA000];
	}
	ubyte[] oam() @safe pure {
		return vram[0xFE00 .. 0xFE00 + 40 * OAMEntry.sizeof];
	}
	ubyte[] windowScreen() @safe pure {
		return (registers.lcdc & LCDCFlags.windowTilemap) ? screenB : screenA;
	}
	ushort getColour(int b) @safe pure {
		const paletteMap = (registers.bgp >> (b * 2)) & 0x3;
		return gbPalette[paletteMap];
	}
	ushort[8] getTile(short id, bool useLCDC) @safe pure {
		const tileBlock = (id > 127) ? tileBlockB : ((useLCDC && !(registers.lcdc & LCDCFlags.useAltBG) ? tileBlockC : tileBlockA));
		return (cast(const(ushort[8])[])(tileBlock[(id % 128) * 16 .. ((id % 128) * 16) + 16]))[0];
	}
	void beginDrawing(ubyte[] pixels, size_t stride) @safe pure {
		oamSorted = cast(OAMEntry[])oam;
		// optimization that can be enabled when the OAM is not modified mid-frame and is discarded at the end
		// allows priority to be determined just by picking the first matching entry instead of iterating the entire array
		version(assumeOAMImmutableDiscarded) {
			import std.algorithm.sorting : sort;
			sort!((a, b) => a.x < b.x)(oamSorted);
		}
		scanline = 0;
		this.pixels = pixels;
		this.stride = stride;
	}
	void drawFullFrame(ubyte[] pixels, size_t stride) @safe pure {
		beginDrawing(pixels, stride);
		foreach (i; 0 .. height) {
			runLine();
		}
	}
}

unittest {
	import std.algorithm.iteration : splitter;
	import std.conv : to;
	import std.file : exists, read, readText;
	import std.path : buildPath;
	import std.string : lineSplitter;
	enum width = 160;
	enum height = 144;
	static ubyte[] draw(ref PPU ppu) {
		auto buffer = new ushort[](width * height);
		enum pitch = width * 2;
		ppu.drawFullFrame(cast(ubyte[])buffer, pitch);
		auto result = new uint[](width * height);
		immutable colourMap = [
			0x0000: 0xFF000000,
			0x35AD: 0xFF6B6B6B,
			0x5AD6: 0xFFB5B5B5,
			0x7FFF: 0xFFFFFFFF,
		];
		foreach (i, ref pixel; result) { //RGB555 -> ARGB8888
			if (buffer[i] !in colourMap) {
				import std.logger; infof("%04X", buffer[i]);
			}
			pixel = colourMap[buffer[i]];
		}
		return cast(ubyte[])result;
	}
	static ubyte[] renderMesen2State(string filename) {
		PPU ppu;
		ppu.vram = new ubyte[](0x10000);
		auto file = cast(ubyte[])read(buildPath("testdata/gameboy", filename));
		LCDCValue lcdc;
		STATValue stat;
		loadMesen2SaveState(file, 1, (key, data) @safe pure {
			ubyte byteData() {
				assert(data.length == 1);
				return data[0];
			}
			ushort shortData() {
				assert(data.length == 2);
				return (cast(const(ushort)[])data)[0];
			}
			uint intData() {
				assert(data.length == 4);
				return (cast(const(uint)[])data)[0];
			}
			switch (key) {
				case "ppu.scrollY":
					ppu.registers.scy = byteData;
					break;
				case "ppu.scrollX":
					ppu.registers.scx = byteData;
					break;
				case "ppu.windowY":
					ppu.registers.wy = byteData;
					break;
				case "ppu.windowX":
					ppu.registers.wx = byteData;
					break;
				case "ppu.objPalette0":
					ppu.registers.obp0 = byteData;
					break;
				case "ppu.objPalette1":
					ppu.registers.obp1 = byteData;
					break;
				case "ppu.bgPalette":
					ppu.registers.bgp = byteData;
					break;
				case "ppu.ly":
					ppu.registers.ly = byteData;
					break;
				case "ppu.bgEnabled":
					lcdc.bgEnabled = byteData & 1;
					break;
				case "ppu.spritesEnabled":
					lcdc.spritesEnabled = byteData & 1;
					break;
				case "ppu.largeSprites":
					lcdc.largeSprites = byteData & 1;
					break;
				case "ppu.bgTilemapSelect":
					lcdc.bgScreenB = byteData & 1;
					break;
				case "ppu.windowEnabled":
					lcdc.windowEnabled = byteData & 1;
					break;
				case "ppu.windowTilemapSelect":
					lcdc.windowScreenB = byteData & 1;
					break;
				case "ppu.lcdEnabled":
					lcdc.lcdEnabled = byteData & 1;
					break;
				case "ppu.bgTileSelect":
					lcdc.bgTileblockA = byteData & 1;
					break;
				case "ppu.mode":
					stat.mode = intData & 3;
					break;
				case "ppu.lyCoincidenceFlag":
					stat.coincidence = byteData & 1;
					break;
				case "ppu.status":
					stat.mode0HBlankIRQ = !!(byteData & 0b00001000);
					stat.mode1VBlankIRQ = !!(byteData & 0b00010000);
					stat.mode2OAMIRQ = !!(byteData & 0b00100000);
					stat.lycEqualsLYFlag = !!(byteData & 0b01000000);
					break;
				case "videoRam":
					ppu.vram[0x8000 .. 0xA000] = data;
					break;
				case "spriteRam":
					ppu.oam[] = data;
					break;
				default:
					import std.logger; debug infof("%s (%s bytes)", key, data.length);
					break;
			}
		});
		ppu.registers.lcdc = lcdc.raw;
		ppu.registers.stat = stat.raw;
		return draw(ppu);
	}
	static void runTest(string name) {
		comparePNG(renderMesen2State(name~".mss"), "testdata/gameboy", name~".png", width, height);

	}
	runTest("everythingok");
}

immutable ushort[] pixelBitmasks = [
	0b0000000100000001,
	0b0000001000000010,
	0b0000010000000100,
	0b0000100000001000,
	0b0001000000010000,
	0b0010000000100000,
	0b0100000001000000,
	0b1000000010000000,
];
ushort rgb(ubyte r, ubyte g, ubyte b) @safe pure {
	return ((r & 0x1F) << 10) | ((g & 0x1F) << 5) | (b & 0x1F);
}
immutable ushort[] pocketPalette = [
	rgb(31, 31, 31),
	rgb(22, 22, 22),
	rgb(13, 13, 13),
	rgb(0, 0, 0)
];
immutable ushort[] ogPalette = [
	rgb(19, 23, 1),
	rgb(17, 21, 1),
	rgb(6, 12, 6),
	rgb(1, 7, 1)
];
ushort tileAddr(ushort num, bool alt) {
	return alt ? cast(ushort)(0x9000 + cast(byte)num) : cast(ushort)(0x8000 + num);
}

auto getPixel(ushort tile, int subX) @safe pure {
	const ushort mask = tile & pixelBitmasks[7 - (subX % 8)];
	const l1 = ((mask & 0xFF) >> (7 - (subX % 8)));
	const l2 = ((mask & 0xFF00) >> (7 + (7 - (subX % 8))));
	return l1 | l2;
}

@safe pure unittest {
	assert(getPixel(0x7E3C, 0) == 0);
	assert(getPixel(0x7E3C, 1) == 2);
	assert(getPixel(0x7E3C, 2) == 3);
	assert(getPixel(0x0A7E, 2) == 1);
}

bool inRange(T)(T value, T lower, T upper) {
	return (lower <= value) && (upper > value);
}
@safe pure unittest {
	assert(0.inRange(0, 1));
	assert(10.inRange(0, 11));
	assert(!10.inRange(0, 10));
	assert(!9.inRange(10, 11));
}

union LCDCValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			bool, "bgEnabled", 1,
			bool, "spritesEnabled", 1,
			bool, "largeSprites", 1,
			bool, "bgScreenB", 1,
			bool, "bgTileblockA", 1,
			bool, "windowEnabled", 1,
			bool, "windowScreenB", 1,
			bool, "lcdEnabled", 1,
		));
	}
}

union STATValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			uint, "mode", 2,
			bool, "coincidence", 1,
			bool, "mode0HBlankIRQ", 1,
			bool, "mode1VBlankIRQ", 1,
			bool, "mode2OAMIRQ", 1,
			bool, "lycEqualsLYFlag", 1,
			bool, "", 1,
		));
	}
}

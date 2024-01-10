module librehome.gameboy.ppu;

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
	enum width = 160;
	enum height = 144;
	Registers registers;
	ubyte[] vram;
	immutable(ushort)[] gbPalette = pocketPalette;

	private ubyte scanline;
	private ubyte[] pixels;
	private size_t stride;
	private OAMEntry[] oam;
	void runLine() @safe pure {
		const baseX = registers.scx;
		const baseY = registers.scy + scanline;
		auto pixelRow = cast(ushort[])(pixels[scanline * stride .. (scanline + 1) * stride]);
		const tilemapBase = ((baseY / 8) % 32) * 32;
		const tilemapRow = bgScreen[tilemapBase .. tilemapBase + 32];
		lineLoop: foreach (x; 0 .. width) {
			size_t highestMatchingSprite = size_t.max;
			int highestX = int.max;
			foreach (idx, sprite; oam) {
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
				const sprite = oam[highestMatchingSprite];
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
				const windowTilemapBase = ((registers.lcdc & LCDCFlags.windowTilemap) ? 0x9C00 : 0x9800) + (finalY / 8) * 32;
				const windowTilemapRow = vram[windowTilemapBase .. windowTilemapBase + 32];
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
	ubyte[] screenA() @safe pure {
		return vram[0x9800 .. 0x9C00];
	}
	ubyte[] screenB() @safe pure {
		return vram[0x9C00 .. 0xA000];
	}
	ushort getColour(int b) @safe pure {
		const paletteMap = (registers.bgp >> (b * 2)) & 0x3;
		return gbPalette[paletteMap];
	}
	ushort[8] getTile(short id, bool useLCDC) @safe pure {
		const useAlternate = useLCDC && !(registers.lcdc & LCDCFlags.useAltBG);
		ushort base = useAlternate ? cast(ushort)(0x9000 + (cast(byte)id) * 16) : cast(ushort)(0x8000 + id*16);
		return (cast(ushort[8][])(vram[base .. base + 16]))[0];
	}
	void beginDrawing(ubyte[] pixels, size_t stride) @safe pure {
		oam = cast(OAMEntry[])(vram[0xFE00 .. 0xFE00 + 40 * OAMEntry.sizeof]);
		// optimization that can be enabled when the OAM is not modified mid-frame and is discarded at the end
		// allows priority to be determined just by picking the first matching entry instead of iterating the entire array
		version(assumeOAMImmutableDiscarded) {
			import std.algorithm.sorting : sort;
			sort!((a, b) => a.x < b.x)(oam);
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
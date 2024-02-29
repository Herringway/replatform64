module librehome.nes.ppu;

import librehome.common;
import librehome.testhelpers;

import core.stdc.stdint;

immutable ubyte[4][2] nametableMirrorLookup = [
	[0, 0, 1, 1], // Vertical
	[0, 1, 0, 1], // Horizontal
];

/**
 * Default hardcoded palette.
 */
__gshared const uint32_t[64] defaultPaletteRGB = [
	0xFF666666,
	0xFF002A88,
	0xFF1412A7,
	0xFF3B00A4,
	0xFF5C007E,
	0xFF6E0040,
	0xFF6C0600,
	0xFF561D00,
	0xFF333500,
	0xFF0B4800,
	0xFF005200,
	0xFF004F08,
	0xFF00404D,
	0xFF000000,
	0xFF000000,
	0xFF000000,
	0xFFADADAD,
	0xFF155FD9,
	0xFF4240FF,
	0xFF7527FE,
	0xFFA01ACC,
	0xFFB71E7B,
	0xFFB53120,
	0xFF994E00,
	0xFF6B6D00,
	0xFF388700,
	0xFF0C9300,
	0xFF008F32,
	0xFF007C8D,
	0xFF000000,
	0xFF000000,
	0xFF000000,
	0xFFFFFEFF,
	0xFF64B0FF,
	0xFF9290FF,
	0xFFC676FF,
	0xFFF36AFF,
	0xFFFE6ECC,
	0xFFFE8170,
	0xFFEA9E22,
	0xFFBCBE00,
	0xFF88D800,
	0xFF5CE430,
	0xFF45E082,
	0xFF48CDDE,
	0xFF4F4F4F,
	0xFF000000,
	0xFF000000,
	0xFFFFFEFF,
	0xFFC0DFFF,
	0xFFD3D2FF,
	0xFFE8C8FF,
	0xFFFBC2FF,
	0xFFFEC4EA,
	0xFFFECCC5,
	0xFFF7D8A5,
	0xFFE4E594,
	0xFFCFEF96,
	0xFFBDF4AB,
	0xFFB3F3CC,
	0xFFB5EBF2,
	0xFFB8B8B8,
	0xFF000000,
	0xFF000000
];

struct OAMEntry {
	align(1):
	ubyte y;
	ubyte index;
	ubyte attributes;
	ubyte x;
}

enum MirrorType {
	horizontal,
	vertical,
	screenA,
	screenB,
	fourScreens,
}

immutable ushort[][] mirrorOffsets = [
	MirrorType.horizontal: [0x000, 0x000, 0x400, 0x400],
	MirrorType.vertical: [0x000, 0x400, 0x000, 0x400],
	MirrorType.screenA: [0x000, 0x000, 0x000, 0x000],
	MirrorType.screenB: [0x400, 0x400, 0x400, 0x400],
	MirrorType.fourScreens: [0x000, 0x400, 0x800, 0xC00],
];

uint getTilemapOffset(uint x, uint y, MirrorType mirrorMode) @safe pure {
	enum tilemapWidth = 32;
	enum tilemapHeight = 30;
	x %= tilemapWidth * 2;
	y %= tilemapHeight * 2;
	const tilemap = (x >= tilemapWidth) + (y >= tilemapHeight) * 2;
	// Determine the index of the tile to render
	return 0x2000 + mirrorOffsets[mirrorMode][tilemap] + (tilemapWidth * (y % tilemapHeight)) + (x % tilemapWidth);
}
@safe pure unittest {
	assert(getTilemapOffset(0, 0, MirrorType.fourScreens) == 0x2000);
	assert(getTilemapOffset(32, 0, MirrorType.vertical) == 0x2400);
	assert(getTilemapOffset(32, 0, MirrorType.horizontal) == 0x2000);
	assert(getTilemapOffset(32, 0, MirrorType.fourScreens) == 0x2400);
	assert(getTilemapOffset(0, 30, MirrorType.fourScreens) == 0x2800);
	assert(getTilemapOffset(32, 30, MirrorType.fourScreens) == 0x2C00);
	assert(getTilemapOffset(0, 29, MirrorType.fourScreens) == 0x23A0);
}

/**
 * Emulates the NES Picture Processing Unit.
 */
struct PPU {
	/// RGB representation of the NES palette.
	const(uint)[] paletteRGB = defaultPaletteRGB;
	ubyte[] nesCPUVRAM;
	private int registerCycle = 0;
	MirrorType mirrorMode;
	ubyte readRegister(ushort address) @safe pure {
		switch(address) {
			case 0x2002: // PPUSTATUS
				writeToggle = false;
				return (registerCycle++ % 2 == 0 ? 0xc0 : 0);
			case 0x2004: // OAMDATA
				return (cast(ubyte[])oam[])[oamAddress];
			case 0x2007: // PPUDATA
				return readDataRegister();
			default:
				break;
			}

		return 0;
	}

	ushort getSpriteBase(ubyte index) @safe pure {
		if (ppuCtrl & (1 << 5)) { //8x16 mode
			return (index & 0xFE) + (index & 1 ? 256 : 0);
		} else {
			return index + (ppuCtrl & (1 << 3) ? 256 : 0);
		}
	}
	void drawSprite(scope Array2D!uint buffer, uint i, bool background) @safe pure {
		// Read OAM for the sprite
		ubyte y = oam[i].y;
		ubyte index = oam[i].index;
		ubyte attributes = oam[i].attributes;
		ubyte x = oam[i].x;

		// Check if the sprite has the correct priority
		//
		if (background != (attributes & (1 << 5))) {
			return;
		}

		// Check if the sprite is visible
		if( y >= 0xef || x >= 0xf9 ) {
			return;
		}

		// Increment y by one since sprite data is delayed by one scanline
		//
		y++;

		// Determine the tile to use
		ushort tile = getSpriteBase(index);
		bool flipX = (attributes & (1 << 6)) != 0;
		bool flipY = (attributes & (1 << 7)) != 0;
		foreach (tileOffset; 0 .. 1 + !!(ppuCtrl & (1 << 5))) {
			// Copy pixels to the framebuffer
			for( int row = 0; row < 8; row++ ) {
				ubyte plane1 = readCHR((tile + tileOffset) * 16 + row);
				ubyte plane2 = readCHR((tile + tileOffset) * 16 + row + 8);

				for( int column = 0; column < 8; column++ ) {
					ubyte paletteIndex = (((plane1 & (1 << column)) ? 1 : 0) + ((plane2 & (1 << column)) ? 2 : 0));
					ubyte colorIndex = palette[0x10 + (attributes & 0x03) * 4 + paletteIndex];
					if( paletteIndex == 0 ) {
						// Skip transparent pixels
						continue;
					}
					uint32_t pixel = paletteRGB[colorIndex];

					int xOffset = 7 - column;
					if( flipX ) {
						xOffset = column;
					}
					int yOffset = row;
					if( flipY ) {
						yOffset = 7 - row;
					}

					int xPixel = cast(int)x + xOffset;
					int yPixel = cast(int)y + yOffset + (8 * tileOffset);
					if (xPixel < 0 || xPixel >= 256 || yPixel < 0 || yPixel >= 240) {
						continue;
					}

					if (i == 0 && index == 0xff && row == 5 && column > 3 && column < 6) {
						continue;
					}

					buffer[xPixel, yPixel] = pixel;
				}
			}
		}
	}

	uint getTilemapOffset(uint x, uint y) const @safe pure {
		return .getTilemapOffset(x, y, mirrorMode);
	}

	/**
	 * Render to a frame buffer.
	 */
	void render(uint[] target) @safe pure {
		auto buffer = Array2D!uint(256, 240, target);
		// Clear the buffer with the background color
		buffer[0 .. $, 0 .. $] = paletteRGB[palette[0]];

		// Draw sprites behind the backround
		if (ppuMask & (1 << 4)) { // Are sprites enabled?
			// Sprites with the lowest index in OAM take priority.
			// Therefore, render the array of sprites in reverse order.
			for (int i = 63; i >= 0; i--) {
				drawSprite(buffer, i, true);
			}
		}

		// Draw the background (nametable)
		if (ppuMask & (1 << 3)) { // Is the background enabled?
			int scrollX = cast(int)ppuScrollX + ((ppuCtrl & (1 << 0)) ? 256 : 0);
			int scrollY = cast(int)ppuScrollY + ((ppuCtrl & (1 << 0)) ? 256 : 0);
			int xMin = scrollX / 8;
			int xMax = (cast(int)scrollX + 256) / 8;
			int yMin = scrollY / 8;
			int yMax = (cast(int)scrollY + 240) / 8;
			for (int x = xMin; x <= xMax; x++) {
				for (int y = yMin; y < yMax; y++) {
					// Render the tile
					renderTile(buffer, getTilemapOffset(x, y), (x * 8) - scrollX, (y * 8) - scrollY);
				}
			}
		}

		// Draw sprites in front of the background
		if (ppuMask & (1 << 4)) {
			// Sprites with the lowest index in OAM take priority.
			// Therefore, render the array of sprites in reverse order.
			for (int i = 63; i >= 0; i--) {
				drawSprite(buffer, i, false);
			}
		}
	}

	void writeRegister(ushort address, ubyte value) @safe pure {
		switch(address) {
			case 0x2000: // PPUCTRL
				ppuCtrl = value;
				break;
			case 0x2001: // PPUMASK
				ppuMask = value;
				break;
			case 0x2003: // OAMADDR
				oamAddress = value;
				break;
			case 0x2004: // OAMDATA
				(cast(ubyte[])oam[])[oamAddress] = value;
				oamAddress++;
				break;
			case 0x2005: // PPUSCROLL
				if (!writeToggle) {
					ppuScrollX = value;
				} else {
					ppuScrollY = value;
				}
				writeToggle = !writeToggle;
				break;
			case 0x2006: // PPUADDR
				writeAddressRegister(value);
				break;
			case 0x2007: // PPUDATA
				writeDataRegister(value);
				break;
			default:
				break;
		}
	}

	private ubyte ppuCtrl; /**< $2000 */
	private ubyte ppuMask; /**< $2001 */
	private ubyte ppuStatus; /**< 2002 */
	private ubyte oamAddress; /**< $2003 */
	private ubyte ppuScrollX; /**< $2005 */
	private ubyte ppuScrollY; /**< $2005 */

	inout(ubyte)[] palette() inout @safe pure {
		return nesCPUVRAM[0x3F00 .. 0x3F20];
	}
	inout(ubyte)[] chr() inout @safe pure {
		return nesCPUVRAM[0x0000 .. 0x2000];
	}
	inout(ubyte)[] nametable() inout @safe pure {
		return nesCPUVRAM[0x2000 .. 0x3000];
	}
	OAMEntry[64] oam; // Sprite memory

	// PPU Address control
	private ushort currentAddress; /**< Address that will be accessed on the next PPU read/write. */
	private bool writeToggle; /**< Toggles whether the low or high bit of the current address will be set on the next write to PPUADDR. */
	private ubyte vramBuffer; /**< Stores the last read byte from VRAM to delay reads by 1 byte. */

	private ubyte getAttributeTableValue(ushort nametableAddress) @safe pure {
		nametableAddress = getNametableIndex(nametableAddress);

		// Determine the 32x32 attribute table address
		int row = ((nametableAddress & 0x3e0) >> 5) / 4;
		int col = (nametableAddress & 0x1f) / 4;

		// Determine the 16x16 metatile for the 8x8 tile addressed
		int shift = ((nametableAddress & (1 << 6)) ? 4 : 0) + ((nametableAddress & (1 << 1)) ? 2 : 0);

		// Determine the offset into the attribute table
		int offset = (nametableAddress & 0xc00) + 0x400 - 64 + (row * 8 + col);

		// Determine the attribute table value
		return (nametable[offset] & (0x3 << shift)) >> shift;
	}
	private ushort getNametableIndex(ushort address) @safe pure {
		address = cast(ushort)((address - 0x2000) % 0x1000);
		int table = address / 0x400;
		int offset = address % 0x400;
		int mode = 1;
		return cast(ushort)((nametableMirrorLookup[mode][table] * 0x400 + offset) % 2048);
	}
	private ubyte readByte(ushort address) @safe pure {
		// Mirror all addresses above $3fff
		address &= 0x3fff;

		if (address < 0x2000) {
			// CHR
			return nesCPUVRAM[address];
		}
		else if (address < 0x3f00) {
			// Nametable
			return nametable[getNametableIndex(address)];
		}

		return 0;
	}
	private ubyte readCHR(int index) @safe pure {
		if (index < 0x2000) {
			return nesCPUVRAM[index];
		} else {
			return 0;
		}
	}
	private ubyte readDataRegister() @safe pure {
		ubyte value = vramBuffer;
		vramBuffer = readByte(currentAddress);

		if (!(ppuCtrl & (1 << 2))) {
			currentAddress++;
		} else {
			currentAddress += 32;
		}

		return value;
	}
	private void renderTile(scope Array2D!uint buffer, int index, int xOffset, int yOffset) @safe pure {
		// Lookup the pattern table entry
		ushort tile = readByte(cast(ushort)index) + (ppuCtrl & (1 << 4) ? 256 : 0);
		ubyte attribute = getAttributeTableValue(cast(ushort)index);

		// Read the pixels of the tile
		for( int row = 0; row < 8; row++ ) {
			ubyte plane1 = readCHR(tile * 16 + row);
			ubyte plane2 = readCHR(tile * 16 + row + 8);

			for( int column = 0; column < 8; column++ ) {
				ubyte paletteIndex = (((plane1 & (1 << column)) ? 1 : 0) + ((plane2 & (1 << column)) ? 2 : 0));
				ubyte colorIndex = palette[attribute * 4 + paletteIndex];
				if( paletteIndex == 0 ) {
					// skip transparent pixels
					//colorIndex = palette[0];
					continue;
				}
				uint32_t pixel = paletteRGB[colorIndex];

				int x = (xOffset + (7 - column));
				int y = (yOffset + row);
				if (x < 0 || x >= 256 || y < 0 || y >= 240) {
					continue;
				}
				buffer[x, y] = pixel;
			}
		}

	}
	private void writeAddressRegister(ubyte value) @safe pure {
		if (!writeToggle) {
			// Upper byte
			currentAddress = (currentAddress & 0xff) | ((cast(ushort)value << 8) & 0xff00);
		} else {
			// Lower byte
			currentAddress = (currentAddress & 0xff00) | cast(ushort)value;
		}
		writeToggle = !writeToggle;
	}
	private void writeByte(ushort address, ubyte value) @safe pure {
		// Mirror all addrsses above $3fff
		address &= 0x3fff;

		if (address < 0x2000) {
			// CHR (no-op)
		} else if (address < 0x3f00) {
			nametable[getNametableIndex(address)] = value;
		} else if (address < 0x3f20) {
			// Palette data
			palette[address - 0x3f00] = value;

			// Mirroring
			if (address == 0x3f10 || address == 0x3f14 || address == 0x3f18 || address == 0x3f1c) {
				palette[address - 0x3f10] = value;
			}
		}
	}
	private void writeDataRegister(ubyte value) @safe pure {
		writeByte(currentAddress, value);
		if (!(ppuCtrl & (1 << 2))) {
			currentAddress++;
		} else {
			currentAddress += 32;
		}
	}
}

unittest {
	import std.algorithm.iteration : splitter;
	import std.conv : to;
	import std.file : exists, read, readText;
	import std.path : buildPath;
	import std.string : lineSplitter;
	enum width = 256;
	enum height = 240;
	static ubyte[] draw(ref PPU ppu) {
		auto buffer = new uint[](width * height);
		enum pitch = width * 2;
		ppu.render(buffer);
		foreach (i, ref pixel; buffer) {
			pixel = 0xFF000000 | ((pixel & 0xFF) << 16) | (pixel & 0xFF00) | ((pixel & 0xFF0000) >> 16);
		}
		return cast(ubyte[])buffer;
	}
	static ubyte[] renderMesen2State(string filename) {
		PPU ppu;
		auto file = cast(ubyte[])read(buildPath("testdata/nes", filename));
		ppu.nesCPUVRAM = new ubyte[](0x4000);
		ubyte PPUCTRL;
		ubyte PPUMASK;
		ubyte PPUSCROLL;
		ubyte PPUSCROLL2;
		loadMesen2SaveState(file, 2, (key, data) @safe pure {
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
				case "mapper.nametableRam":
					ppu.nametable[0 .. data.length] = data;
					break;
				case "mapper.chrRam":
					ppu.chr[] = data;
					break;
				case "ppu.paletteRam":
					ppu.palette[] = data;
					break;
				case "ppu.spriteRam":
					ppu.oam[] = cast(const(OAMEntry[]))data;
					break;
				case "ppu.control.verticalWrite":
					PPUCTRL |= !!byteData << 2;
					break;
				case "ppu.control.spritePatternAddr":
					PPUCTRL |= (shortData == 0) << 3;
					break;
				case "ppu.control.backgroundPatternAddr":
					PPUCTRL |= (shortData != 0) << 4;
					break;
				case "ppu.control.largeSprites":
					PPUCTRL |= (byteData != 0) << 5;
					break;
				case "ppu.control.nmiOnVerticalBlank":
					PPUCTRL |= (byteData != 0) << 7;
					break;
				case "ppu.mask.grayscale":
					PPUMASK |= byteData & 1;
					break;
				case "ppu.mask.backgroundMask":
					PPUMASK |= (byteData & 1) << 1;
					break;
				case "ppu.mask.spriteMask":
					PPUMASK |= (byteData & 1) << 2;
					break;
				case "ppu.mask.backgroundEnabled":
					PPUMASK |= (byteData & 1) << 3;
					break;
				case "ppu.mask.spritesEnabled":
					PPUMASK |= (byteData & 1) << 4;
					break;
				case "ppu.mask.intensifyRed":
					PPUMASK |= (byteData & 1) << 5;
					break;
				case "ppu.mask.intensifyGreen":
					PPUMASK |= (byteData & 1) << 6;
					break;
				case "ppu.mask.intensifyBlue":
					PPUMASK |= (byteData & 1) << 7;
					break;
				case "ppu.xScroll":
					PPUSCROLL = byteData;
					break;
				case "mapper.mirroringType":
					switch (intData) {
						case 0:
							ppu.mirrorMode = MirrorType.horizontal;
							break;
						case 1:
							ppu.mirrorMode = MirrorType.vertical;
							break;
						case 2:
							ppu.mirrorMode = MirrorType.screenA;
							break;
						case 3:
							ppu.mirrorMode = MirrorType.screenB;
							break;
						case 4:
							ppu.mirrorMode = MirrorType.fourScreens;
							break;
						default: assert(0, "Unexpected mirror type");
					}
					break;
				case "ppu.tmpVideoRamAddr":
					//mesen stores this in a strange way
					PPUSCROLL2 = ((shortData & 0x3E0) >> 2) | ((shortData & 0x7000) >> 12);
					break;
				default:
					break;
			}
		});
		ppu.writeRegister(0x2000, PPUCTRL);
		ppu.writeRegister(0x2001, PPUMASK);
		ppu.writeRegister(0x2005, PPUSCROLL);
		ppu.writeRegister(0x2005, PPUSCROLL2);
		return draw(ppu);
	}
	static void runTest(string name) {
		comparePNG(renderMesen2State(name~".mss"), "testdata/nes", name~".png", width, height);

	}
	runTest("cv");
	runTest("con2");
}

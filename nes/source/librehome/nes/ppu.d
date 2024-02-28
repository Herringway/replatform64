module librehome.nes.ppu;

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
	0x666666,
	0x002A88,
	0x1412A7,
	0x3B00A4,
	0x5C007E,
	0x6E0040,
	0x6C0600,
	0x561D00,
	0x333500,
	0x0B4800,
	0x005200,
	0x004F08,
	0x00404D,
	0x000000,
	0x000000,
	0x000000,
	0xADADAD,
	0x155FD9,
	0x4240FF,
	0x7527FE,
	0xA01ACC,
	0xB71E7B,
	0xB53120,
	0x994E00,
	0x6B6D00,
	0x388700,
	0x0C9300,
	0x008F32,
	0x007C8D,
	0x000000,
	0x000000,
	0x000000,
	0xFFFEFF,
	0x64B0FF,
	0x9290FF,
	0xC676FF,
	0xF36AFF,
	0xFE6ECC,
	0xFE8170,
	0xEA9E22,
	0xBCBE00,
	0x88D800,
	0x5CE430,
	0x45E082,
	0x48CDDE,
	0x4F4F4F,
	0x000000,
	0x000000,
	0xFFFEFF,
	0xC0DFFF,
	0xD3D2FF,
	0xE8C8FF,
	0xFBC2FF,
	0xFEC4EA,
	0xFECCC5,
	0xF7D8A5,
	0xE4E594,
	0xCFEF96,
	0xBDF4AB,
	0xB3F3CC,
	0xB5EBF2,
	0xB8B8B8,
	0x000000,
	0x000000
];


/**
 * Emulates the NES Picture Processing Unit.
 */
struct PPU {
	/// RGB representation of the NES palette.
	const(uint)[] paletteRGB = defaultPaletteRGB;
	ubyte[] nesCPUVRAM;
	private int registerCycle = 0;
	ubyte readRegister(ushort address) @safe pure {
		switch(address) {
			case 0x2002: // PPUSTATUS
				writeToggle = false;
				return (registerCycle++ % 2 == 0 ? 0xc0 : 0);
			case 0x2004: // OAMDATA
				return oam[oamAddress];
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
	void drawSprite(scope uint[] buffer, uint i, bool background) @safe pure {
		// Read OAM for the sprite
		ubyte y = oam[i * 4];
		ubyte index = oam[i * 4 + 1];
		ubyte attributes = oam[i * 4 + 2];
		ubyte x = oam[i * 4 + 3];

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
					uint32_t pixel = 0xff000000 | paletteRGB[colorIndex];

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

					buffer[yPixel * 256 + xPixel] = pixel;
				}
			}
		}
	}

	/**
	 * Render to a frame buffer.
	 */
	void render(uint[] buffer) @safe pure {
		// Clear the buffer with the background color
		for (int index = 0; index < 256 * 240; index++) {
			buffer[index] = paletteRGB[palette[0]];
		}

		// Draw sprites behind the backround
		if (ppuMask & (1 << 4)) { // Are sprites enabled?
			// Sprites with the lowest index in OAM take priority.
			// Therefore, render the array of sprites in reverse order.
			//
			for (int i = 63; i >= 0; i--) {
				drawSprite(buffer, i, true);
			}
		}

		// Draw the background (nametable)
		if (ppuMask & (1 << 3)) { // Is the background enabled?
			int scrollX = cast(int)ppuScrollX + ((ppuCtrl & (1 << 0)) ? 256 : 0);
			int xMin = scrollX / 8;
			int xMax = (cast(int)scrollX + 256) / 8;
			for (int x = 0; x < 32; x++) {
				for (int y = 0; y < 4; y++) {
					// Render the status bar in the same position (it doesn't scroll)
					renderTile(buffer, 0x2000 + 32 * y + x, x * 8, y * 8);
				}
			}
			for (int x = xMin; x <= xMax; x++) {
				for (int y = 4; y < 30; y++) {
					// Determine the index of the tile to render
					int index;
					if (x < 32) {
						index = 0x2000 + 32 * y + x;
					} else if (x < 64) {
						index = 0x2400 + 32 * y + (x - 32);
					} else {
						index = 0x2800 + 32 * y + (x - 64);
					}

					// Render the tile
					renderTile(buffer, index, (x * 8) - cast(int)scrollX, (y * 8));
				}
			}
		}

		// Draw sprites in front of the background
		if (ppuMask & (1 << 4)) {
			// Sprites with the lowest index in OAM take priority.
			// Therefore, render the array of sprites in reverse order.
			//
			// We render sprite 0 first as a special case (coin indicator).
			//
			for (int j = 64; j > 0; j--) {
				// Start at 0, then 63, 62, 61, ..., 1
				//
				int i = j % 64;
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
				oam[oamAddress] = value;
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

	private ubyte[32] palette; /**< Palette data. */
	private ubyte[2048] nametable; /**< Background table. */
	private ubyte[256] oam; /**< Sprite memory. */

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
	private void renderTile(scope uint[] buffer, int index, int xOffset, int yOffset) @safe pure {
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
				uint32_t pixel = 0xff000000 | paletteRGB[colorIndex];

				int x = (xOffset + (7 - column));
				int y = (yOffset + row);
				if (x < 0 || x >= 256 || y < 0 || y >= 240) {
					continue;
				}
				buffer[y * 256 + x] = pixel;
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
		ppu.nesCPUVRAM = new ubyte[](0x2000);
		ubyte PPUCTRL;
		ubyte PPUMASK;
		ubyte PPUSCROLL;
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
					ppu.nametable[] = data;
					break;
				case "mapper.chrRam":
					ppu.nesCPUVRAM[] = data;
					break;
				case "ppu.paletteRam":
					ppu.palette[] = data;
					break;
				case "ppu.spriteRam":
					ppu.oam[] = data;
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
				default:
					break;
			}
		});
		ppu.writeRegister(0x2000, PPUCTRL);
		ppu.writeRegister(0x2001, PPUMASK);
		ppu.writeRegister(0x2005, PPUSCROLL);
		return draw(ppu);
	}
	static void runTest(string name) {
		comparePNG(renderMesen2State(name~".mss"), "testdata/nes", name~".png", width, height);

	}
	runTest("cv");
}

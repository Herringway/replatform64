module replatform64.nes.ppu;

import replatform64.backend.common.interfaces;
import replatform64.dumping;
import replatform64.testhelpers;
import replatform64.ui;
import replatform64.util;

import core.stdc.stdint;
import std.algorithm.comparison;
import std.algorithm.iteration;
import std.bitmanip;
import std.format;
import std.range;

import tilemagic.colours;
import tilemagic.tiles;

immutable ubyte[4][2] nametableMirrorLookup = [
	[0, 0, 1, 1], // Vertical
	[0, 1, 0, 1], // Horizontal
];

/**
 * Default hardcoded palette.
 */
__gshared const PPU.ColourFormat[64] defaultPaletteRGB = [
	PPU.ColourFormat(blue: 102, green: 102, red: 102),
	PPU.ColourFormat(blue: 136, green: 42, red: 0),
	PPU.ColourFormat(blue: 167, green: 18, red: 20),
	PPU.ColourFormat(blue: 164, green: 0, red: 59),
	PPU.ColourFormat(blue: 126, green: 0, red: 92),
	PPU.ColourFormat(blue: 64, green: 0, red: 110),
	PPU.ColourFormat(blue: 0, green: 6, red: 108),
	PPU.ColourFormat(blue: 0, green: 29, red: 86),
	PPU.ColourFormat(blue: 0, green: 53, red: 51),
	PPU.ColourFormat(blue: 0, green: 72, red: 11),
	PPU.ColourFormat(blue: 0, green: 82, red: 0),
	PPU.ColourFormat(blue: 8, green: 79, red: 0),
	PPU.ColourFormat(blue: 77, green: 64, red: 0),
	PPU.ColourFormat(blue: 0, green: 0, red: 0),
	PPU.ColourFormat(blue: 0, green: 0, red: 0),
	PPU.ColourFormat(blue: 0, green: 0, red: 0),

	PPU.ColourFormat(blue: 173, green: 173, red: 173),
	PPU.ColourFormat(blue: 217, green: 95, red: 21),
	PPU.ColourFormat(blue: 255, green: 64, red: 66),
	PPU.ColourFormat(blue: 254, green: 39, red: 117),
	PPU.ColourFormat(blue: 204, green: 26, red: 160),
	PPU.ColourFormat(blue: 123, green: 30, red: 183),
	PPU.ColourFormat(blue: 32, green: 49, red: 181),
	PPU.ColourFormat(blue: 0, green: 78, red: 153),
	PPU.ColourFormat(blue: 0, green: 109, red: 107),
	PPU.ColourFormat(blue: 0, green: 135, red: 56),
	PPU.ColourFormat(blue: 0, green: 147, red: 12),
	PPU.ColourFormat(blue: 50, green: 143, red: 0),
	PPU.ColourFormat(blue: 141, green: 124, red: 0),
	PPU.ColourFormat(blue: 0, green: 0, red: 0),
	PPU.ColourFormat(blue: 0, green: 0, red: 0),
	PPU.ColourFormat(blue: 0, green: 0, red: 0),

	PPU.ColourFormat(blue: 255, green: 254, red: 255),
	PPU.ColourFormat(blue: 255, green: 176, red: 100),
	PPU.ColourFormat(blue: 255, green: 144, red: 146),
	PPU.ColourFormat(blue: 255, green: 118, red: 198),
	PPU.ColourFormat(blue: 255, green: 106, red: 243),
	PPU.ColourFormat(blue: 204, green: 110, red: 254),
	PPU.ColourFormat(blue: 112, green: 129, red: 254),
	PPU.ColourFormat(blue: 34, green: 158, red: 234),
	PPU.ColourFormat(blue: 0, green: 190, red: 188),
	PPU.ColourFormat(blue: 0, green: 216, red: 136),
	PPU.ColourFormat(blue: 48, green: 228, red: 92),
	PPU.ColourFormat(blue: 130, green: 224, red: 69),
	PPU.ColourFormat(blue: 222, green: 205, red: 72),
	PPU.ColourFormat(blue: 79, green: 79, red: 79),
	PPU.ColourFormat(blue: 0, green: 0, red: 0),
	PPU.ColourFormat(blue: 0, green: 0, red: 0),

	PPU.ColourFormat(blue: 255, green: 254, red: 255),
	PPU.ColourFormat(blue: 255, green: 223, red: 192),
	PPU.ColourFormat(blue: 255, green: 210, red: 211),
	PPU.ColourFormat(blue: 255, green: 200, red: 232),
	PPU.ColourFormat(blue: 255, green: 194, red: 251),
	PPU.ColourFormat(blue: 234, green: 196, red: 254),
	PPU.ColourFormat(blue: 197, green: 204, red: 254),
	PPU.ColourFormat(blue: 165, green: 216, red: 247),
	PPU.ColourFormat(blue: 148, green: 229, red: 228),
	PPU.ColourFormat(blue: 150, green: 239, red: 207),
	PPU.ColourFormat(blue: 171, green: 244, red: 189),
	PPU.ColourFormat(blue: 204, green: 243, red: 179),
	PPU.ColourFormat(blue: 242, green: 235, red: 181),
	PPU.ColourFormat(blue: 184, green: 184, red: 184),
	PPU.ColourFormat(blue: 0, green: 0, red: 0),
	PPU.ColourFormat(blue: 0, green: 0, red: 0)
];

struct OAMEntry {
	align(1):
	ubyte y;
	ubyte index;
	union {
		ubyte attributes;
		struct {
			mixin(bitfields!(
				ubyte, "palette", 2,
				ubyte, "", 3,
				ubyte, "priority", 1,
				bool, "flipHorizontal", 1,
				bool, "flipVertical", 1,
			));
		}
	}
	ubyte x;
	static OAMEntry offscreen() {
		return OAMEntry(ubyte(0), ubyte(255), ubyte(0), ubyte(0));
	}
	this(ubyte x, ubyte y, ubyte tileLower, ubyte flags) {
		this.x = x;
		this.y = y;
		this.index = tileLower;
		this.attributes = flags;
	}
	this(ubyte x, ubyte y, ubyte tile, bool hFlip = false, bool vFlip = false, ubyte palette = 0, ubyte priority = 0) {
		this.x = x;
		this.y = y;
		this.index = tile;
		this.palette = palette;
		this.priority = priority;
		this.flipHorizontal = hFlip;
		this.flipVertical = vFlip;
	}
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
	alias ColourFormat = ARGB8888;
	enum width = 256;
	enum height = 240;
	/// RGB representation of the NES palette.
	const(ColourFormat)[] paletteRGB = defaultPaletteRGB;
	ubyte[] chr;
	ubyte[] nametable;
	ubyte[32] palette;
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

	ushort getSpriteBase(ubyte index) const @safe pure {
		if (ppuCtrl & (1 << 5)) { //8x16 mode
			return (index & 0xFE) + (index & 1 ? 256 : 0);
		} else {
			return index + (ppuCtrl & (1 << 3) ? 256 : 0);
		}
	}
	void drawFullTileData(Array2D!ColourFormat buffer, size_t paletteIndex) @safe pure
		in (buffer.dimensions[0] % 8 == 0, "Buffer width must be a multiple of 8")
		in (buffer.dimensions[1] % 8 == 0, "Buffer height must be a multiple of 8")
		in (buffer.dimensions[0] * buffer.dimensions[1] <= 512 * 8 * 8, "Buffer too small")
	{
		foreach (tileID; 0 .. 512) {
			const tileX = (tileID % (buffer.dimensions[0] / 8));
			const tileY = (tileID / (buffer.dimensions[0] / 8));
			foreach (subPixelY; 0 .. 8) {
				const plane1 = readCHR(tileID * 16 + subPixelY);
				const plane2 = readCHR(tileID * 16 + subPixelY + 8);
				foreach (subPixelX; 0 .. 8) {
					const colourIndex = (((plane1 & (1 << (7 - subPixelX))) ? 1 : 0) + ((plane2 & (1 << (7 - subPixelX))) ? 2 : 0));
					buffer[tileX * 8 + subPixelX, tileY * 8 + subPixelY] = paletteRGB[palette[paletteIndex * 4 + colourIndex]];
				}
			}
		}
	}
	void drawSprite(scope Array2D!ColourFormat buffer, uint i, bool background, bool ignoreOAMCoords) const @safe pure {
		// Read OAM for the sprite
		ubyte y = ignoreOAMCoords ? 0xFF : oam[i].y;
		ubyte index = oam[i].index;
		ubyte attributes = oam[i].attributes;
		ubyte x = ignoreOAMCoords ? 0 : oam[i].x;

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
					auto pixel = paletteRGB[colorIndex];

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
	void render(Array2D!ColourFormat buffer) @safe pure {
		// Clear the buffer with the background color
		buffer[0 .. $, 0 .. $] = paletteRGB[palette[0]];

		// Draw sprites behind the backround
		if (ppuMask & (1 << 4)) { // Are sprites enabled?
			// Sprites with the lowest index in OAM take priority.
			// Therefore, render the array of sprites in reverse order.
			for (int i = 63; i >= 0; i--) {
				drawSprite(buffer, i, true, false);
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
				drawSprite(buffer, i, false, false);
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
			return chr[address];
		}
		else if (address < 0x3f00) {
			// Nametable
			return nametable[getNametableIndex(address)];
		}

		return 0;
	}
	private ubyte readCHR(int index) const @safe pure {
		if (index < 0x2000) {
			return chr[index];
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
	private void renderTile(scope Array2D!ColourFormat buffer, int index, int xOffset, int yOffset) @safe pure {
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
				auto pixel = paletteRGB[colorIndex];

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
			chr[address] = value;
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
	void debugUI(const UIState state, VideoBackend video) {
		static ColourFormat[width * height] buffer;
		if (ImGui.BeginTabBar("renderer")) {
			if (ImGui.BeginTabItem("Registers")) {
				if (ImGui.TreeNode("PPUCTRL", "PPUCTRL: %02X", ppuCtrl)) {
					registerBitSel!2("Base nametable address", ppuCtrl, 0, ["$2000", "$2400", "$2800", "$2C00"]);
					ImGui.SetItemTooltip("Base address of the nametable currently rendered");
					registerBitSel!1("PPUDATA auto-increment", ppuCtrl, 2, ["1", "32"]);
					ImGui.SetItemTooltip("Add 32 to the address with every PPUDATA read/write. 1 otherwise.");
					registerBitSel!1("Sprite pattern table", ppuCtrl, 3, ["$0000", "$1000"]);
					ImGui.SetItemTooltip("Which bank of tile data to use for sprites");
					registerBitSel!1("BG pattern table", ppuCtrl, 4, ["$0000", "$1000"]);
					ImGui.SetItemTooltip("Which bank of tile data to use for the background");
					registerBit("Tall sprites", ppuCtrl, 5);
					ImGui.SetItemTooltip("If enabled, uses 8x16 sprites instead of 8x8.");
					registerBitSel!1("Primary/Secondary select", ppuCtrl, 6, ["Primary", "Secondary"]);
					ImGui.SetItemTooltip("Selects whether the NES's internal PPU renders the backdrop.");
					registerBit("VBlank enabled", ppuCtrl, 7);
					ImGui.SetItemTooltip("Controls whether or not VBlank interrupts are generated.");
					ImGui.TreePop();
				}
				if (ImGui.TreeNode("PPUMASK", "PPUMASK: %02X", ppuMask)) {
					registerBit("Grayscale", ppuMask, 0);
					ImGui.SetItemTooltip("Render in grayscale instead of colour.");
					registerBit("Render leftmost BG", ppuMask, 1);
					ImGui.SetItemTooltip("Whether or not to render the leftmost 8 pixels of the BG layer.");
					registerBit("Render leftmost sprites", ppuMask, 2);
					ImGui.SetItemTooltip("Whether or not to render the leftmost 8 pixels of the sprite layer.");
					registerBit("Show BG", ppuMask, 3);
					ImGui.SetItemTooltip("Whether or not to render the BG layer.");
					registerBit("Show sprites", ppuMask, 4);
					ImGui.SetItemTooltip("Whether or not to render the sprite layer.");
					registerBit("Emphasize red", ppuMask, 5);
					ImGui.SetItemTooltip("Darkens green and blue colour channels.");
					registerBit("Emphasize green", ppuMask, 6);
					ImGui.SetItemTooltip("Darkens red and blue colour channels.");
					registerBit("Emphasize blue", ppuMask, 7);
					ImGui.SetItemTooltip("Darkens red and green colour channels.");
					ImGui.TreePop();
				}
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Palettes")) {
				foreach (idx, ref palette; this.palette[].chunks(4).enumerate) {
					ImGui.SeparatorText(format!"Palette %d"(idx));
					foreach (i, ref colour; palette) {
						ImGui.PushID(cast(int)i);
						const c = ImVec4(defaultPaletteRGB[colour].red / 255.0, defaultPaletteRGB[colour].green / 255.0, defaultPaletteRGB[colour].blue / 255.0, 1.0);
						ImGui.Text("$%02X", colour);
						ImGui.SameLine();
						if (ImGui.ColorButton("##colour", c, ImGuiColorEditFlags.None, ImVec2(40, 40))) {
							// TODO: colour picker
						}
						if (i + 1 < palette.length) {
							ImGui.SameLine();
						}
						ImGui.PopID();
					}
				}
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Tiles")) {
				static void* surface;
				drawZoomableTiles(cast(Linear2BPP[])chr, cast(ColourFormat[4][])(palette[].map!(x => paletteRGB[x]).array), video, surface);
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("OAM")) {
				static void*[64] spriteSurfaces;
				const sprHeight = 8 * (1 + !!(ppuCtrl & (1 << 5)));
				enum sprWidth = 8;
				if (ImGui.BeginTable("oamTable", 8)) {
					foreach (idx, sprite; cast(OAMEntry[])oam) {
						ImGui.TableNextColumn();
						if (spriteSurfaces[idx] is null) {
							spriteSurfaces[idx] = video.createSurface(sprWidth, sprHeight, ushort.sizeof * sprWidth, PixelFormatOf!ColourFormat);
						}
						auto sprBuffer = Array2D!ColourFormat(sprWidth, sprHeight, buffer[0 .. sprWidth * sprHeight]);
						drawSprite(sprBuffer, cast(uint)idx, false, true);
						video.setSurfacePixels(spriteSurfaces[idx], cast(ubyte[])sprBuffer[]);
						ImGui.Image(spriteSurfaces[idx], ImVec2(sprWidth * 4.0, sprHeight * 4.0));
						if (ImGui.BeginItemTooltip()) {
							ImGui.Text("Coordinates: %d, %d", sprite.x, sprite.y);
							ImGui.Text("Tile: %d", sprite.index);
							ImGui.Text("Orientation: ");
							ImGui.SameLine();
							ImGui.Text(["Normal", "Flipped horizontally", "Flipped vertically", "Flipped horizontally, vertically"][(sprite.flipVertical << 1) + sprite.flipHorizontal]);
							ImGui.Text("Priority: ");
							ImGui.SameLine();
							ImGui.Text(["Normal", "High"][sprite.priority]);
							ImGui.Text("Palette: %d", sprite.palette);
							ImGui.EndTooltip();
						}
					}
					ImGui.EndTable();
				}
				ImGui.EndTabItem();
			}
			ImGui.EndTabBar();
		}
	}
}

unittest {
	import std.algorithm.iteration : splitter;
	import std.conv : to;
	import std.file : exists, mkdirRecurse, read, readText;
	import std.format : format;
	import std.path : buildPath;
	import std.string : lineSplitter;
	enum width = 256;
	enum height = 240;
	static Array2D!(PPU.ColourFormat) draw(ref PPU ppu) {
		auto buffer = Array2D!(PPU.ColourFormat)(width, height);
		ppu.render(buffer);
		return buffer;
	}
	static Array2D!(PPU.ColourFormat) renderMesen2State(string filename) {
		PPU ppu;
		auto file = cast(ubyte[])read(buildPath("testdata/nes", filename));
		ppu.chr = new ubyte[](0x2000);
		ppu.nametable = new ubyte[](0x1000);
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
		const frame = renderMesen2State(name~".mss");
		if (const result = comparePNG(frame, "testdata/nes", name~".png")) {
			mkdirRecurse("failed");
			dumpPNG(frame, "failed/"~name~".png");
			assert(0, format!"Pixel mismatch at %s, %s in %s (got %s, expecting %s)"(result.x, result.y, name, result.got, result.expected));
		}
	}
	runTest("cv");
	runTest("con2");
}

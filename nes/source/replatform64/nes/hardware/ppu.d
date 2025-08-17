module replatform64.nes.hardware.ppu;

import replatform64.dumping;
import replatform64.nes.hardware;
import replatform64.testhelpers;
import replatform64.ui;
import replatform64.util;

import core.stdc.stdint;
import std.algorithm.comparison;
import std.algorithm.iteration;
import std.bitmanip;
import std.format;
import std.range;

import pixelmancy.colours;
import pixelmancy.tiles;

immutable ubyte[4][2] nametableMirrorLookup = [
	[0, 0, 1, 1], // Vertical
	[0, 1, 0, 1], // Horizontal
];

/**
 * Default hardcoded palette.
 */
__gshared const PPU.ColourFormat[64] defaultPaletteRGB = [
	PPU.ColourFormat(blue: 102, green: 102, red: 102, alpha: 255),
	PPU.ColourFormat(blue: 136, green: 42, red: 0, alpha: 255),
	PPU.ColourFormat(blue: 167, green: 18, red: 20, alpha: 255),
	PPU.ColourFormat(blue: 164, green: 0, red: 59, alpha: 255),
	PPU.ColourFormat(blue: 126, green: 0, red: 92, alpha: 255),
	PPU.ColourFormat(blue: 64, green: 0, red: 110, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 6, red: 108, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 29, red: 86, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 53, red: 51, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 72, red: 11, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 82, red: 0, alpha: 255),
	PPU.ColourFormat(blue: 8, green: 79, red: 0, alpha: 255),
	PPU.ColourFormat(blue: 77, green: 64, red: 0, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 0, red: 0, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 0, red: 0, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 0, red: 0, alpha: 255),

	PPU.ColourFormat(blue: 173, green: 173, red: 173, alpha: 255),
	PPU.ColourFormat(blue: 217, green: 95, red: 21, alpha: 255),
	PPU.ColourFormat(blue: 255, green: 64, red: 66, alpha: 255),
	PPU.ColourFormat(blue: 254, green: 39, red: 117, alpha: 255),
	PPU.ColourFormat(blue: 204, green: 26, red: 160, alpha: 255),
	PPU.ColourFormat(blue: 123, green: 30, red: 183, alpha: 255),
	PPU.ColourFormat(blue: 32, green: 49, red: 181, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 78, red: 153, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 109, red: 107, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 135, red: 56, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 147, red: 12, alpha: 255),
	PPU.ColourFormat(blue: 50, green: 143, red: 0, alpha: 255),
	PPU.ColourFormat(blue: 141, green: 124, red: 0, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 0, red: 0, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 0, red: 0, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 0, red: 0, alpha: 255),

	PPU.ColourFormat(blue: 255, green: 254, red: 255, alpha: 255),
	PPU.ColourFormat(blue: 255, green: 176, red: 100, alpha: 255),
	PPU.ColourFormat(blue: 255, green: 144, red: 146, alpha: 255),
	PPU.ColourFormat(blue: 255, green: 118, red: 198, alpha: 255),
	PPU.ColourFormat(blue: 255, green: 106, red: 243, alpha: 255),
	PPU.ColourFormat(blue: 204, green: 110, red: 254, alpha: 255),
	PPU.ColourFormat(blue: 112, green: 129, red: 254, alpha: 255),
	PPU.ColourFormat(blue: 34, green: 158, red: 234, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 190, red: 188, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 216, red: 136, alpha: 255),
	PPU.ColourFormat(blue: 48, green: 228, red: 92, alpha: 255),
	PPU.ColourFormat(blue: 130, green: 224, red: 69, alpha: 255),
	PPU.ColourFormat(blue: 222, green: 205, red: 72, alpha: 255),
	PPU.ColourFormat(blue: 79, green: 79, red: 79, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 0, red: 0, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 0, red: 0, alpha: 255),

	PPU.ColourFormat(blue: 255, green: 254, red: 255, alpha: 255),
	PPU.ColourFormat(blue: 255, green: 223, red: 192, alpha: 255),
	PPU.ColourFormat(blue: 255, green: 210, red: 211, alpha: 255),
	PPU.ColourFormat(blue: 255, green: 200, red: 232, alpha: 255),
	PPU.ColourFormat(blue: 255, green: 194, red: 251, alpha: 255),
	PPU.ColourFormat(blue: 234, green: 196, red: 254, alpha: 255),
	PPU.ColourFormat(blue: 197, green: 204, red: 254, alpha: 255),
	PPU.ColourFormat(blue: 165, green: 216, red: 247, alpha: 255),
	PPU.ColourFormat(blue: 148, green: 229, red: 228, alpha: 255),
	PPU.ColourFormat(blue: 150, green: 239, red: 207, alpha: 255),
	PPU.ColourFormat(blue: 171, green: 244, red: 189, alpha: 255),
	PPU.ColourFormat(blue: 204, green: 243, red: 179, alpha: 255),
	PPU.ColourFormat(blue: 242, green: 235, red: 181, alpha: 255),
	PPU.ColourFormat(blue: 184, green: 184, red: 184, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 0, red: 0, alpha: 255),
	PPU.ColourFormat(blue: 0, green: 0, red: 0, alpha: 255)
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
	static OAMEntry offscreen() @safe pure {
		return OAMEntry(ubyte(0), ubyte(255), ubyte(0), ubyte(0));
	}
	this(ubyte x, ubyte y, ubyte tileLower, ubyte flags) @safe pure {
		this.x = x;
		this.y = y;
		this.index = tileLower;
		this.attributes = flags;
	}
	this(ubyte x, ubyte y, ubyte tile, bool hFlip = false, bool vFlip = false, ubyte palette = 0, ubyte priority = 0) @safe pure {
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
		if (ppuCtrl.tallSprites) { //8x16 mode
			return (index & 0xFE) + (index & 1 ? 256 : 0);
		} else {
			return index + (ppuCtrl.spritePatternTable ? 256 : 0);
		}
	}
	void drawSprite(scope Array2D!ColourFormat buffer, uint i, bool background, bool ignoreOAM) const @safe pure {
		// Read OAM for the sprite
		const oamEntry = oam[i];
		// Increment y by one since sprite data is delayed by one scanline
		const baseY = ignoreOAM ? 0 : (oamEntry.y + 1);
		const baseX = ignoreOAM ? 0 : oamEntry.x;
		// Check if the sprite has the correct priority
		if (!ignoreOAM && (background != oamEntry.priority)) {
			return;
		}
		// Check if the sprite is visible
		if(!ignoreOAM && (baseY >= height - 1)) {
			return;
		}

		// Determine the tile to use
		const tile = getSpriteBase(oamEntry.index);
		const chr = cast(const(Linear2BPP)[])this.chr[];
		foreach (tileOffset; 0 .. 1 + ppuCtrl.tallSprites) {
			// Copy pixels to the framebuffer
			const thisTile = chr[tile + tileOffset];
			foreach (row; 0 .. 8) {
				foreach (column; 0 .. 8) {
					const tileX = autoFlip(column, !oamEntry.flipHorizontal);
					const tileY = autoFlip(row, oamEntry.flipVertical);
					const paletteIndex = thisTile[7 - column, row];
					if (paletteIndex == 0) {
						// Skip transparent pixels
						continue;
					}
					auto pixel = paletteRGB[palette[0x10 + oamEntry.palette * 4 + paletteIndex]];

					const xPixel = baseX + tileX;
					const yPixel = baseY + tileY + (8 * tileOffset);
					if (!xPixel.inRange(0, width) || !yPixel.inRange(0, height)) {
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
		if (ppuMask.enableSprites) { // Are sprites enabled?
			// Sprites with the lowest index in OAM take priority.
			// Therefore, render the array of sprites in reverse order.
			for (int i = 63; i >= 0; i--) {
				drawSprite(buffer, i, true, false);
			}
		}

		// Draw the background (nametable)
		if (ppuMask.enableBG) { // Is the background enabled?
			const scrollX = ppuScrollX + (ppuCtrl.nametableX * width);
			const scrollY = ppuScrollY + (ppuCtrl.nametableY * height);
			const xMin = scrollX / 8;
			const yMin = scrollY / 8;
			foreach (x; xMin .. xMin + width / 8) {
				foreach (y; yMin .. yMin + height / 8) {
					// Render the tile
					renderTile(buffer, getTilemapOffset(x, y), (x * 8) - scrollX, (y * 8) - scrollY);
				}
			}
		}

		// Draw sprites in front of the background
		if (ppuMask.enableSprites) {
			// Sprites with the lowest index in OAM take priority.
			// Therefore, render the array of sprites in reverse order.
			foreach_reverse (i; 0 .. 63) {
				drawSprite(buffer, i, false, false);
			}
		}
	}

	void writeRegister(ushort address, ubyte value) @safe pure {
		switch(address) {
			case 0x2000: // PPUCTRL
				ppuCtrl.raw = value;
				break;
			case 0x2001: // PPUMASK
				ppuMask.raw = value;
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

	private PPUCTRLValue ppuCtrl; /**< $2000 */
	private PPUMASKValue ppuMask; /**< $2001 */
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

		if (ppuCtrl.ppuDataIncreaseByRow) {
			currentAddress += 32;
		} else {
			currentAddress++;
		}

		return value;
	}
	private void renderTile(scope Array2D!ColourFormat buffer, int index, int xOffset, int yOffset) @safe pure {
		// Lookup the pattern table entry
		ushort tile = readByte(cast(ushort)index) + (ppuCtrl.bgPatternTable << 8);
		ubyte attribute = getAttributeTableValue(cast(ushort)index);

		// Read the pixels of the tile
		for (int row = 0; row < 8; row++) {
			ubyte plane1 = readCHR(tile * 16 + row);
			ubyte plane2 = readCHR(tile * 16 + row + 8);

			for (int column = 0; column < 8; column++) {
				ubyte paletteIndex = (((plane1 & (1 << column)) ? 1 : 0) + ((plane2 & (1 << column)) ? 2 : 0));
				ubyte colorIndex = palette[attribute * 4 + paletteIndex];
				if (paletteIndex == 0) {
					// skip transparent pixels
					continue;
				}
				auto pixel = paletteRGB[colorIndex];

				int x = (xOffset + (7 - column));
				int y = (yOffset + row);
				if (!x.inRange(0, width) || !y.inRange(0, height)) {
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
		if (ppuCtrl.ppuDataIncreaseByRow) {
			currentAddress += 32;
		} else {
			currentAddress++;
		}
	}
	void debugUI(UIState state) {
		static ColourFormat[width * height] buffer;
		if (ImGui.BeginTabBar("renderer")) {
			if (ImGui.BeginTabItem("Registers")) {
				if (ImGui.TreeNode("PPUCTRL", "PPUCTRL: %02X", ppuCtrl.raw)) {
					registerBitSel!2("Base nametable address", ppuCtrl.raw, 0, ["$2000", "$2400", "$2800", "$2C00"]);
					ImGui.SetItemTooltip("Base address of the nametable currently rendered");
					registerBitSel!1("PPUDATA auto-increment", ppuCtrl.raw, 2, ["1", "32"]);
					ImGui.SetItemTooltip("Add 32 to the address with every PPUDATA read/write. 1 otherwise.");
					registerBitSel!1("Sprite pattern table", ppuCtrl.raw, 3, ["$0000", "$1000"]);
					ImGui.SetItemTooltip("Which bank of tile data to use for sprites");
					registerBitSel!1("BG pattern table", ppuCtrl.raw, 4, ["$0000", "$1000"]);
					ImGui.SetItemTooltip("Which bank of tile data to use for the background");
					registerBit("Tall sprites", ppuCtrl.raw, 5);
					ImGui.SetItemTooltip("If enabled, uses 8x16 sprites instead of 8x8.");
					registerBitSel!1("Primary/Secondary select", ppuCtrl.raw, 6, ["Primary", "Secondary"]);
					ImGui.SetItemTooltip("Selects whether the NES's internal PPU renders the backdrop.");
					registerBit("VBlank enabled", ppuCtrl.raw, 7);
					ImGui.SetItemTooltip("Controls whether or not VBlank interrupts are generated.");
					ImGui.TreePop();
				}
				if (ImGui.TreeNode("PPUMASK", "PPUMASK: %02X", ppuMask.raw)) {
					registerBit("Grayscale", ppuMask.raw, 0);
					ImGui.SetItemTooltip("Render in grayscale instead of colour.");
					registerBit("Render leftmost BG", ppuMask.raw, 1);
					ImGui.SetItemTooltip("Whether or not to render the leftmost 8 pixels of the BG layer.");
					registerBit("Render leftmost sprites", ppuMask.raw, 2);
					ImGui.SetItemTooltip("Whether or not to render the leftmost 8 pixels of the sprite layer.");
					registerBit("Show BG", ppuMask.raw, 3);
					ImGui.SetItemTooltip("Whether or not to render the BG layer.");
					registerBit("Show sprites", ppuMask.raw, 4);
					ImGui.SetItemTooltip("Whether or not to render the sprite layer.");
					registerBit("Emphasize red", ppuMask.raw, 5);
					ImGui.SetItemTooltip("Darkens green and blue colour channels.");
					registerBit("Emphasize green", ppuMask.raw, 6);
					ImGui.SetItemTooltip("Darkens red and blue colour channels.");
					registerBit("Emphasize blue", ppuMask.raw, 7);
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
				drawZoomableTiles(cast(Linear2BPP[])chr, cast(ColourFormat[4][])(palette[].map!(x => paletteRGB[x]).array), state, surface);
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("OAM")) {
				drawSprites!ColourFormat(oam.length, state, 8, 16, (canvas, index) {
					drawSprite(canvas, cast(uint)index, false, true);
				}, (index) {
					const sprite = oam[index];
					ImGui.Text("Coordinates: %d, %d", sprite.x, sprite.y);
					ImGui.Text("Tile: %d", sprite.index);
					ImGui.Text("Orientation: ");
					ImGui.SameLine();
					ImGui.Text(["Normal", "Flipped horizontally", "Flipped vertically", "Flipped horizontally, vertically"][(sprite.flipVertical << 1) + sprite.flipHorizontal]);
					ImGui.Text("Priority: ");
					ImGui.SameLine();
					ImGui.Text(["Normal", "High"][sprite.priority]);
					ImGui.Text("Palette: %d", sprite.palette);
				});
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
	static Array2D!(PPU.ColourFormat) draw(ref PPU ppu) {
		auto buffer = Array2D!(PPU.ColourFormat)(ppu.width, ppu.height);
		ppu.render(buffer);
		return buffer;
	}
	static Array2D!(PPU.ColourFormat) renderMesen2State(const(ubyte)[] file, FauxDMA[] dma) {
		PPU ppu;
		ppu.chr = new ubyte[](0x2000);
		ppu.nametable = new ubyte[](0x1000);
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
					ppu.ppuCtrl.ppuDataIncreaseByRow = !!byteData;
					break;
				case "ppu.control.spritePatternAddr":
					ppu.ppuCtrl.spritePatternTable = !!shortData;
					break;
				case "ppu.control.backgroundPatternAddr":
					ppu.ppuCtrl.bgPatternTable = !!shortData;
					break;
				case "ppu.control.largeSprites":
					ppu.ppuCtrl.tallSprites = !!byteData;
					break;
				case "ppu.control.nmiOnVerticalBlank":
					ppu.ppuCtrl.vblankNMI = !!byteData;
					break;
				case "ppu.mask.grayscale":
					ppu.ppuMask.grayscale = !!byteData;
					break;
				case "ppu.mask.backgroundMask":
					ppu.ppuMask.showBGLeft8 = !!byteData;
					break;
				case "ppu.mask.spriteMask":
					ppu.ppuMask.showSpritesLeft8 = !!byteData;
					break;
				case "ppu.mask.backgroundEnabled":
					ppu.ppuMask.enableBG = !!byteData;
					break;
				case "ppu.mask.spritesEnabled":
					ppu.ppuMask.enableSprites = !!byteData;
					break;
				case "ppu.mask.intensifyRed":
					ppu.ppuMask.emphasizeRed = !!byteData;
					break;
				case "ppu.mask.intensifyGreen":
					ppu.ppuMask.emphasizeGreen = !!byteData;
					break;
				case "ppu.mask.intensifyBlue":
					ppu.ppuMask.emphasizeBlue = !!byteData;
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
				case "ppu.videoRamAddr":
					const nameTable = (shortData >> 10) & 3;
					ppu.ppuCtrl.nametableX = !!(nameTable & 1);
					ppu.ppuCtrl.nametableY = !!(nameTable >> 1);
					break;
				default:
					break;
			}
		});
		ppu.writeRegister(0x2005, PPUSCROLL);
		ppu.writeRegister(0x2005, PPUSCROLL2);
		return draw(ppu);
	}
	assert(runTests!renderMesen2State("nes", ""), "Tests failed");
}

// make sure writing via PPUADDR/PPUDATA works
@safe pure unittest {
	import std.algorithm.comparison : equal;
	with (PPU()) {
		nametable = new ubyte[](0x2000);
		writeRegister(Register.PPUADDR, 0x20);
		writeRegister(Register.PPUADDR, 0x00);
		foreach (_; 0 .. 0x200) {
			writeRegister(Register.PPUDATA, 0x42);
			writeRegister(Register.PPUDATA, 0x24);
		}
		assert(nametable[0 .. 0x400].equal((cast(ubyte[])[0x42, 0x24]).repeat(0x200).joiner));
	}
}

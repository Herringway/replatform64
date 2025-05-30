module replatform64.gameboy.hardware.ppu;

import replatform64.gameboy.hardware.registers;

import replatform64.dumping;
import replatform64.testhelpers;
import replatform64.ui;
import replatform64.util;

import std.algorithm.comparison;
import std.algorithm.iteration;
import std.bitmanip : bitfields;
import std.format;
import std.range;

import pixelmancy.colours;
import pixelmancy.tiles.bpp2;

union VRAM {
	ubyte[0x4000] raw;
	struct {
		Intertwined2BPP[0x80] tileBlockA;
		Intertwined2BPP[0x80] tileBlockB;
		Intertwined2BPP[0x80] tileBlockC;
		ubyte[0x0400] screenA;
		ubyte[0x0400] screenB;
		Intertwined2BPP[0x80] tileBlockACGB;
		Intertwined2BPP[0x80] tileBlockBCGB;
		Intertwined2BPP[0x80] tileBlockCCGB;
		CGBBGAttributeValue[0x0400] screenACGB;
		CGBBGAttributeValue[0x0400] screenBCGB;
	}
}
static assert(VRAM.sizeof == 0x4000);

struct PPU {
	alias ColourFormat = BGR555;
	static struct Registers {
		STATValue stat;
		LCDCValue lcdc;
		ubyte scy;
		ubyte scx;
		ubyte ly;
		ubyte lyc;
		ubyte bgp;
		ubyte obp0;
		ubyte obp1;
		ubyte wy;
		ubyte wx;
		ubyte bcps;
		ubyte ocps;
		ubyte vbk;
	}
	enum fullTileWidth = 32;
	enum fullTileHeight = 32;
	enum width = 160;
	enum height = 144;
	bool cgbMode;
	Registers registers;
	VRAM vram;
	OAMEntry[40] _oam;
	ColourFormat[4][16] paletteRAM = pocketPaletteCGB;
	const(ColourFormat)[4][] gbPalette = pocketPaletteCGB;

	private Array2D!ColourFormat pixels;
	private OAMEntry[] oamSorted;
	void runLine() @safe pure {
		const sprHeight = 8 * (1 + registers.lcdc.tallSprites);
		const baseX = registers.scx;
		const baseY = registers.scy + registers.ly;
		const baseWindowY = registers.ly - registers.wy;
		auto pixelRow = pixels[0 .. $, registers.ly];
		// get this row of tiles for the background and window
		const tilemapBase = ((baseY / 8) % fullTileWidth) * fullTileWidth;
		const tilemapRow = bgScreen[tilemapBase .. tilemapBase + fullTileWidth];
		const tilemapRowAttributes = bgScreenCGB[tilemapBase .. tilemapBase + fullTileWidth];
		const windowTilemapBase = (max(0, baseWindowY) / 8) * fullTileWidth;
		const windowTilemapRow = windowScreen[windowTilemapBase .. windowTilemapBase + fullTileWidth];
		const windowTilemapRowAttributes = windowScreenCGB[windowTilemapBase .. windowTilemapBase + fullTileWidth];
		// draw pixels from left to right
		foreach (x; 0 .. width) {
			size_t highestMatchingSprite = size_t.max;
			int highestX = int.max;
			// first, find a sprite at these coords with a non-transparent pixel
			foreach (idx, sprite; oamSorted) {
				if (registers.ly.inRange(sprite.y - 16, sprite.y - (registers.lcdc.tallSprites ? 0 : 8)) && x.inRange(sprite.x - 8, sprite.x)) {
					const xpos = autoFlip(x - (sprite.x - 8), sprite.flags.xFlip);
					const ypos = autoFlip((registers.ly - (sprite.y - 16)), sprite.flags.yFlip, sprHeight);
					// ignore transparent pixels
					if (getTile(cast(short)(sprite.tile + ypos / 8), false, cgbMode && sprite.flags.bank)[xpos, ypos % 8] == 0) {
						continue;
					}
					// in non-CGB mode, the sprite with the lowest X coordinate takes priority
					if (sprite.x - 8 < highestX) {
						highestX = sprite.x - 8;
						highestMatchingSprite = idx;
						// in CGB mode, the first matching sprite has priority instead, so we can just stop searching
						if (cgbMode) {
							break;
						}
						version(assumeOAMImmutableDiscarded) {
							// it's sorted according to priority already, so we can stop at the first sprite
							break;
						}
					}
				}
			}
			// grab pixel from background or window
			const bool useWindow = registers.lcdc.windowDisplay && (x >= registers.wx - 7) && (registers.ly >= registers.wy);
			const finalX = useWindow ? (x - (registers.wx - 7)) : (baseX + x);
			const finalY = useWindow ? baseWindowY : baseY;
			const attributes = (useWindow ? windowTilemapRowAttributes : tilemapRowAttributes)[(finalX / 8) % fullTileWidth];
			const tile = (useWindow ? windowTilemapRow : tilemapRow)[(finalX / 8) % fullTileWidth];
			const subX = autoFlip(cast(ubyte)(finalX % 8), attributes.xFlip);
			const subY = autoFlip(cast(ubyte)(finalY % 8), attributes.yFlip);
			auto prospectivePixel = getTile(tile, true, attributes.bank)[subX, subY];
			auto prospectivePalette = attributes.palette;
			auto prospectivePriority = attributes.priority;
			// decide between sprite pixel and background pixel using priority settings
			if (highestMatchingSprite != size_t.max) {
				const sprite = oamSorted[highestMatchingSprite];
				const xpos = autoFlip(x - (sprite.x - 8), sprite.flags.xFlip);
				const ypos = autoFlip((registers.ly - (sprite.y - 16)), sprite.flags.yFlip, sprHeight);
				// a combined priority below 5 causes a sprite pixel to be drawn instead of a BG/window pixel
				static immutable bool[8] objPriority = () { return iota(0, 8).map!(x => x < 5).array; } ();
				const combinedPriority = ((!cgbMode || registers.lcdc.bgEnabled) << 2) + (sprite.flags.priority << 1) + prospectivePriority;
				if (objPriority[combinedPriority] || (prospectivePixel == 0)) {
					const pixel = getTile(cast(short)(sprite.tile + ypos / 8), false, cgbMode && sprite.flags.bank)[xpos, ypos % 8];
					if (pixel != 0) {
						prospectivePixel = pixel;
						prospectivePalette = cast(ubyte)(8 + (cgbMode ? sprite.flags.cgbPalette : sprite.flags.dmgPalette));
					}
				}
			}
			pixelRow[x] = paletteRAM[prospectivePalette][prospectivePixel];
		}
	}
	auto bank() inout=> (cgbMode && registers.vbk) ? vram.raw[0x2000 .. 0x4000] : vram.raw[0x0000 .. 0x2000];
	auto bgScreen() inout => registers.lcdc.bgTilemap ? vram.screenB[] : vram.screenA[];
	auto bgScreenCGB() inout => registers.lcdc.bgTilemap ? vram.screenBCGB[] : vram.screenACGB[];
	auto bgScreen2D() const => Array2D!(const ubyte)(fullTileWidth, fullTileHeight, bgScreen);
	auto bgScreenCGB2D() const => Array2D!(const CGBBGAttributeValue)(fullTileWidth, fullTileHeight, bgScreenCGB);
	auto oam() inout => cast(inout(ubyte)[])_oam[];
	auto windowScreen() inout => registers.lcdc.windowTilemap ? vram.screenB[] : vram.screenA[];
	auto windowScreenCGB() inout => registers.lcdc.windowTilemap ? vram.screenBCGB[] : vram.screenACGB[];
	auto windowScreen2D() const => Array2D!(const ubyte)(fullTileWidth, fullTileHeight, windowScreen);
	auto windowScreenCGB2D() const=> Array2D!(const CGBBGAttributeValue)(fullTileWidth, fullTileHeight, windowScreenCGB);
	Intertwined2BPP getTile(short id, bool useLCDC, ubyte bank) const @safe pure {
		auto blockA = (cgbMode && bank) ? vram.tileBlockACGB[] : vram.tileBlockA[];
		auto blockB = (cgbMode && bank) ? vram.tileBlockBCGB[] : vram.tileBlockB[];
		auto blockC = (cgbMode && bank) ? vram.tileBlockCCGB[] : vram.tileBlockC[];
		const tileBlock = (id > 127) ? blockB : ((useLCDC && !registers.lcdc.useAltBG ? blockC : blockA));
		return tileBlock[id % 128];
	}
	Intertwined2BPP getTileUnmapped(short id, ubyte bank) const @safe pure {
		return (cast(const(Intertwined2BPP)[])(vram.raw[0x0000 + bank * 0x2000 .. 0x1800 + bank * 0x2000]))[id];
	}
	void beginDrawing(Array2D!ColourFormat pixels) @safe pure {
		oamSorted = _oam;
		if (!cgbMode) {
			// optimization that can be enabled when the OAM is not modified mid-frame and is discarded at the end
			// allows priority to be determined just by picking the first matching entry instead of iterating the entire array
			version(assumeOAMImmutableDiscarded) {
				import std.algorithm.sorting : sort;
				sort!((a, b) => a.x < b.x)(oamSorted);
			}
		}
		registers.ly = 0;
		this.pixels = pixels;
	}
	void drawFullBackground(Array2D!ColourFormat buffer) const @safe pure => drawDebugCommon(buffer, bgScreen2D, bgScreenCGB2D);
	void drawFullWindow(Array2D!ColourFormat buffer) const @safe pure  => drawDebugCommon(buffer, windowScreen2D, windowScreenCGB2D);
	void drawDebugCommon(Array2D!ColourFormat buffer, const Array2D!(const ubyte) tiles, const Array2D!(const CGBBGAttributeValue) attributes) const @safe pure {
		foreach (size_t tileX, size_t tileY, const ubyte tileID; tiles) {
			const tile = getTile(tileID, true, attributes[tileX, tileY].bank);
			foreach (subPixelX; 0 .. 8) {
				const x = autoFlip(subPixelX, attributes[tileX, tileY].xFlip);
				foreach (subPixelY; 0 .. 8) {
					const y = autoFlip(subPixelY, attributes[tileX, tileY].yFlip);
					buffer[tileX * 8 + subPixelX, tileY * 8 + subPixelY] = paletteRAM[attributes[tileX, tileY].palette][tile[x, y]];
				}
			}
		}
	}
	void drawSprite(Array2D!ColourFormat buffer, uint sprite) @safe pure {
		const tiles = 1 + registers.lcdc.tallSprites;
		const oamEntry = _oam[sprite];
		foreach (tileID; 0 .. tiles) {
			const tile = getTile((oamEntry.tile + tileID) & 0xFF, false, oamEntry.flags.bank);
			foreach (x; 0 .. 8) {
				const tileX = autoFlip(x, oamEntry.flags.xFlip);
				foreach (y; 0 .. 8) {
					const tileY = autoFlip(y, oamEntry.flags.yFlip);
					const palette = 8 + (cgbMode ? oamEntry.flags.cgbPalette : oamEntry.flags.dmgPalette);
					buffer[x, y + 8 * tileID] = paletteRAM[palette][tile[tileX, tileY]];
				}
			}
		}
	}
	void writeRegister(ushort addr, ubyte val) @safe pure {
		static void autoIncrementCPD(ref ubyte value) {
			if (value & 0x80) {
				value++;
				value &= 0b10111111;
			}
		}
		void writePaletteDMG(ubyte value, size_t paletteIndex) {
			if (!cgbMode) {
				ColourFormat[] palette = paletteRAM[paletteIndex][];
				palette[0] = gbPalette[paletteIndex][value & 3];
				palette[1] = gbPalette[paletteIndex][(value >> 2) & 3];
				palette[2] = gbPalette[paletteIndex][(value >> 4) & 3];
				palette[3] = gbPalette[paletteIndex][(value >> 6) & 3];
			}
		}
		switch (addr) {
			case Register.SCX:
				registers.scx = val;
				break;
			case Register.SCY:
				registers.scy = val;
				break;
			case Register.WX:
				registers.wx = val;
				break;
			case Register.WY:
				registers.wy = val;
				break;
			case Register.LY:
				// read-only
				break;
			case Register.LYC:
				registers.lyc = val;
				break;
			case Register.LCDC:
				registers.lcdc.raw = val;
				break;
			case Register.STAT:
				registers.stat.raw = val;
				break;
			case Register.BGP:
				registers.bgp = val;
				writePaletteDMG(val, 0);
				break;
			case Register.OBP0:
				registers.obp0 = val;
				writePaletteDMG(val, 8);
				break;
			case Register.OBP1:
				registers.obp1 = val;
				writePaletteDMG(val, 9);
				break;
			case Register.BCPS:
				registers.bcps = val & 0b10111111;
				break;
			case Register.BCPD:
				(cast(ubyte[])paletteRAM)[registers.bcps & 0b00111111] = val;
				autoIncrementCPD(registers.bcps);
				break;
			case Register.OCPS:
				registers.ocps = val;
				break;
			case Register.OCPD:
				(cast(ubyte[])paletteRAM)[64 + (registers.ocps & 0b00111111)] = val;
				autoIncrementCPD(registers.ocps);
				break;
			case Register.VBK:
				registers.vbk = val & 1;
				break;
			default:
				break;
		}
	}
	ubyte readRegister(ushort addr) const @safe pure {
		switch (addr) {
			case Register.SCX:
				return registers.scx;
			case Register.SCY:
				return registers.scy;
			case Register.WX:
				return registers.wx;
			case Register.WY:
				return registers.wy;
			case Register.LY:
				return registers.ly;
			case Register.LYC:
				return registers.lyc;
			case Register.LCDC:
				return registers.lcdc.raw;
			case Register.STAT:
				return registers.stat.raw;
			case Register.BGP:
				return registers.bgp;
			case Register.OBP0:
				return registers.obp0;
			case Register.OBP1:
				return registers.obp1;
			default:
				return 0; // open bus, but we're not doing anything with that yet
		}
	}
	void debugUI(UIState state) {
		static void inputPaletteRegister(string label, string label2, ref ubyte palette) {
			if (ImGui.TreeNode(label, label2, palette)) {
				foreach (i; 0 .. 4) {
					ImGui.Text("Colour %d", i);
					foreach (colourIdx, colour; pocketPalette.map!(x => ImVec4(x.red / 31.0, x.green / 31.0, x.blue / 31.0, 1.0)).enumerate) {
						ImGui.PushStyleColor(ImGuiCol.CheckMark, colour);
						ImGui.SameLine();
						if (ImGui.RadioButton("", ((palette >> (i * 2)) & 3) == colourIdx)) {
							palette = cast(ubyte)((palette & ~(3 << (i * 2))) | (colourIdx << (i * 2)));
						}
						ImGui.PopStyleColor();
					}
				}
				ImGui.TreePop();
			}
		}
		enum height = 256;
		enum width = 256;
		static Array2D!ColourFormat buffer = Array2D!ColourFormat(width, height);
		if (ImGui.BeginTabBar("rendererpreview")) {
			if (ImGui.BeginTabItem("State")) {
				if (ImGui.TreeNode("STAT", "STAT: %02X", registers.stat.raw)) {
					registerBitSel!2("PPU mode", registers.stat.raw, 0, ["HBlank", "VBlank", "OAM scan", "Drawing"]);
					ImGui.SetItemTooltip("Current PPU rendering mode. (not currently emulated)");
					registerBit("LY = LYC", registers.stat.raw, 2);
					ImGui.SetItemTooltip("Flag set if LY == LYC. (not currently emulated)");
					registerBit("Mode 0 interrupt enabled", registers.stat.raw, 3);
					ImGui.SetItemTooltip("HBlank interrupt is enabled.");
					registerBit("Mode 1 interrupt enabled", registers.stat.raw, 4);
					ImGui.SetItemTooltip("VBlank interrupt is enabled.");
					registerBit("Mode 2 interrupt enabled", registers.stat.raw, 5);
					ImGui.SetItemTooltip("OAM scan interrupt is enabled.");
					registerBit("LY == LYC interrupt enabled", registers.stat.raw, 6);
					ImGui.SetItemTooltip("Interrupt is enabled for when LY == LYC.");
					ImGui.TreePop();
				}
				if (ImGui.TreeNode("LCDC", "LCDC: %02X", registers.lcdc.raw)) {
					registerBit("BG+window enable", registers.lcdc.raw, 0);
					ImGui.SetItemTooltip("If disabled, the BG and window layers will not be rendered.");
					registerBit("OBJ enable", registers.lcdc.raw, 1);
					ImGui.SetItemTooltip("Whether or not sprites are enabled.");
					registerBitSel("OBJ size", registers.lcdc.raw, 2, ["8x8", "8x16"]);
					ImGui.SetItemTooltip("The size of all sprites currently being rendered.");
					registerBitSel("BG tilemap area", registers.lcdc.raw, 3, ["$9800", "$9C00"]);
					ImGui.SetItemTooltip("The region of VRAM where the BG tilemap is located.");
					registerBitSel("BG+Window tile area", registers.lcdc.raw, 4, ["$8800", "$8000"]);
					ImGui.SetItemTooltip("The region of VRAM where the BG and window tile data is located.");
					registerBit("Window enable", registers.lcdc.raw, 5);
					ImGui.SetItemTooltip("Whether or not the window layer is enabled.");
					registerBitSel("Window tilemap area", registers.lcdc.raw, 6, ["$9800", "$9C00"]);
					ImGui.SetItemTooltip("The region of VRAM where the window tilemap is located.");
					registerBit("LCD+PPU enable", registers.lcdc.raw, 7);
					ImGui.SetItemTooltip("Whether or not the LCD and PPU are active.");
					ImGui.TreePop();
				}
				ImGui.InputScalar("SCX", ImGuiDataType.U8, &registers.scx, null, null, "%02X");
				ImGui.InputScalar("SCY", ImGuiDataType.U8, &registers.scy, null, null, "%02X");
				ImGui.InputScalar("LY", ImGuiDataType.U8, &registers.ly, null, null, "%02X");
				ImGui.InputScalar("LYC", ImGuiDataType.U8, &registers.lyc, null, null, "%02X");
				inputPaletteRegister("BGP", "BGP: %02X", registers.bgp);
				inputPaletteRegister("OBP0", "OBP0: %02X", registers.obp0);
				inputPaletteRegister("OBP1", "OBP1: %02X", registers.obp1);
				ImGui.InputScalar("WX", ImGuiDataType.U8, &registers.wx, null, null, "%02X");
				ImGui.InputScalar("WY", ImGuiDataType.U8, &registers.wy, null, null, "%02X");
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Palettes")) {
				showPalette(cast(ColourFormat[])paletteRAM[], 4);
				ImGui.EndTabItem();
			}
			void showTileInfo(int x, int y, Array2D!(const ubyte) tileID, Array2D!(const CGBBGAttributeValue) tileAttributes) {
				const tileX = x / 8;
				const tileY = y / 8;
				ImGui.SeparatorText(format!"Tile at %d, %d"(tileX, tileY));
				ImGui.Text("Tile %d (%X)", tileID[tileX, tileY], tileID[tileX, tileY]);
				ImGui.Text("Palette %d", tileAttributes[tileX, tileY].palette);
				ImGui.Text("Bank %d", tileAttributes[tileX, tileY].bank);
				bool xFlip = tileAttributes[tileX, tileY].xFlip;
				ImGui.Checkbox("Flip (horizontal)", &xFlip);
				bool yFlip = tileAttributes[tileX, tileY].yFlip;
				ImGui.Checkbox("Flip (vertical)", &yFlip);
				bool priority = tileAttributes[tileX, tileY].priority;
				ImGui.Checkbox("Priority", &priority);
			}
			if (ImGui.BeginTabItem("Background")) {
				static void* surface;
				drawFullBackground(buffer);
				auto tiles = bgScreen2D();
				auto attributes = bgScreenCGB2D();
				drawZoomableImage(buffer, state, surface, (x, y) { showTileInfo(x, y, tiles, attributes); });
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Window")) {
				static void* surface;
				drawFullWindow(buffer);
				auto tiles = windowScreen2D();
				auto attributes = windowScreenCGB2D();
				drawZoomableImage(buffer, state, surface, (x, y) { showTileInfo(x, y, tiles, attributes); });
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("VRAM")) {
				static void* surface;
				drawZoomableTiles(cast(Intertwined2BPP[])vram.raw, paletteRAM[], state, surface);
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("OAM")) {
				drawSprites!ColourFormat(_oam.length, state, 8, 16, (canvas, index) {
					drawSprite(canvas, cast(uint)index);
				}, (index) {
					const sprite = _oam[index];
					ImGui.Text("Coordinates: %d, %d", sprite.x, sprite.y);
					ImGui.Text("Tile: %d", sprite.tile);
					ImGui.Text("Orientation: ");
					ImGui.SameLine();
					ImGui.Text(["Normal", "Flipped horizontally", "Flipped vertically", "Flipped horizontally, vertically"][(sprite.flags.raw >> 5) & 3]);
					ImGui.Text("Priority: ");
					ImGui.SameLine();
					ImGui.Text(["Normal", "High"][sprite.flags.priority]);
					ImGui.Text("Palette: %d", cgbMode ? sprite.flags.cgbPalette : sprite.flags.dmgPalette);
				});
				ImGui.EndTabItem();
			}
			ImGui.EndTabBar();
		}
	}
	void dump(StateDumper dumpFunction) @safe {}
}

unittest {
	enum testData = [0x01, 0x23, 0x45, 0x67, 0x89];
	PPU ppu;
	ppu.writeRegister(0xFF68, 0x80);
	foreach (ubyte value; testData) {
		ppu.writeRegister(0xFF69, value);
	}
	assert((cast(ubyte[])ppu.paletteRAM)[0 .. 5] == testData);
	ppu.writeRegister(0xFF6A, 0x80);
	foreach (ubyte value; testData) {
		ppu.writeRegister(0xFF6B, value);
	}
	assert((cast(ubyte[])ppu.paletteRAM)[64 .. 69] == testData);
}

unittest {
	import std.algorithm.iteration : splitter;
	import std.array : split;
	import std.conv : to;
	import std.file : exists, read, readText;
	import std.format : format;
	import std.math : round;
	import std.path : buildPath;
	import std.string : lineSplitter;
	import std.stdio : File;
	import replatform64.dumping : convert, writePNG;
	enum width = 160;
	enum height = 144;
	static auto draw(ref PPU ppu, FauxDMA[] dma) {
		auto buffer = Array2D!(PPU.ColourFormat)(width, height);
		ppu.beginDrawing(buffer);
		foreach (i; 0 .. height) {
			foreach (entry; dma) {
				if (i == entry.scanline) {
					ppu.writeRegister(cast(Register)entry.register, entry.value);
				}
			}
			ppu.runLine();
			ppu.registers.ly++;
		}
		return buffer;
	}
	static auto renderMesen2State(const ubyte[] file, FauxDMA[] dma) {
		PPU ppu;
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
					ppu.writeRegister(Register.OBP0, byteData);
					break;
				case "ppu.objPalette1":
					ppu.writeRegister(Register.OBP1, byteData);
					break;
				case "ppu.bgPalette":
					ppu.writeRegister(Register.BGP, byteData);
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
					lcdc.tallSprites = byteData & 1;
					break;
				case "ppu.bgTilemapSelect":
					lcdc.bgTilemap = byteData & 1;
					break;
				case "ppu.windowEnabled":
					lcdc.windowDisplay = byteData & 1;
					break;
				case "ppu.windowTilemapSelect":
					lcdc.windowTilemap = byteData & 1;
					break;
				case "ppu.lcdEnabled":
					lcdc.lcdEnabled = byteData & 1;
					break;
				case "ppu.bgTileSelect":
					lcdc.useAltBG = byteData & 1;
					break;
				case "ppu.mode":
					stat.mode = intData & 3;
					break;
				case "ppu.lyCoincidenceFlag":
					stat.lycEqualLY = byteData & 1;
					break;
				case "ppu.cgbEnabled":
					ppu.cgbMode = byteData & 1;
					break;
				case "ppu.status":
					stat.mode0Interrupt = !!(byteData & 0b00001000);
					stat.mode1Interrupt = !!(byteData & 0b00010000);
					stat.mode2Interrupt = !!(byteData & 0b00100000);
					stat.lycInterrupt = !!(byteData & 0b01000000);
					break;
				case "videoRam":
					ppu.vram.raw[0x0000 .. data.length] = data;
					break;
				case "spriteRam":
					ppu.oam[] = data;
					break;
				case "ppu.cgbBgPalettes":
					ppu.paletteRAM[0 .. 8] = cast(const(PPU.ColourFormat)[4][])data;
					break;
				case "ppu.cgbObjPalettes":
					ppu.paletteRAM[8 .. 16] = cast(const(PPU.ColourFormat)[4][])data;
					break;
				default:
					break;
			}
		});
		ppu.registers.lcdc = lcdc;
		ppu.registers.stat = stat;
		return draw(ppu, dma);
	}
	assert(runTests!renderMesen2State("gameboy", ""), "Tests failed");
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
immutable PPU.ColourFormat[] pocketPalette = [
	PPU.ColourFormat(31, 31, 31),
	PPU.ColourFormat(22, 22, 22),
	PPU.ColourFormat(13, 13, 13),
	PPU.ColourFormat(0, 0, 0)
];
enum pocketPaletteCGB = pocketPalette.repeat(16).array;
immutable PPU.ColourFormat[] dmgPalette = [
	PPU.ColourFormat(red: 19, green: 23, blue: 1),
	PPU.ColourFormat(red: 17, green: 21, blue: 1),
	PPU.ColourFormat(red: 6, green: 12, blue: 6),
	PPU.ColourFormat(red: 1, green: 7, blue: 1)
];
enum dmgPaletteCGB = dmgPalette.repeat(16).array;

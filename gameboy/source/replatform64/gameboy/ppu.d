module replatform64.gameboy.ppu;

import replatform64.backend.common.interfaces;
import replatform64.gameboy.common;
import replatform64.gameboy.hardware;

import replatform64.testhelpers;
import replatform64.ui;
import replatform64.util;

import std.algorithm.iteration;
import std.bitmanip : bitfields;
import std.format;
import std.range;

import tilemagic.colours;
import tilemagic.tiles.bpp2;

private immutable ubyte[0x2000] dmgExt;
struct PPU {
	alias ColourFormat = BGR555;
	static struct Registers {
		ubyte stat;
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
	ubyte[] vram;
	OAMEntry[40] _oam;
	ColourFormat[4][16] paletteRAM = pocketPaletteCGB;
	const(ColourFormat)[4][] gbPalette = pocketPaletteCGB;

	private Array2D!ColourFormat pixels;
	private OAMEntry[] oamSorted;
	void runLine() @safe pure {
		const sprHeight = 8 * (1 + registers.lcdc.tallSprites);
		const baseX = registers.scx;
		const baseY = registers.scy + registers.ly;
		auto pixelRow = pixels[0 .. $, registers.ly];
		const tilemapBase = ((baseY / 8) % fullTileWidth) * 32;
		const tilemapRow = bgScreen[tilemapBase .. tilemapBase + fullTileWidth];
		const tilemapRowAttributes = cgbMode ? bgScreenCGB[tilemapBase .. tilemapBase + fullTileWidth] : dmgExt[0 .. fullTileWidth];
		lineLoop: foreach (x; 0 .. width) {
			size_t highestMatchingSprite = size_t.max;
			int highestX = int.max;
			// first, find a sprite at these coords with a non-transparent pixel
			foreach (idx, sprite; oamSorted) {
				if (registers.ly.inRange(sprite.y - 16, sprite.y - (registers.lcdc.tallSprites ? 0 : 8)) && x.inRange(sprite.x - 8, sprite.x)) {
					auto xpos = x - (sprite.x - 8);
					auto ypos = (registers.ly - (sprite.y - 16));
					if (sprite.flags.xFlip) {
						xpos = 7 - xpos;
					}
					if (sprite.flags.yFlip) {
						ypos = sprHeight - 1 - ypos;
					}
					// ignore transparent pixels
					if (getTile(cast(short)(sprite.tile + ypos / 8), false, cgbMode && sprite.flags.bank)[xpos, ypos % 8] == 0) {
						continue;
					}
					if (sprite.x - 8 < highestX) {
						highestX = sprite.x - 8;
						highestMatchingSprite = idx;
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
			ushort prospectivePixel;
			ubyte prospectivePalette;
			bool prospectivePriority;
			// grab pixel from background or window
			if (registers.lcdc.windowDisplay && (x >= registers.wx - 7) && (registers.ly >= registers.wy)) {
				auto finalX = x - (registers.wx - 7);
				auto finalY = registers.ly - registers.wy;
				const windowTilemapBase = (finalY / 8) * 32;
				const windowTilemapRow = windowScreen[windowTilemapBase .. windowTilemapBase + fullTileWidth];
				const windowTilemapRowAttributes = cast(const(CGBBGAttributeValue)[])(cgbMode ? windowScreenCGB[windowTilemapBase .. windowTilemapBase + fullTileWidth] : dmgExt[0 .. fullTileWidth]);
				const tile = windowTilemapRow[finalX / 8];
				const attributes = windowTilemapRowAttributes[finalX / 8];
				auto subX = finalX % 8;
				auto subY = finalY % 8;
				if (attributes.xFlip) {
					subX = 7 - subX;
				}
				if (attributes.yFlip) {
					subY = 7 - subY;
				}
				prospectivePixel = getTile(tile, true, attributes.bank)[subX, subY];
				prospectivePalette = attributes.palette;
				prospectivePriority = attributes.priority;
			} else {
				uint finalX = baseX + x;
				uint finalY = baseY;
				const tile = tilemapRow[(finalX / 8) % 32];
				const attributes = cast(CGBBGAttributeValue)tilemapRowAttributes[(finalX / 8) % 32];
				auto subX = finalX % 8;
				auto subY = finalY % 8;
				if (attributes.xFlip) {
					subX = 7 - (subX % 8);
				}
				if (attributes.yFlip) {
					subY = 7 - (subY % 8);
				}
				prospectivePixel = getTile(tile, true, attributes.bank)[subX % 8, subY % 8];
				prospectivePalette = attributes.palette;
				prospectivePriority = attributes.priority;
			}
			// decide between sprite pixel and background pixel using priority settings
			if (highestMatchingSprite != size_t.max) {
				const sprite = oamSorted[highestMatchingSprite];
				auto xpos = x - (sprite.x - 8);
				auto ypos = (registers.ly - (sprite.y - 16));
				if (sprite.flags.xFlip) {
					xpos = 7 - xpos;
				}
				if (sprite.flags.yFlip) {
					ypos = sprHeight - 1 - ypos;
				}
				static immutable bool[8] objPriority = [
					0b000: true,
					0b001: true,
					0b010: true,
					0b011: true,
					0b100: true,
					0b101: false,
					0b110: false,
					0b111: false,
				];
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
		registers.ly++;
	}
	inout(ubyte)[] bank() inout @safe pure {
		return (cgbMode && registers.vbk) ? vram[0x2000 .. 0x4000] : vram[0x0000 .. 0x2000];
	}
	inout(ubyte)[] bgScreen() inout @safe pure {
		return registers.lcdc.bgTilemap ? screenB : screenA;
	}
	inout(ubyte)[] bgScreenCGB() inout @safe pure {
		return registers.lcdc.bgTilemap ? screenBCGB : screenACGB;
	}
	Array2D!(const ubyte) bgScreen2D() const @safe pure {
		return Array2D!(const ubyte)(32, 32, 32, bgScreen);
	}
	Array2D!(const CGBBGAttributeValue) bgScreenCGB2D() const @safe pure {
		return Array2D!(const CGBBGAttributeValue)(32, 32, 32, cast(const(CGBBGAttributeValue)[])(cgbMode ? bgScreenCGB : dmgExt[0 .. 0x400]));
	}
	inout(ubyte)[] tileBlockA() inout @safe pure {
		return vram[0x0000 .. 0x0800];
	}
	inout(ubyte)[] tileBlockB() inout @safe pure {
		return vram[0x0800 .. 0x1000];
	}
	inout(ubyte)[] tileBlockC() inout @safe pure {
		return vram[0x1000 .. 0x1800];
	}
	inout(ubyte)[] tileBlockACGB() inout @safe pure {
		return vram[0x2000 .. 0x2800];
	}
	inout(ubyte)[] tileBlockBCGB() inout @safe pure {
		return vram[0x2800 .. 0x3000];
	}
	inout(ubyte)[] tileBlockCCGB() inout @safe pure {
		return vram[0x3000 .. 0x3800];
	}
	inout(ubyte)[] screenA() inout @safe pure {
		return vram[0x1800 .. 0x1C00];
	}
	inout(ubyte)[] screenB() inout @safe pure {
		return vram[0x1C00 .. 0x2000];
	}
	inout(ubyte)[] screenACGB() inout @safe pure {
		return vram[0x3800 .. 0x3C00];
	}
	inout(ubyte)[] screenBCGB() inout @safe pure {
		return vram[0x3C00 .. 0x4000];
	}
	inout(ubyte)[] oam() return inout @safe pure {
		return cast(inout(ubyte)[])_oam[];
	}
	inout(ubyte)[] windowScreen() inout @safe pure {
		return registers.lcdc.windowTilemap ? screenB : screenA;
	}
	inout(ubyte)[] windowScreenCGB() inout @safe pure {
		return registers.lcdc.windowTilemap ? screenBCGB : screenACGB;
	}
	Array2D!(const ubyte) windowScreen2D() const @safe pure {
		return Array2D!(const ubyte)(32, 32, 32, windowScreen);
	}
	Array2D!(const CGBBGAttributeValue) windowScreenCGB2D() const @safe pure {
		return Array2D!(const CGBBGAttributeValue)(32, 32, 32, cast(const(CGBBGAttributeValue)[])(cgbMode ? windowScreenCGB : dmgExt[0 .. 0x400]));
	}
	Intertwined2BPP getTile(short id, bool useLCDC, ubyte bank) const @safe pure {
		auto blockA = (cgbMode && bank) ? tileBlockACGB : tileBlockA;
		auto blockB = (cgbMode && bank) ? tileBlockBCGB : tileBlockB;
		auto blockC = (cgbMode && bank) ? tileBlockCCGB : tileBlockC;
		const tileBlock = (id > 127) ? blockB : ((useLCDC && !registers.lcdc.useAltBG ? blockC : blockA));
		return (cast(const(Intertwined2BPP)[])(tileBlock[(id % 128) * 16 .. ((id % 128) * 16) + 16]))[0];
	}
	Intertwined2BPP getTileUnmapped(short id, ubyte bank) const @safe pure {
		return (cast(const(Intertwined2BPP)[])(vram[0x0000 + bank * 0x2000 .. 0x1800 + bank * 0x2000]))[id];
	}
	void beginDrawing(ubyte[] pixels, size_t stride) @safe pure {
		beginDrawing(Array2D!ColourFormat(width, height, cast(int)(stride / ColourFormat.sizeof), cast(ColourFormat[])pixels));
	}
	void beginDrawing(Array2D!ColourFormat pixels) @safe pure {
		oamSorted = cast(OAMEntry[])oam;
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
	void drawFullFrame(ubyte[] pixels, size_t stride) @safe pure {
		beginDrawing(pixels, stride);
		foreach (i; 0 .. height) {
			runLine();
		}
	}
	void drawFullBackground(Array2D!ColourFormat buffer) const @safe pure {
		drawDebugCommon(buffer, bgScreen2D, bgScreenCGB2D);
	}
	void drawFullWindow(Array2D!ColourFormat buffer) const @safe pure {
		drawDebugCommon(buffer, windowScreen2D, windowScreenCGB2D);
	}
	void drawDebugCommon(Array2D!ColourFormat buffer, const Array2D!(const ubyte) tiles, const Array2D!(const CGBBGAttributeValue) attributes) const @safe pure {
		foreach (size_t tileX, size_t tileY, const ubyte tileID; tiles) {
			const tile = getTile(tileID, true, attributes[tileX, tileY].bank);
			foreach (subPixelX; 0 .. 8) {
				auto x = subPixelX;
				if (attributes[tileX, tileY].xFlip) {
					x = 7 - x;
				}
				foreach (subPixelY; 0 .. 8) {
					auto y = subPixelY;
					if (attributes[tileX, tileY].yFlip) {
						y = 7 - y;
					}
					buffer[tileX * 8 + subPixelX, tileY * 8 + subPixelY] = paletteRAM[attributes[tileX, tileY].palette][tile[x, y]];
				}
			}
		}
	}
	void drawFullTileData(Array2D!ColourFormat buffer) @safe pure
		in (buffer.dimensions[0] % 8 == 0, "Buffer width must be a multiple of 8")
		in (buffer.dimensions[1] % 8 == 0, "Buffer height must be a multiple of 8")
		in (buffer.dimensions[0] * buffer.dimensions[1] <= 768 * 8 * 8, "Buffer too small")
	{
		foreach (tileID; 0 .. cgbMode ? 768 : 384) {
			const tileX = (tileID % (buffer.dimensions[0] / 8));
			const tileY = (tileID / (buffer.dimensions[0] / 8));
			const tile = getTileUnmapped(cast(short)tileID % 384, cast(ubyte)(tileID / 384));
			foreach (subPixelX; 0 .. 8) {
				foreach (subPixelY; 0 .. 8) {
					buffer[tileX * 8 + subPixelX, tileY * 8 + subPixelY] = paletteRAM[0][tile[subPixelX, subPixelY]];
				}
			}
		}
	}
	void drawSprite(ubyte[] pixels, size_t stride, uint sprite) @safe pure {
		drawSprite(Array2D!ColourFormat(8, 16, cast(int)(stride / ushort.sizeof), cast(ColourFormat[])pixels), sprite);
	}
	void drawSprite(Array2D!ColourFormat buffer, uint sprite) @safe pure {
		const tiles = 1 + registers.lcdc.tallSprites;
		const oamEntry = (cast(OAMEntry[])oam)[sprite];
		foreach (tileID; 0 .. tiles) {
			const tile = getTile((oamEntry.tile + tileID) & 0xFF, false, oamEntry.flags.bank);
			foreach (x; 0 .. 8) {
				foreach (y; 0 .. 8) {
					const tileX = oamEntry.flags.xFlip ? 7 - x : x;
					const tileY = oamEntry.flags.yFlip ? 7 - y : y;
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
			case GameBoyRegister.SCX:
				registers.scx = val;
				break;
			case GameBoyRegister.SCY:
				registers.scy = val;
				break;
			case GameBoyRegister.WX:
				registers.wx = val;
				break;
			case GameBoyRegister.WY:
				registers.wy = val;
				break;
			case GameBoyRegister.LY:
				// read-only
				break;
			case GameBoyRegister.LYC:
				registers.lyc = val;
				break;
			case GameBoyRegister.LCDC:
				registers.lcdc.raw = val;
				break;
			case GameBoyRegister.STAT:
				registers.stat = val;
				break;
			case GameBoyRegister.BGP:
				registers.bgp = val;
				writePaletteDMG(val, 0);
				break;
			case GameBoyRegister.OBP0:
				registers.obp0 = val;
				writePaletteDMG(val, 8);
				break;
			case GameBoyRegister.OBP1:
				registers.obp1 = val;
				writePaletteDMG(val, 9);
				break;
			case GameBoyRegister.BCPS:
				registers.bcps = val & 0b10111111;
				break;
			case GameBoyRegister.BCPD:
				(cast(ubyte[])paletteRAM)[registers.bcps & 0b00111111] = val;
				autoIncrementCPD(registers.bcps);
				break;
			case GameBoyRegister.OCPS:
				registers.ocps = val;
				break;
			case GameBoyRegister.OCPD:
				(cast(ubyte[])paletteRAM)[64 + (registers.ocps & 0b00111111)] = val;
				autoIncrementCPD(registers.ocps);
				break;
			case GameBoyRegister.VBK:
				registers.vbk = val & 1;
				break;
			default:
				break;
		}
	}
	ubyte readRegister(ushort addr) @safe pure {
		switch (addr) {
			case GameBoyRegister.SCX:
				return registers.scx;
			case GameBoyRegister.SCY:
				return registers.scy;
			case GameBoyRegister.WX:
				return registers.wx;
			case GameBoyRegister.WY:
				return registers.wy;
			case GameBoyRegister.LY:
				return registers.ly;
			case GameBoyRegister.LYC:
				return registers.lyc;
			case GameBoyRegister.LCDC:
				return registers.lcdc.raw;
			case GameBoyRegister.STAT:
				return registers.stat;
			case GameBoyRegister.BGP:
				return registers.bgp;
			case GameBoyRegister.OBP0:
				return registers.obp0;
			case GameBoyRegister.OBP1:
				return registers.obp1;
			default:
				return 0; // open bus, but we're not doing anything with that yet
		}
	}
	void debugUI(const UIState state, VideoBackend video) {
		static void inputPaletteRegister(string label, ref ubyte palette) {
			if (ImGui.TreeNode(label)) {
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
				if (ImGui.TreeNode("STAT", "STAT: %02X", registers.stat)) {
					registerBitSel!2("PPU mode", registers.stat, 0, ["HBlank", "VBlank", "OAM scan", "Drawing"]);
					ImGui.SetItemTooltip("Current PPU rendering mode. (not currently emulated)");
					registerBit("LY = LYC", registers.stat, 2);
					ImGui.SetItemTooltip("Flag set if LY == LYC. (not currently emulated)");
					registerBit("Mode 0 interrupt enabled", registers.stat, 3);
					ImGui.SetItemTooltip("HBlank interrupt is enabled.");
					registerBit("Mode 1 interrupt enabled", registers.stat, 4);
					ImGui.SetItemTooltip("VBlank interrupt is enabled.");
					registerBit("Mode 2 interrupt enabled", registers.stat, 5);
					ImGui.SetItemTooltip("OAM scan interrupt is enabled.");
					registerBit("LY == LYC interrupt enabled", registers.stat, 6);
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
				inputPaletteRegister("BGP", registers.bgp);
				inputPaletteRegister("OBP0", registers.obp0);
				inputPaletteRegister("OBP1", registers.obp1);
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
				drawZoomableImage(buffer, video, surface, (x, y) { showTileInfo(x, y, tiles, attributes); });
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Window")) {
				static void* surface;
				drawFullWindow(buffer);
				auto tiles = windowScreen2D();
				auto attributes = windowScreenCGB2D();
				drawZoomableImage(buffer, video, surface, (x, y) { showTileInfo(x, y, tiles, attributes); });
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("VRAM")) {
				static void* surface;
				drawZoomableTiles(cast(Intertwined2BPP[])vram, cast(ColourFormat[4][])(paletteRAM[]), video, surface);
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("OAM")) {
				drawSprites!ColourFormat(_oam.length, video, 8, 16, (canvas, index) {
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
	import replatform64.dumping : convert, dumpPNG;
	enum width = 160;
	enum height = 144;
	static struct FauxDMA {
		ubyte scanline;
		GameBoyRegister register;
		ubyte value;
	}
	static auto draw(ref PPU ppu, FauxDMA[] dma = []) {
		auto buffer = Array2D!(PPU.ColourFormat)(width, height);
		ppu.beginDrawing(buffer);
		foreach (i; 0 .. height) {
			foreach (entry; dma) {
				if (i == entry.scanline) {
					ppu.writeRegister(entry.register, entry.value);
				}
			}
			ppu.runLine();
		}
		return buffer;
	}
	static auto renderMesen2State(const ubyte[] file, FauxDMA[] dma = []) {
		PPU ppu;
		ppu.vram = new ubyte[](0x4000);
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
					ppu.writeRegister(GameBoyRegister.OBP0, byteData);
					break;
				case "ppu.objPalette1":
					ppu.writeRegister(GameBoyRegister.OBP1, byteData);
					break;
				case "ppu.bgPalette":
					ppu.writeRegister(GameBoyRegister.BGP, byteData);
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
					stat.coincidence = byteData & 1;
					break;
				case "ppu.cgbEnabled":
					ppu.cgbMode = byteData & 1;
					break;
				case "ppu.status":
					stat.mode0HBlankIRQ = !!(byteData & 0b00001000);
					stat.mode1VBlankIRQ = !!(byteData & 0b00010000);
					stat.mode2OAMIRQ = !!(byteData & 0b00100000);
					stat.lycEqualsLYFlag = !!(byteData & 0b01000000);
					break;
				case "videoRam":
					ppu.vram[0x0000 .. data.length] = data;
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
		ppu.registers.stat = stat.raw;
		return draw(ppu, dma);
	}
	static void runTest(string name) {
		FauxDMA[] dma;
		const dmaPath = buildPath("testdata/gameboy", name~".dma");
		if (dmaPath.exists) {
			foreach (line; File(dmaPath, "r").byLine) {
				auto split = line.split(" ");
				dma ~= FauxDMA(split[0].to!ubyte, cast(GameBoyRegister)split[1].to!ushort(16), split[2].to!ubyte(16));
			}
		}
		const frame = renderMesen2State(cast(ubyte[])read(buildPath("testdata/gameboy", name~".mss")), dma);
		if (const result = comparePNG(frame, "testdata/gameboy", name~".png")) {
			dumpPNG(frame, "failed/"~name~".png");
			assert(0, format!"Pixel mismatch at %s, %s in %s (got %s, expecting %s)"(result.x, result.y, name, result.got, result.expected));
		}
	}
	runTest("everythingok");
	runTest("ffl2");
	runTest("m2");
	runTest("w2");
	runTest("mqueen1");
	runTest("gator");
	runTest("ffa-obp1");
	runTest("ooaintro");
	runTest("ooaintro2");
	runTest("ooaintro3");
	runTest("ooaintro4");
	runTest("cgb_bg_oam_priority");
	runTest("cgb_oam_internal_priority");
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

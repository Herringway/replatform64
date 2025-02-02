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
	BGR555[64] paletteRAM;
	immutable(BGR555)[] gbPalette = pocketPalette;

	private Array2D!BGR555 pixels;
	private OAMEntry[] oamSorted;
	void runLine() @safe pure {
		const sprHeight = 8 * (1 + !!(registers.lcdc & LCDCFlags.tallSprites));
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
				if (registers.ly.inRange(sprite.y - 16, sprite.y - ((registers.lcdc & LCDCFlags.tallSprites) ? 0 : 8)) && x.inRange(sprite.x - 8, sprite.x)) {
					auto xpos = x - (sprite.x - 8);
					auto ypos = (registers.ly - (sprite.y - 16));
					if (sprite.flags & OAMFlags.xFlip) {
						xpos = 7 - xpos;
					}
					if (sprite.flags & OAMFlags.yFlip) {
						ypos = sprHeight - 1 - ypos;
					}
					// ignore transparent pixels
					if (getTile(cast(short)(sprite.tile + ypos / 8), false, cgbMode && !!(sprite.flags & OAMFlags.bank))[xpos, ypos % 8] == 0) {
						continue;
					}
					if (sprite.x - 8 < highestX) {
						highestX = sprite.x - 8;
						highestMatchingSprite = idx;
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
			if ((registers.lcdc & LCDCFlags.windowDisplay) && (x >= registers.wx - 7) && (registers.ly >= registers.wy)) {
				auto finalX = x - (registers.wx - 7);
				auto finalY = registers.ly - registers.wy;
				const windowTilemapBase = (finalY / 8) * 32;
				const windowTilemapRow = windowScreen[windowTilemapBase .. windowTilemapBase + fullTileWidth];
				const windowTilemapRowAttributes = cgbMode ? windowScreenCGB[windowTilemapBase .. windowTilemapBase + fullTileWidth] : dmgExt[0 .. fullTileWidth];
				const tile = windowTilemapRow[finalX / 8];
				const attributes = windowTilemapRowAttributes[finalX / 8];
				auto subX = finalX % 8;
				auto subY = finalY % 8;
				if (attributes & CGBBGAttributes.xFlip) {
					subX = 7 - subX;
				}
				if (attributes & CGBBGAttributes.yFlip) {
					subY = 7 - subY;
				}
				prospectivePixel = getTile(tile, true, !!(attributes & CGBBGAttributes.bank))[subX, subY];
				prospectivePalette = attributes & CGBBGAttributes.palette;
				prospectivePriority = !!(attributes & CGBBGAttributes.priority);
			} else {
				uint finalX = baseX + x;
				uint finalY = baseY;
				const tile = tilemapRow[(finalX / 8) % 32];
				const attributes = tilemapRowAttributes[(finalX / 8) % 32];
				auto subX = finalX % 8;
				auto subY = finalY % 8;
				if (attributes & CGBBGAttributes.xFlip) {
					subX = 7 - (subX % 8);
				}
				if (attributes & CGBBGAttributes.yFlip) {
					subY = 7 - (subY % 8);
				}
				prospectivePixel = getTile(tile, true, !!(attributes & CGBBGAttributes.bank))[subX % 8, subY % 8];
				prospectivePalette = attributes & CGBBGAttributes.palette;
				prospectivePriority = !!(attributes & CGBBGAttributes.priority);
			}
			// decide between sprite pixel and background pixel using priority settings
			if (highestMatchingSprite != size_t.max) {
				const sprite = oamSorted[highestMatchingSprite];
				auto xpos = x - (sprite.x - 8);
				auto ypos = (registers.ly - (sprite.y - 16));
				if (sprite.flags & OAMFlags.xFlip) {
					xpos = 7 - xpos;
				}
				if (sprite.flags & OAMFlags.yFlip) {
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
				const combinedPriority = ((!cgbMode || LCDCValue(registers.lcdc).bgEnabled) << 2) + (!!(sprite.flags & OAMFlags.priority) << 1) + prospectivePriority;
				if (objPriority[combinedPriority] || (prospectivePixel == 0)) {
					const pixel = getTile(cast(short)(sprite.tile + ypos / 8), false, cgbMode && !!(sprite.flags & OAMFlags.bank))[xpos, ypos % 8];
					if (pixel != 0) {
						prospectivePixel = pixel;
						prospectivePalette = 8 + (cgbMode ? (sprite.flags & OAMFlags.cgbPalette) : 0);
					}
				}
			}
			pixelRow[x] = getColour(prospectivePixel, prospectivePalette);
		}
		registers.ly++;
	}
	inout(ubyte)[] bank() inout @safe pure {
		return (cgbMode && registers.vbk) ? vram[0x2000 .. 0x4000] : vram[0x0000 .. 0x2000];
	}
	inout(ubyte)[] bgScreen() inout @safe pure {
		return (registers.lcdc & LCDCFlags.bgTilemap) ? screenB : screenA;
	}
	inout(ubyte)[] bgScreenCGB() inout @safe pure {
		return (registers.lcdc & LCDCFlags.bgTilemap) ? screenBCGB : screenACGB;
	}
	Array2D!(const ubyte) bgScreen2D() const @safe pure {
		return Array2D!(const ubyte)(32, 32, 32, bgScreen);
	}
	Array2D!(const ubyte) bgScreenCGB2D() const @safe pure {
		return Array2D!(const ubyte)(32, 32, 32, cgbMode ? bgScreenCGB : dmgExt[0 .. 0x400]);
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
		return (registers.lcdc & LCDCFlags.windowTilemap) ? screenB : screenA;
	}
	inout(ubyte)[] windowScreenCGB() inout @safe pure {
		return (registers.lcdc & LCDCFlags.windowTilemap) ? screenBCGB : screenACGB;
	}
	Array2D!(const ubyte) windowScreen2D() const @safe pure {
		return Array2D!(const ubyte)(32, 32, 32, windowScreen);
	}
	Array2D!(const ubyte) windowScreenCGB2D() const @safe pure {
		return Array2D!(const ubyte)(32, 32, 32, cgbMode ? windowScreenCGB : dmgExt[0 .. 0x400]);
	}
	BGR555 getColour(int b, int palette) const @safe pure {
		if (cgbMode) {
			return paletteRAM[palette * 4 + b];
		} else {
			const paletteMap = (registers.bgp >> (b * 2)) & 0x3;
			return gbPalette[paletteMap];
		}
	}
	Intertwined2BPP getTile(short id, bool useLCDC, ubyte bank) const @safe pure {
		auto blockA = (cgbMode && bank) ? tileBlockACGB : tileBlockA;
		auto blockB = (cgbMode && bank) ? tileBlockBCGB : tileBlockB;
		auto blockC = (cgbMode && bank) ? tileBlockCCGB : tileBlockC;
		const tileBlock = (id > 127) ? blockB : ((useLCDC && !(registers.lcdc & LCDCFlags.useAltBG) ? blockC : blockA));
		return (cast(const(Intertwined2BPP)[])(tileBlock[(id % 128) * 16 .. ((id % 128) * 16) + 16]))[0];
	}
	Intertwined2BPP getTileUnmapped(short id, ubyte bank) const @safe pure {
		return (cast(const(Intertwined2BPP)[])(vram[0x0000 + bank * 0x2000 .. 0x1800 + bank * 0x2000]))[id];
	}
	void beginDrawing(ubyte[] pixels, size_t stride) @safe pure {
		beginDrawing(Array2D!BGR555(width, height, cast(int)(stride / BGR555.sizeof), cast(BGR555[])pixels));
	}
	void beginDrawing(Array2D!BGR555 pixels) @safe pure {
		oamSorted = cast(OAMEntry[])oam;
		// optimization that can be enabled when the OAM is not modified mid-frame and is discarded at the end
		// allows priority to be determined just by picking the first matching entry instead of iterating the entire array
		version(assumeOAMImmutableDiscarded) {
			import std.algorithm.sorting : sort;
			sort!((a, b) => a.x < b.x)(oamSorted);
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
	void drawFullBackground(Array2D!BGR555 buffer) const @safe pure {
		drawDebugCommon(buffer, bgScreen2D, bgScreenCGB2D);
	}
	void drawFullWindow(Array2D!BGR555 buffer) const @safe pure {
		drawDebugCommon(buffer, windowScreen2D, windowScreenCGB2D);
	}
	void drawDebugCommon(Array2D!BGR555 buffer, const Array2D!(const ubyte) tiles, const Array2D!(const ubyte) attributes) const @safe pure {
		foreach (size_t tileX, size_t tileY, const ubyte tileID; tiles) {
			const tile = getTile(tileID, true, !!(attributes[tileX, tileY] & CGBBGAttributes.bank));
			foreach (subPixelX; 0 .. 8) {
				auto x = subPixelX;
				if (attributes[tileX, tileY] & CGBBGAttributes.xFlip) {
					x = 7 - x;
				}
				foreach (subPixelY; 0 .. 8) {
					auto y = subPixelY;
					if (attributes[tileX, tileY] & CGBBGAttributes.yFlip) {
						y = 7 - y;
					}
					buffer[tileX * 8 + subPixelX, tileY * 8 + subPixelY] = getColour(tile[x, y], attributes[tileX, tileY] & CGBBGAttributes.palette);
				}
			}
		}
	}
	void drawFullTileData(Array2D!BGR555 buffer) @safe pure
		in (buffer.dimensions[0] % 8 == 0, "Buffer width must be a multiple of 8")
		in (buffer.dimensions[1] % 8 == 0, "Buffer height must be a multiple of 8")
		in (buffer.dimensions[0] * buffer.dimensions[1] <= 384 * 8 * 8, "Buffer too small")
	{
		foreach (tileID; 0 .. 384) {
			const tileX = (tileID % (buffer.dimensions[0] / 8));
			const tileY = (tileID / (buffer.dimensions[0] / 8));
			const tile = getTileUnmapped(cast(short)tileID, 0);
			foreach (subPixelX; 0 .. 8) {
				foreach (subPixelY; 0 .. 8) {
					buffer[tileX * 8 + subPixelX, tileY * 8 + subPixelY] = getColour(tile[subPixelX, subPixelY], 0);
				}
			}
		}
	}
	void drawSprite(ubyte[] pixels, size_t stride, uint sprite) @safe pure {
		drawSprite(Array2D!BGR555(8, 16, cast(int)(stride / ushort.sizeof), cast(BGR555[])pixels), sprite);
	}
	void drawSprite(Array2D!BGR555 buffer, uint sprite) @safe pure {
		const tiles = 1 + !!(registers.lcdc & LCDCFlags.tallSprites);
		const oamEntry = (cast(OAMEntry[])oam)[sprite];
		foreach (tileID; 0 .. tiles) {
			const tile = getTile((oamEntry.tile + tileID) & 0xFF, false, !!(oamEntry.flags & OAMFlags.bank));
			foreach (x; 0 .. 8) {
				foreach (y; 0 .. 8) {
					const tileX = oamEntry.flags & OAMFlags.xFlip ? 7 - x : x;
					const tileY = oamEntry.flags & OAMFlags.yFlip ? height - 1 - y : y;
					const palette = 8 + (cgbMode ? (oamEntry.flags & OAMFlags.cgbPalette) : !!(oamEntry.flags & OAMFlags.dmgPalette));
					buffer[x, y + 8 * tileID] = getColour(tile[tileX, tileY], palette);
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
				registers.lcdc = val;
				break;
			case GameBoyRegister.STAT:
				registers.stat = val;
				break;
			case GameBoyRegister.BGP:
				registers.bgp = val;
				break;
			case GameBoyRegister.OBP0:
				registers.obp0 = val;
				break;
			case GameBoyRegister.OBP1:
				registers.obp1 = val;
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
				return registers.lcdc;
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
		static Array2D!BGR555 buffer = Array2D!BGR555(width, height);
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
				if (ImGui.TreeNode("LCDC", "LCDC: %02X", registers.lcdc)) {
					registerBit("BG+window enable", registers.lcdc, 0);
					ImGui.SetItemTooltip("If disabled, the BG and window layers will not be rendered.");
					registerBit("OBJ enable", registers.lcdc, 1);
					ImGui.SetItemTooltip("Whether or not sprites are enabled.");
					registerBitSel("OBJ size", registers.lcdc, 2, ["8x8", "8x16"]);
					ImGui.SetItemTooltip("The size of all sprites currently being rendered.");
					registerBitSel("BG tilemap area", registers.lcdc, 3, ["$9800", "$9C00"]);
					ImGui.SetItemTooltip("The region of VRAM where the BG tilemap is located.");
					registerBitSel("BG+Window tile area", registers.lcdc, 4, ["$8800", "$8000"]);
					ImGui.SetItemTooltip("The region of VRAM where the BG and window tile data is located.");
					registerBit("Window enable", registers.lcdc, 5);
					ImGui.SetItemTooltip("Whether or not the window layer is enabled.");
					registerBitSel("Window tilemap area", registers.lcdc, 6, ["$9800", "$9C00"]);
					ImGui.SetItemTooltip("The region of VRAM where the window tilemap is located.");
					registerBit("LCD+PPU enable", registers.lcdc, 7);
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
			if (cgbMode && ImGui.BeginTabItem("Palettes")) {
				showPalette(paletteRAM[], 4);
				ImGui.EndTabItem();
			}
			void showTileInfo(int x, int y) {
				ImGui.SetItemTooltip(format!"");
			}
			if (ImGui.BeginTabItem("Background")) {
				static void* surface;
				drawFullBackground(buffer);
				drawZoomableImage(buffer, video, surface, &showTileInfo);
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Window")) {
				static void* surface;
				drawFullWindow(buffer);
				drawZoomableImage(buffer, video, surface, &showTileInfo);
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Tiles")) {
				static void* surface;
				static allTilesBuffer = Array2D!BGR555(16 * 8, 24 * 8);
				drawFullTileData(allTilesBuffer);
				drawZoomableImage(allTilesBuffer, video, surface);
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("OAM")) {
				static void*[40] spriteSurfaces;
				static Array2D!BGR555[40] sprBuffers;
				const sprHeight = 8 * (1 + !!(registers.lcdc & LCDCFlags.tallSprites));
				enum sprWidth = 8;
				if (ImGui.BeginTable("oamTable", 8)) {
					foreach (idx, sprite; cast(OAMEntry[])oam) {
						ImGui.TableNextColumn();
						if (sprBuffers[idx] == Array2D!BGR555.init) {
							sprBuffers[idx] = Array2D!BGR555(8, 16);
						}
						auto sprBuffer = sprBuffers[idx][0 .. $, 0 .. sprHeight];
						if (spriteSurfaces[idx] is null) {
							spriteSurfaces[idx] = video.createSurface(sprBuffer);
						}
						drawSprite(sprBuffer, cast(uint)idx);
						video.setSurfacePixels(spriteSurfaces[idx], sprBuffer);
						ImGui.Image(spriteSurfaces[idx], ImVec2(sprWidth * 4.0, sprHeight * 4.0));
						if (ImGui.BeginItemTooltip()) {
							ImGui.Text("Coordinates: %d, %d", sprite.x, sprite.y);
							ImGui.Text("Tile: %d", sprite.tile);
							ImGui.Text("Orientation: ");
							ImGui.SameLine();
							ImGui.Text(["Normal", "Flipped horizontally", "Flipped vertically", "Flipped horizontally, vertically"][(sprite.flags >> 5) & 3]);
							ImGui.Text("Priority: ");
							ImGui.SameLine();
							ImGui.Text(["Normal", "High"][sprite.flags >> 7]);
							ImGui.Text("Palette: %d", cgbMode ? (sprite.flags & OAMFlags.cgbPalette) : ((sprite.flags >> 4) & 1));
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
		auto buffer = Array2D!BGR555(width, height);
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
					ppu.paletteRAM[0 .. 32] = cast(const(BGR555)[])data;
					break;
				case "ppu.cgbObjPalettes":
					ppu.paletteRAM[32 .. 64] = cast(const(BGR555)[])data;
					break;
				default:
					break;
			}
		});
		ppu.registers.lcdc = lcdc.raw;
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
immutable BGR555[] pocketPalette = [
	BGR555(31, 31, 31),
	BGR555(22, 22, 22),
	BGR555(13, 13, 13),
	BGR555(0, 0, 0)
];
immutable BGR555[] dmgPalette = [
	BGR555(blue: 19, green: 23, red: 1),
	BGR555(blue: 17, green: 21, red: 1),
	BGR555(blue: 6, green: 12, red: 6),
	BGR555(blue: 1, green: 7, red: 1)
];

module replatform64.gameboy.ppu;

import replatform64.backend.common.interfaces;
import replatform64.gameboy.common;

import replatform64.testhelpers;
import replatform64.ui;
import replatform64.util;

import std.algorithm.iteration;
import std.bitmanip : bitfields;
import std.range;

import tilemagic.tiles.bpp2;

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
	immutable(RGB555)[] gbPalette = pocketPalette;

	private Array2D!RGB555 pixels;
	private OAMEntry[] oamSorted;
	void runLine() @safe pure {
		const baseX = registers.scx;
		const baseY = registers.scy + registers.ly;
		auto pixelRow = pixels[0 .. $, registers.ly];
		const tilemapBase = ((baseY / 8) % fullTileWidth) * 32;
		const tilemapRow = bgScreen[tilemapBase .. tilemapBase + fullTileWidth];
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
						ypos = 7 - ypos;
					}
					// ignore transparent pixels
					if (getTile(cast(short)(sprite.tile + ypos / 8), false)[xpos, ypos % 8] == 0) {
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
			// grab pixel from background or window
			if ((registers.lcdc & LCDCFlags.windowDisplay) && (x >= registers.wx - 7) && (registers.ly >= registers.wy)) {
				const finalX = x - (registers.wx - 7);
				const finalY = registers.ly - registers.wy;
				const windowTilemapBase = (finalY / 8) * 32;
				const windowTilemapRow = windowScreen[windowTilemapBase .. windowTilemapBase + fullTileWidth];
				prospectivePixel = getTile(windowTilemapRow[finalX / 8], true)[finalX % 8, finalY % 8];
			} else {
				const finalX = baseX + x;
				prospectivePixel = getTile(tilemapRow[(finalX / 8) % 32], true)[finalX % 8, baseY % 8];
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
					ypos = 7 - ypos;
				}
				if (!(sprite.flags & OAMFlags.priority) || (prospectivePixel == 0)) {
					const pixel = getTile(cast(short)(sprite.tile + ypos / 8), false)[xpos, ypos % 8];
					if (pixel != 0) {
						prospectivePixel = pixel;
					}
				}
			}
			pixelRow[x] = getColour(prospectivePixel);
		}
		registers.ly++;
	}
	inout(ubyte)[] bgScreen() inout @safe pure {
		return (registers.lcdc & LCDCFlags.bgTilemap) ? screenB : screenA;
	}
	inout(ubyte)[] tileBlockA() inout @safe pure {
		return vram[0x8000 .. 0x8800];
	}
	inout(ubyte)[] tileBlockB() inout @safe pure {
		return vram[0x8800 .. 0x9000];
	}
	inout(ubyte)[] tileBlockC() inout @safe pure {
		return vram[0x9000 .. 0x9800];
	}
	inout(ubyte)[] screenA() inout @safe pure {
		return vram[0x9800 .. 0x9C00];
	}
	inout(ubyte)[] screenB() inout @safe pure {
		return vram[0x9C00 .. 0xA000];
	}
	inout(ubyte)[] oam() inout @safe pure {
		return vram[0xFE00 .. 0xFE00 + 40 * OAMEntry.sizeof];
	}
	inout(ubyte)[] windowScreen() inout @safe pure {
		return (registers.lcdc & LCDCFlags.windowTilemap) ? screenB : screenA;
	}
	RGB555 getColour(int b) const @safe pure {
		const paletteMap = (registers.bgp >> (b * 2)) & 0x3;
		return gbPalette[paletteMap];
	}
	Intertwined2BPP getTile(short id, bool useLCDC) const @safe pure {
		const tileBlock = (id > 127) ? tileBlockB : ((useLCDC && !(registers.lcdc & LCDCFlags.useAltBG) ? tileBlockC : tileBlockA));
		return (cast(const(Intertwined2BPP)[])(tileBlock[(id % 128) * 16 .. ((id % 128) * 16) + 16]))[0];
	}
	Intertwined2BPP getTileUnmapped(short id) const @safe pure {
		return (cast(const(Intertwined2BPP)[])(vram[0x8000 .. 0x9800]))[id];
	}
	void beginDrawing(ubyte[] pixels, size_t stride) @safe pure {
		oamSorted = cast(OAMEntry[])oam;
		// optimization that can be enabled when the OAM is not modified mid-frame and is discarded at the end
		// allows priority to be determined just by picking the first matching entry instead of iterating the entire array
		version(assumeOAMImmutableDiscarded) {
			import std.algorithm.sorting : sort;
			sort!((a, b) => a.x < b.x)(oamSorted);
		}
		registers.ly = 0;
		this.pixels = Array2D!RGB555(width, height, cast(int)(stride / ushort.sizeof), cast(RGB555[])pixels);
	}
	void drawFullFrame(ubyte[] pixels, size_t stride) @safe pure {
		beginDrawing(pixels, stride);
		foreach (i; 0 .. height) {
			runLine();
		}
	}
	void drawFullBackground(ubyte[] pixels, size_t stride) const @safe pure {
		auto buffer = Array2D!RGB555(256, 256, cast(int)(stride / ushort.sizeof), cast(RGB555[])pixels);
		foreach (size_t tileX, size_t tileY, ref const ubyte tileID; Array2D!(const ubyte)(32, 32, 32, bgScreen)) {
			const tile = getTile(tileID, true);
			foreach (subPixelX; 0 .. 8) {
				foreach (subPixelY; 0 .. 8) {
					buffer[tileX * 8 + subPixelX, tileY * 8 + subPixelY] = getColour(tile[subPixelX, subPixelY]);
				}
			}
		}
	}
	void drawFullWindow(ubyte[] pixels, size_t stride) @safe pure {
		auto buffer = Array2D!RGB555(256, 256, cast(int)(stride / ushort.sizeof), cast(RGB555[])pixels);
		foreach (size_t tileX, size_t tileY, ref const ubyte tileID; Array2D!(const ubyte)(32, 32, 32, windowScreen)) {
			const tile = getTile(tileID, true);
			foreach (subPixelX; 0 .. 8) {
				foreach (subPixelY; 0 .. 8) {
					buffer[tileX * 8 + subPixelX, tileY * 8 + subPixelY] = getColour(tile[subPixelX, subPixelY]);
				}
			}
		}
	}
	void drawFullTileData(Array2D!RGB555 buffer) @safe pure
		in (buffer.dimensions[0] % 8 == 0, "Buffer width must be a multiple of 8")
		in (buffer.dimensions[1] % 8 == 0, "Buffer height must be a multiple of 8")
		in (buffer.dimensions[0] * buffer.dimensions[1] <= 384 * 8 * 8, "Buffer too small")
	{
		foreach (tileID; 0 .. 384) {
			const tileX = (tileID % (buffer.dimensions[0] / 8));
			const tileY = (tileID / (buffer.dimensions[0] / 8));
			const tile = getTileUnmapped(cast(short)tileID);
			foreach (subPixelX; 0 .. 8) {
				foreach (subPixelY; 0 .. 8) {
					buffer[tileX * 8 + subPixelX, tileY * 8 + subPixelY] = getColour(tile[subPixelX, subPixelY]);
				}
			}
		}
	}
	void drawSprite(ubyte[] pixels, size_t stride, uint sprite) @safe pure {
		auto buffer = Array2D!RGB555(8, 8 * (1 + !!(registers.lcdc & LCDCFlags.tallSprites)), cast(int)(stride / ushort.sizeof), cast(RGB555[])pixels);
		const oamEntry = (cast(OAMEntry[])oam)[sprite];
		const tile = getTile(oamEntry.tile, false);
		foreach (x; 0 .. 8) {
			foreach (y; 0 .. 8) {
				const tileX = oamEntry.flags & OAMFlags.xFlip ? 7 - x : x;
				const tileY = oamEntry.flags & OAMFlags.yFlip ? 7 - y : y;
				buffer[x, y] = getColour(tile[tileX, tileY]);
			}
		}
	}
	void writeRegister(ushort addr, ubyte val) @safe pure {
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
		static void registerBit(string label, ref ubyte register, ubyte offset) {
			bool boolean = !!(register & (1 << offset));
			if (ImGui.Checkbox(label, &boolean)) {
				register = cast(ubyte)((register & ~(1 << offset)) | (boolean << offset));
			}
		}
		static void registerBitSel(size_t bits = 1, size_t opts = 1 << bits)(string label, ref ubyte register, ubyte offset, string[opts] labels) {
			const mask = (((1 << bits) - 1) << offset);
			size_t idx = (register & mask) >> offset;
			if (ImGui.BeginCombo(label, labels[idx])) {
				foreach (i, itemLabel; labels) {
					if (ImGui.Selectable(itemLabel, i == idx)) {
						register = cast(ubyte)((register & ~mask) | (i << offset));
					}
				}
				ImGui.EndCombo();
			}
		}
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
		static ushort[width * height] buffer;
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
			if (ImGui.BeginTabItem("Background")) {
				static void* backgroundSurface;
				if (backgroundSurface is null) {
					backgroundSurface = video.createSurface(width, height, ushort.sizeof * width, PixelFormat.rgb555);
				}
				drawFullBackground(cast(ubyte[])buffer[], width * ushort.sizeof);
				video.setSurfacePixels(backgroundSurface, cast(ubyte[])buffer[]);
				ImGui.Image(backgroundSurface, ImVec2(width, height));
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Window")) {
				static void* windowSurface;
				if (windowSurface is null) {
					windowSurface = video.createSurface(width, height, ushort.sizeof * width, PixelFormat.rgb555);
				}
				drawFullWindow(cast(ubyte[])buffer[], width * ushort.sizeof);
				video.setSurfacePixels(windowSurface, cast(ubyte[])buffer[]);
				ImGui.Image(windowSurface, ImVec2(width, height));
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Tiles")) {
				static size_t zoom = 1;
				if (ImGui.BeginCombo("Zoom", "1x")) {
					foreach (i, label; ["1x", "2x", "3x", "4x"]) {
						if (ImGui.Selectable(label, (i + 1) == zoom)) {
							zoom = i + 1;
						}
					}
					ImGui.EndCombo();
				}
				static void* windowSurface;
				static allTilesBuffer = Array2D!RGB555(16 * 8, 24 * 8);
				if (windowSurface is null) {
					windowSurface = video.createSurface(allTilesBuffer.dimensions[0], allTilesBuffer.dimensions[1], ushort.sizeof * allTilesBuffer.dimensions[0], PixelFormat.rgb555);
				}
				drawFullTileData(allTilesBuffer);
				video.setSurfacePixels(windowSurface, cast(ubyte[])allTilesBuffer[]);
				ImGui.Image(windowSurface, ImVec2(allTilesBuffer.dimensions[0] * zoom, allTilesBuffer.dimensions[1] * zoom));
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("OAM")) {
				static void*[40] spriteSurfaces;
				const sprHeight = 8 * (1 + !!(registers.lcdc & LCDCFlags.tallSprites));
				enum sprWidth = 8;
				if (ImGui.BeginTable("oamTable", 8)) {
					foreach (idx, sprite; cast(OAMEntry[])oam) {
						ImGui.TableNextColumn();
						if (spriteSurfaces[idx] is null) {
							spriteSurfaces[idx] = video.createSurface(sprWidth, sprHeight, ushort.sizeof * sprWidth, PixelFormat.rgb555);
						}
						auto sprBuffer = cast(ubyte[])(buffer[0 .. sprWidth * sprHeight]);
						drawSprite(sprBuffer, sprWidth * ushort.sizeof, cast(uint)idx);
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
							ImGui.Text("Palette: %d", (sprite.flags >> 4) & 1);
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
	import std.array : split;
	import std.conv : to;
	import std.file : exists, read, readText;
	import std.format : format;
	import std.path : buildPath;
	import std.string : lineSplitter;
	import std.stdio : File;
	enum width = 160;
	enum height = 144;
	static struct FauxDMA {
		ubyte scanline;
		GameBoyRegister register;
		ubyte value;
	}
	static Array2D!ABGR8888 draw(ref PPU ppu, FauxDMA[] dma = []) {
		auto buffer = new ushort[](width * height);
		enum pitch = width * 2;
		ppu.beginDrawing(cast(ubyte[])buffer, pitch);
		foreach (i; 0 .. height) {
			foreach (entry; dma) {
				if (i == entry.scanline) {
					ppu.writeRegister(entry.register, entry.value);
				}
			}
			ppu.runLine();
		}
		auto result = new uint[](width * height);
		immutable colourMap = [
			0x0000: 0xFF000000,
			0x35AD: 0xFF6B6B6B,
			0x5AD6: 0xFFB5B5B5,
			0x7FFF: 0xFFFFFFFF,
		];
		foreach (i, ref pixel; result) { //RGB555 -> ABGR8888
			if (buffer[i] !in colourMap) {
				import std.logger; infof("%04X", buffer[i]);
			}
			pixel = colourMap[buffer[i]];
		}
		return Array2D!ABGR8888(width, height, cast(ABGR8888[])result);
	}
	static Array2D!ABGR8888 renderMesen2State(const ubyte[] file, FauxDMA[] dma = []) {
		PPU ppu;
		ppu.vram = new ubyte[](0x10000);
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
			dumpPNG(frame, name~".png");
			assert(0, format!"Pixel mismatch at %s, %s in %s (got %s, expecting %s)"(result.x, result.y, name, result.got, result.expected));
		}
	}
	runTest("everythingok");
	runTest("ffl2");
	runTest("m2");
	runTest("w2");
	runTest("mqueen1");
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
immutable RGB555[] pocketPalette = [
	RGB555(31, 31, 31),
	RGB555(22, 22, 22),
	RGB555(13, 13, 13),
	RGB555(0, 0, 0)
];
immutable RGB555[] ogPalette = [
	RGB555(19, 23, 1),
	RGB555(17, 21, 1),
	RGB555(6, 12, 6),
	RGB555(1, 7, 1)
];
ushort tileAddr(ushort num, bool alt) {
	return alt ? cast(ushort)(0x9000 + cast(byte)num) : cast(ushort)(0x8000 + num);
}

ushort getPixel(ushort tile, int subX) @safe pure {
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

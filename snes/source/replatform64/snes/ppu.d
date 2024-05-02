module replatform64.snes.ppu;

/**
 * MIT License

Copyright (c) 2023 Herringway
Copyright (c) 2022 snesrev
Copyright (c) 2021 elzo_d

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE
*/

import replatform64.backend.common.interfaces;
import replatform64.common;
import replatform64.testhelpers;
import replatform64.snes.hardware;
import replatform64.ui;

import pixelatrix;

import std.algorithm.comparison;
import std.algorithm.mutation;
import std.bitmanip;
import std.format;
import std.range;

struct BGLayer {
	ushort hScroll = 0;
	ushort vScroll = 0;
	// -- snapshot starts here
	bool tilemapWider = false;
	bool tilemapHigher = false;
	ushort tilemapAdr = 0;
	// -- snapshot ends here
	ushort tileAdr = 0;
}

enum kPpuExtraLeftRight = 88;

enum {
	kPpuXPixels = 256 + kPpuExtraLeftRight * 2,
};

alias PpuZbufType = ushort;

struct PpuPixelPrioBufs {
	// This holds the prio in the upper 8 bits and the color in the lower 8 bits.
	PpuZbufType[kPpuXPixels] data;
}

int IntMin(int a, int b) @safe pure { return a < b ? a : b; }
int IntMax(int a, int b) @safe pure { return a > b ? a : b; }
uint UintMin(uint a, uint b) @safe pure { return a < b ? a : b; }

enum KPPURenderFlags {
	newRenderer = 1,
	// Render mode7 upsampled by 4x4
	mode74x4 = 2,
	// Use 240 height instead of 224
	height240 = 4,
	// Disable sprite render limits
	noSpriteLimits = 8,
}

struct Tile {
	align(1):
	mixin(bitfields!(
		uint, "chr", 10,
		uint, "palette", 3,
		bool, "priority", 1,
		bool, "hFlip", 1,
		bool, "vFlip", 1,
	));
	void toString(R)(ref R sink) const {
		import std.format : formattedWrite;
		sink.formattedWrite!"%s%s%s%s%03X"(vFlip ? "V" : "v", hFlip ? "H" : "h", priority ? "P" : "p", palette, chr);
	}
}

struct PPU {
	bool lineHasSprites;
	ubyte lastBrightnessMult = 0xff;
	ubyte lastMosaicModulo = 0xff;
	ubyte renderFlags;
	uint renderPitch;
	uint[] renderBuffer;
	ubyte extraLeftCur = 0;
	ubyte extraRightCur = 0;
	ubyte extraLeftRight = 0;
	ubyte extraBottomCur = 0;
	float mode7PerspectiveLow, mode7PerspectiveHigh;
	bool interlacing;

	// TMW / TSW etc
	ubyte[2] screenEnabled;
	ubyte[2] screenWindowed;
	ubyte mosaicEnabled;
	ubyte mosaicSize = 1;
	// object/sprites
	ushort objTileAdr1 = 0x4000;
	ushort objTileAdr2 = 0x5000;
	ubyte objSize = 0;
	// Window
	ubyte window1left = 0;
	ubyte window1right = 0;
	ubyte window2left = 0;
	ubyte window2right = 0;
	uint windowsel = 0;

	// color math
	ubyte clipMode = 0;
	ubyte preventMathMode = 0;
	bool addSubscreen = false;
	bool subtractColor = false;
	bool halfColor = false;
	ubyte mathEnabled = 0;
	ubyte fixedColorR = 0;
	ubyte fixedColorG = 0;
	ubyte fixedColorB = 0;
	// settings
	bool forcedBlank = true;
	ubyte brightness = 0;
	ubyte mode = 0;

	// vram access
	ushort vramPointer = 0;
	ushort vramIncrement = 1;
	bool vramIncrementOnHigh = false;
	// cgram access
	ubyte cgramPointer = 0;
	bool cgramSecondWrite = false;
	ubyte cgramBuffer = 0;
	// oam access
	ushort oamAdr = 0;
	bool oamSecondWrite = false;
	ubyte oamBuffer = 0;

	// background layers
	BGLayer[4] bgLayer;
	ubyte scrollPrev = 0;
	ubyte scrollPrev2 = 0;

	// mode 7
	short[8] m7matrix; // a, b, c, d, x, y, h, v
	ubyte m7prev = 0;
	bool m7largeField = true;
	bool m7charFill = false;
	bool m7xFlip = false;
	bool m7yFlip = false;
	bool m7extBg_always_zero = false;
	// mode 7 internal
	int m7startX = 0;
	int m7startY = 0;

	ushort[0x110] oam;

	// store 31 extra entries to remove the need for clamp
	ubyte[32 + 31] brightnessMult;
	ubyte[32 * 2] brightnessMultHalf;
	ushort[0x100] cgram;
	ubyte[kPpuXPixels] mosaicModulo;
	uint[256] colorMapRgb;
	PpuPixelPrioBufs[2] bgBuffers;
	PpuPixelPrioBufs objBuffer;
	ushort[0x8000] vram;

	int getCurrentRenderScale(uint render_flags) @safe pure {
		bool hq = mode == 7 && !forcedBlank && (render_flags & (KPPURenderFlags.mode74x4 | KPPURenderFlags.newRenderer)) == (KPPURenderFlags.mode74x4 | KPPURenderFlags.newRenderer);
		return hq ? 4 : 1;
	}

	void beginDrawing(ubyte[] pixels, size_t pitch, uint render_flags) @safe pure {
		renderFlags = cast(ubyte)render_flags;
		renderPitch = cast(uint)pitch / uint.sizeof;
		renderBuffer = cast(uint[])pixels;

		// Cache the brightness computation
		if (brightness != lastBrightnessMult) {
			ubyte ppu_brightness = brightness;
			lastBrightnessMult = ppu_brightness;
			for (int i = 0; i < 32; i++) {
				brightnessMultHalf[i * 2] = brightnessMultHalf[i * 2 + 1] = brightnessMult[i] = cast(ubyte)(((i << 3) | (i >> 2)) * ppu_brightness / 15);
			}
			// Store 31 extra entries to remove the need for clamping to 31.
			brightnessMult[32 .. 63] = brightnessMult[31];
		}

		if (getCurrentRenderScale(renderFlags) == 4) {
			for (int i = 0; i < colorMapRgb.length; i++) {
				uint color = cgram[i];
				colorMapRgb[i] = brightnessMult[color & 0x1f] << 16 | brightnessMult[(color >> 5) & 0x1f] << 8 | brightnessMult[(color >> 10) & 0x1f];
			}
		}
	}

	private void ClearBackdrop(ref PpuPixelPrioBufs buf) @safe pure {
		(cast(ulong[])buf.data)[] = 0x0500050005000500;
	}


	void runLine(int line) @safe pure {
		if(line != 0) {
			if (mosaicSize != lastMosaicModulo) {
				int mod = mosaicSize;
				lastMosaicModulo = cast(ubyte)mod;
				for (int i = 0, j = 0; i < mosaicModulo.length; i++) {
					mosaicModulo[i] = cast(ubyte)(i - j);
					j = (j + 1 == mod ? 0 : j + 1);
				}
			}
			// evaluate sprites
			ClearBackdrop(objBuffer);
			lineHasSprites = !forcedBlank && evaluateSprites(line - 1);

			// outside of visible range?
			if (line >= 225 + extraBottomCur) {
				renderBuffer[(line - 1) * renderPitch .. (line - 1) * renderPitch + (256 + extraLeftRight * 2)] = 0;
				return;
			}

			if (renderFlags & KPPURenderFlags.newRenderer) {
				drawWholeLine(line);
			} else {
				if (mode == 7) {
					calculateMode7Starts(line);
				}
				for (int x = 0; x < 256; x++) {
					handlePixel(x, line);
				}

				uint[] dst = renderBuffer[(line - 1) * renderPitch .. $];
				if (extraLeftRight != 0) {
					dst[0 .. extraLeftRight] = 0;
					dst[256 + extraLeftRight .. 257 + extraLeftRight] = 0;
				}
			}
		}
	}

	private void windowsClear(ref PpuWindows win, uint layer) @safe pure {
		win.edges[0] = -(layer != 2 ? extraLeftCur : 0);
		win.edges[1] = 256 + (layer != 2 ? extraRightCur : 0);
		win.nr = 1;
		win.bits = 0;
	}

	private void windowsCalc(ref PpuWindows win, uint layer) const @safe pure {
		// Evaluate which spans to render based on the window settings.
		// There are at most 5 windows.
		// Algorithm from Snes9x
		uint winflags = GET_WINDOW_FLAGS(layer);
		uint nr = 1;
		int window_right = 256 + (layer != 2 ? extraRightCur : 0);
		win.edges[0] = - (layer != 2 ? extraLeftCur : 0);
		win.edges[1] = cast(short)window_right;
		uint i, j;
		int t;
		bool w1_ena = (winflags & kWindow1Enabled) && window1left <= window1right;
		if (w1_ena) {
			if (window1left > win.edges[0]) {
				win.edges[nr] = window1left;
				win.edges[++nr] = cast(short)window_right;
			}
			if (window1right + 1 < window_right) {
				win.edges[nr] = window1right + 1;
				win.edges[++nr] = cast(short)window_right;
			}
		}
		bool w2_ena = (winflags & kWindow2Enabled) && window2left <= window2right;
		if (w2_ena) {
			for (i = 0; i <= nr && (t = window2left) != win.edges[i]; i++) {
				if (t < win.edges[i]) {
					for (j = nr++; j >= i; j--) {
						win.edges[j + 1] = win.edges[j];
					}
					win.edges[i] = cast(short)t;
					break;
				}
			}
			for (; i <= nr && (t = window2right + 1) != win.edges[i]; i++) {
				if (t < win.edges[i]) {
					for (j = nr++; j >= i; j--) {
						win.edges[j + 1] = win.edges[j];
					}
					win.edges[i] = cast(short)t;
					break;
				}
			}
		}
		win.nr = cast(ubyte)nr;
		// get a bitmap of how regions map to windows
		ubyte w1_bits = 0, w2_bits = 0;
		if (w1_ena) {
			for (i = 0; win.edges[i] != window1left; i++) {}
			for (j = i; win.edges[j] != window1right + 1; j++) {}
			w1_bits = cast(ubyte)(((1 << (j - i)) - 1) << i);
		}
		if ((winflags & (kWindow1Enabled | kWindow1Inversed)) == (kWindow1Enabled | kWindow1Inversed)) {
			w1_bits = cast(ubyte)~w1_bits;
		}
		if (w2_ena) {
			for (i = 0; win.edges[i] != window2left; i++) {}
			for (j = i; win.edges[j] != window2right + 1; j++) {}
			w2_bits = cast(ubyte)(((1 << (j - i)) - 1) << i);
		}
		if ((winflags & (kWindow2Enabled | kWindow2Inversed)) == (kWindow2Enabled | kWindow2Inversed)) {
			w2_bits = cast(ubyte)~w2_bits;
		}
		win.bits = w1_bits | w2_bits;
	}
	private Array2D!(const Tile)[4] getBackgroundTilemaps(uint layer) const return @safe pure {
		static immutable tilemapOffsets = [
			[0x000, 0x000, 0x000, 0x000],
			[0x000, 0x400, 0x000, 0x400],
			[0x000, 0x000, 0x400, 0x400],
			[0x000, 0x400, 0x800, 0xC00],
		];
		alias Tilemap = Array2D!(const Tile);
		const base = bgLayer[layer].tilemapAdr;
		const offsets = tilemapOffsets[bgLayer[layer].tilemapWider + bgLayer[layer].tilemapHigher * 2];
		return [
			Tilemap(32, 32, cast(const(Tile)[])vram[base + offsets[0] .. $][0 .. 32 * 32]),
			Tilemap(32, 32, cast(const(Tile)[])vram[base + offsets[1] .. $][0 .. 32 * 32]),
			Tilemap(32, 32, cast(const(Tile)[])vram[base + offsets[2] .. $][0 .. 32 * 32]),
			Tilemap(32, 32, cast(const(Tile)[])vram[base + offsets[3] .. $][0 .. 32 * 32]),
		];
	}
	// Draw a whole line of a background layer into bgBuffers
	private void drawBackground(size_t bpp)(uint y, bool sub, uint layer, PpuZbufType zhi, PpuZbufType zlo) @safe pure {
		if (!IS_SCREEN_ENABLED(sub, layer)) {
			return; // layer is completely hidden
		}
		PpuWindows win;
		IS_SCREEN_WINDOWED(sub, layer) ? windowsCalc(win, layer) : windowsClear(win, layer);
		const bglayer = &bgLayer[layer];
		const tilemaps = getBackgroundTilemaps(layer);
		static if (bpp == 2) {
			alias TileType = Intertwined2BPP;
		} else static if (bpp == 4) {
			alias TileType = Intertwined4BPP;
		} else static if (bpp == 8) {
			alias TileType = Intertwined8BPP;
		}
		auto tiles = (cast(const(TileType)[])vram).cycle[(bgLayer[layer].tileAdr * 2) / TileType.sizeof .. (bgLayer[layer].tileAdr * 2) / TileType.sizeof + 0x400];
		y = mosaicModulo[y] + bglayer.vScroll;
		for (size_t windex = 0; windex < win.nr; windex++) {
			if (win.bits & (1 << windex)) {
				continue; // layer is disabled for this window part
			}
			uint x = win.edges[windex] + bglayer.hScroll;
			uint w = win.edges[windex + 1] - win.edges[windex];
			PpuZbufType[] dstz = bgBuffers[sub].data[win.edges[windex] + kPpuExtraLeftRight .. $];
			const tileLine = (y / 8) % 32;
			const tileMap = ((y >> 8) & 1) * 2;
			auto tp = tilemaps[tileMap][0 .. $, tileLine].chain(tilemaps[tileMap + 1][0 .. $, tileLine]).cycle.drop((x / 8) & 0x3F).take(w);
			void renderTile(Tile tile, const uint start, uint end) {
				const z = cast(ushort)((tile.priority ? zhi : zlo) + (tile.palette << bpp));
				foreach (i; 8 - start .. end) {
					ubyte tileX = cast(ubyte)i;
					ubyte tileY = y % 8;
					if (tile.hFlip) {
						tileX = cast(ubyte)(7 - tileX);
					}
					if (tile.vFlip) {
						tileY = cast(ubyte)(7 - tileY);
					}
					const pixel = tiles[tile.chr][tileX, tileY];
					if (pixel && (z > dstz[i - (8 - start)])) {
						dstz[i - (8 - start)] = cast(ushort)(z + pixel);
					}
				}
			}
			while (w >= 8) {
				const start = 8 - (x & 7);
				const tile = tp[0];
				const end = 8;
				renderTile(tp[0], start, 8);
				dstz = dstz[start .. $];
				tp = tp[1 .. $];
				w -= start;
				x += start;
			}
			if (w & 7) {
				renderTile(tp[0], 8, w & 7);
			}
		}
	}

	// Draw a whole line of a background layer into bgBuffers, with mosaic applied
	private void drawBackgroundMosaic(size_t bpp)(uint y, bool sub, uint layer, PpuZbufType zhi, PpuZbufType zlo) @safe pure {
		static if (bpp == 2) {
			enum kPaletteShift = 8;
		} else static if (bpp == 4) {
			enum kPaletteShift = 6;
		} else static if (bpp == 8) {
			enum kPaletteShift = 12;
		}
		if (!IS_SCREEN_ENABLED(sub, layer)) {
			return; // layer is completely hidden
		}
		PpuWindows win;
		IS_SCREEN_WINDOWED(sub, layer) ? windowsCalc(win, layer) : windowsClear(win, layer);
		BGLayer *bglayer = &bgLayer[layer];
		y = mosaicModulo[y] + bglayer.vScroll;
		int sc_offs = bglayer.tilemapAdr + (((y >> 3) & 0x1f) << 5);
		if ((y & 0x100) && bglayer.tilemapHigher) {
			sc_offs += bglayer.tilemapWider ? 0x800 : 0x400;
		}
		const(ushort)[] tps(uint i) {
			return [
				vram[sc_offs & 0x7fff .. $],
				vram[sc_offs + (bglayer.tilemapWider ? 0x400 : 0) & 0x7fff .. $]
			][i];
		}
		int tileadr = bgLayer[layer].tileAdr;
		int pixel;
		int tileadr1 = tileadr + 7 - (y & 0x7);
		int tileadr0 = tileadr + (y & 0x7);
		const(ushort)[] addr;
		ulong READ_BITS(uint ta, uint tile) {
			ulong result;
			addr = vram[(ta + tile * bpp * 4) & 0x7FFF .. $];
			static foreach (plane; 0 .. bpp / 2) {
				result |= cast(ulong)addr[plane * 8] << (plane * 16);
			}
			return result;
		}
		for (size_t windex = 0; windex < win.nr; windex++) {
			if (win.bits & (1 << windex)) {
				continue; // layer is disabled for this window part
			}
			int sx = win.edges[windex];
			PpuZbufType[] dstz = bgBuffers[sub].data[sx + kPpuExtraLeftRight .. win.edges[windex + 1] + kPpuExtraLeftRight];
			uint x = sx + bglayer.hScroll;
			const(ushort)[] tp_next = tps((x >> 8 & 1) ^ 1);
			const(ushort)[] tp = tps(x >> 8 & 1)[(x >> 3) & 0x1f .. 32];
			ulong bits;
			PpuZbufType z;
			void DO_PIXEL(int i)() {
				pixel = 0;
				static foreach (plane; 0 .. bpp) {
					pixel |= (bits >> (7 * plane + i)) & (1 << plane);
				}
				if (pixel && (z > dstz[i])) {
					dstz[i] = cast(ushort)(z + pixel);
				}
			}
			void DO_PIXEL_HFLIP(int i)() {
				pixel = 0;
				static foreach (plane; 0 .. bpp) {
					pixel |= (bits >> (7 * (plane + 1) - i)) & (1 << plane);
				}
				if (pixel && z > dstz[i]) {
					dstz[i] = cast(ushort)(z + pixel);
				}
			}
			x &= 7;
			int w = mosaicSize - (sx - mosaicModulo[sx]);
			do {
				w = IntMin(w, cast(int)dstz.length);
				uint tile = tp[0];
				int ta = (tile & 0x8000) ? tileadr1 : tileadr0;
				z = (tile & 0x2000) ? zhi : zlo;
				bits = READ_BITS(ta, tile & 0x3ff);
				if (tile & 0x4000) {
					bits >>= x;
					DO_PIXEL!(0);
				} else {
					bits <<= x;
					DO_PIXEL_HFLIP!(0);
				}
				if (pixel) {
					pixel += (tile & 0x1c00) >> kPaletteShift;
					int i = 0;
					do {
						if (z > dstz[i]) {
							dstz[i] = cast(ushort)(pixel + z);
						}
					} while (++i != w);
				}
				dstz = dstz[w .. $];
				x += w;
				for (; x >= 8; x -= 8) {
					tp = (tp.length > 1) ? tp[1 .. $] : tp_next;
				}
				w = mosaicSize;
			} while (dstz.length != 0);
		}
	}

	// level6 should be set if it's from palette 0xc0 which means color math is not applied
	uint SPRITE_PRIO_TO_PRIO(uint prio, bool level6) @safe pure {
		return SPRITE_PRIO_TO_PRIO_HI(prio) * 16 + 4 + (level6 ? 2 : 0);
	}
	uint SPRITE_PRIO_TO_PRIO_HI(uint prio) @safe pure {
		return (prio + 1) * 3;
	}

	private void drawSprites(uint y, uint sub, bool clear_backdrop) @safe pure {
		int layer = 4;
		if (!IS_SCREEN_ENABLED(sub, layer)) {
			return; // layer is completely hidden
		}
		PpuWindows win;
		IS_SCREEN_WINDOWED(sub, layer) ? windowsCalc(win, layer) : windowsClear(win, layer);
		for (size_t windex = 0; windex < win.nr; windex++) {
			if (win.bits & (1 << windex)) {
				continue; // layer is disabled for this window part
			}
			int left = win.edges[windex];
			int width = win.edges[windex + 1] - left;
			PpuZbufType[] src = objBuffer.data[left + kPpuExtraLeftRight .. $];
			PpuZbufType[] dst = bgBuffers[sub].data[left + kPpuExtraLeftRight .. $];
			if (clear_backdrop) {
				dst[0 .. min($, width * ushort.sizeof)] = src[0 .. min($, width * ushort.sizeof)];
			} else {
				do {
					if (src[0] > dst[0]) {
						dst[0] = src[0];
					}
					src = src[1 .. $];
					dst = dst[1 .. $];
				} while (--width);
			}
		}
	}

	// Assumes it's drawn on an empty backdrop
	private void drawBackgroundMode7(uint y, bool sub, PpuZbufType z) @safe pure {
		int layer = 0;
		if (!IS_SCREEN_ENABLED(sub, layer)) {
			return; // layer is completely hidden
		}
		PpuWindows win;
		IS_SCREEN_WINDOWED(sub, layer) ? windowsCalc(win, layer) : windowsClear(win, layer);

		// expand 13-bit values to signed values
		int hScroll = (cast(short)(m7matrix[6] << 3)) >> 3;
		int vScroll = (cast(short)(m7matrix[7] << 3)) >> 3;
		int xCenter = (cast(short)(m7matrix[4] << 3)) >> 3;
		int yCenter = (cast(short)(m7matrix[5] << 3)) >> 3;
		int clippedH = hScroll - xCenter;
		int clippedV = vScroll - yCenter;
		clippedH = (clippedH & 0x2000) ? (clippedH | ~1023) : (clippedH & 1023);
		clippedV = (clippedV & 0x2000) ? (clippedV | ~1023) : (clippedV & 1023);
		bool mosaic_enabled = IS_MOSAIC_ENABLED(0);
		if (mosaic_enabled) {
			y = mosaicModulo[y];
		}
		uint ry = m7yFlip ? 255 - y : y;
		uint m7startX = (m7matrix[0] * clippedH & ~63) + (m7matrix[1] * ry & ~63) +
			(m7matrix[1] * clippedV & ~63) + (xCenter << 8);
		uint m7startY = (m7matrix[2] * clippedH & ~63) + (m7matrix[3] * ry & ~63) +
			(m7matrix[3] * clippedV & ~63) + (yCenter << 8);
		for (size_t windex = 0; windex < win.nr; windex++) {
			if (win.bits & (1 << windex)) {
				continue; // layer is disabled for this window part
			}
			int x = win.edges[windex], x2 = win.edges[windex + 1], tile;
			PpuZbufType[] dstz = bgBuffers[sub].data[x + kPpuExtraLeftRight .. x2 + kPpuExtraLeftRight];
			uint rx = m7xFlip ? 255 - x : x;
			uint xpos = m7startX + m7matrix[0] * rx;
			uint ypos = m7startY + m7matrix[2] * rx;
			uint dx = m7xFlip ? -m7matrix[0] : m7matrix[0];
			uint dy = m7xFlip ? -m7matrix[2] : m7matrix[2];
			uint outside_value = m7largeField ? 0x3ffff : 0xffffffff;
			bool char_fill = m7charFill;
			if (mosaic_enabled) {
				int w = mosaicSize - (x - mosaicModulo[x]);
				do {
					w = IntMin(w, cast(int)dstz.length);
					if (cast(uint)(xpos | ypos) > outside_value) {
						if (!char_fill) {
							break;
						}
						tile = 0;
					} else {
						tile = vram[(ypos >> 11 & 0x7f) * 128 + (xpos >> 11 & 0x7f)] & 0xff;
					}
					ubyte pixel = vram[tile * 64 + (ypos >> 8 & 7) * 8 + (xpos >> 8 & 7)] >> 8;
					if (pixel) {
						int i = 0;
						do {
							dstz[i] = cast(ushort)(pixel + z);
						} while (++i != w);
					}
					xpos += dx * w;
					ypos += dy * w;
					dstz = dstz[w .. $];
					w = mosaicSize;
				} while (dstz.length > 0);
			} else {
				do {
					if (cast(uint)(xpos | ypos) > outside_value) {
						if (!char_fill) {
							break;
						}
						tile = 0;
					} else {
						tile = vram[(ypos >> 11 & 0x7f) * 128 + (xpos >> 11 & 0x7f)] & 0xff;
					}
					ubyte pixel = vram[tile * 64 + (ypos >> 8 & 7) * 8 + (xpos >> 8 & 7)] >> 8;
					if (pixel) {
						dstz[0] = cast(ushort)(pixel + z);
					}
					xpos += dx;
					ypos += dy;
					dstz = dstz[1 .. $];
				} while (dstz.length > 0);
			}
		}
	}

	void setMode7PerspectiveCorrection(int low, int high) @safe pure {
		mode7PerspectiveLow = low ? 1.0f / low : 0.0f;
		mode7PerspectiveHigh = 1.0f / high;
	}

	void setExtraSideSpace(int left, int right, int bottom) @safe pure {
		extraLeftCur = cast(ubyte)UintMin(left, extraLeftRight);
		extraRightCur = cast(ubyte)UintMin(right, extraLeftRight);
		extraBottomCur = cast(ubyte)UintMin(bottom, 16);
	}

	private float FloatInterpolate(float x, float xmin, float xmax, float ymin, float ymax) @safe pure {
		return ymin + (ymax - ymin) * (x - xmin) * (1.0f / (xmax - xmin));
	}

	// Upsampled version of mode7 rendering. Draws everything in 4x the normal resolution.
	// Draws directly to the pixel buffer and bypasses any math, and supports only
	// a subset of the normal features (all that zelda needs)
	private void drawMode7Upsampled(uint y) @safe pure {
		// expand 13-bit values to signed values
		uint xCenter = (cast(short)(m7matrix[4] << 3)) >> 3, yCenter = (cast(short)(m7matrix[5] << 3)) >> 3;
		uint clippedH = ((cast(short)(m7matrix[6] << 3)) >> 3) - xCenter;
		uint clippedV = ((cast(short)(m7matrix[7] << 3)) >> 3) - yCenter;
		int[4] m0v;
		if (*cast(uint*)&mode7PerspectiveLow == 0) {
			m0v[0] = m0v[1] = m0v[2] = m0v[3] = m7matrix[0] << 12;
		} else {
			static const float[4] kInterpolateOffsets = [ -1, -1 + 0.25f, -1 + 0.5f, -1 + 0.75f ];
			for (int i = 0; i < 4; i++) {
				m0v[i] = cast(int)(4096.0f / FloatInterpolate(cast(int)y + kInterpolateOffsets[i], 0, 223, mode7PerspectiveLow, mode7PerspectiveHigh));
			}
		}
		size_t pitch = renderPitch;
		uint[] render_buffer_ptr = renderBuffer[(y - 1) * 4 * pitch .. $];
		uint[] dst_start = render_buffer_ptr[(extraLeftRight - extraLeftCur) * 4 .. $];
		size_t draw_width = 256 + extraLeftCur + extraRightCur;
		uint[] dst_curline = dst_start;
		uint m1 = m7matrix[1] << 12; // xpos increment per vert movement
		uint m2 = m7matrix[2] << 12; // ypos increment per horiz movement
		for (int j = 0; j < 4; j++) {
			uint m0 = m0v[j], m3 = m0;
			uint xpos = m0 * clippedH + m1 * (clippedV + y) + (xCenter << 20), xcur;
			uint ypos = m2 * clippedH + m3 * (clippedV + y) + (yCenter << 20), ycur;

			uint tile, pixel;
			xpos -= (m0 + m1) >> 1;
			ypos -= (m2 + m3) >> 1;
			xcur = (xpos << 2) + j * m1;
			ycur = (ypos << 2) + j * m3;

			xcur -= extraLeftCur * 4 * m0;
			ycur -= extraLeftCur * 4 * m2;

			uint[] dst = dst_curline[0 .. draw_width * 4];

			void DRAW_PIXEL(int mode) {
				tile = vram[(ycur >> 25 & 0x7f) * 128 + (xcur >> 25 & 0x7f)] & 0xff;
				pixel = vram[tile * 64 + (ycur >> 22 & 7) * 8 + (xcur >> 22 & 7)] >> 8;
				pixel = (xcur & 0x80000000) ? 0 : pixel;
				dst[0] = (mode ? (colorMapRgb[pixel] & 0xfefefe) >> 1 : colorMapRgb[pixel]);
				xcur += m0;
				ycur += m2;
				dst = dst[1 .. $];
			}

			if (!halfColor) {
				do {
					DRAW_PIXEL(0);
					DRAW_PIXEL(0);
					DRAW_PIXEL(0);
					DRAW_PIXEL(0);
				} while (dst.length > 0);
			} else {
				do {
					DRAW_PIXEL(1);
					DRAW_PIXEL(1);
					DRAW_PIXEL(1);
					DRAW_PIXEL(1);
				} while (dst.length > 0);
			}

			dst_curline = dst_curline[pitch .. $];
		}

		if (lineHasSprites) {
			uint[] dst = dst_start;
			PpuZbufType[] pixels = objBuffer.data[kPpuExtraLeftRight - extraLeftCur .. $];
			for (size_t i = 0; i < draw_width; i++, dst = dst[16 .. $]) {
				uint pixel = pixels[i] & 0xff;
				if (pixel) {
					uint color = colorMapRgb[pixel];
					dst[pitch * 0 .. pitch * 0 + 4][] = color;
					dst[pitch * 1 .. pitch * 1 + 4][] = color;
					dst[pitch * 2 .. pitch * 2 + 4][] = color;
					dst[pitch * 3 .. pitch * 3 + 4][] = color;
				}
			}
		}

		if (extraLeftRight - extraLeftCur != 0) {
			size_t n = 4 * uint.sizeof * (extraLeftRight - extraLeftCur);
			for(int i = 0; i < 4; i++) {
				render_buffer_ptr[pitch * i .. pitch * i + n] = 0;
			}
		}
		if (extraLeftRight - extraRightCur != 0) {
			size_t n = 4 * uint.sizeof * (extraLeftRight - extraRightCur);
			for (int i = 0; i < 4; i++) {
				const start = pitch * i + (256 + extraLeftRight * 2 - (extraLeftRight - extraRightCur)) * 4 * uint.sizeof;
				render_buffer_ptr[start .. start + n] = 0;
			}
		}
	}

	private void drawBackgrounds(int y, bool sub) @safe pure {
		// Top 4 bits contain the prio level, and bottom 4 bits the layer num
		// split into minimums and maximums
		enum ushort[2][4][8] priorityTable = [
			0: [[11, 8], [10, 7], [5, 2], [4, 1]],
			1: [[11, 8], [10, 7], [12, 1], [0, 0]],
			2: [[11, 5], [8, 2], [0, 0], [0, 0]],
			3: [[11, 5], [8, 2], [0, 0], [0, 0]],
			4: [[11, 5], [8, 2], [0, 0], [0, 0]],
			5: [[11, 5], [8, 2], [0, 0], [0, 0]],
			6: [[11, 5], [0, 0], [0, 0], [0, 0]],
			7: [[11, 5], [0, 0], [0, 0], [0, 0]],
		];
		enum int[4][8] bgBPP = [
			0: [2, 2, 2, 2],
			1: [4, 4, 2, 0],
			2: [4, 4, 0, 0],
			3: [8, 4, 0, 0],
			4: [8, 2, 0, 0],
			5: [4, 2, 0, 0],
			6: [4, 0, 0, 0],
			7: [8, 0, 0, 0],
		];

		if (lineHasSprites) {
			drawSprites(y, sub, mode != 7);
		}
		sw: switch (mode) {
			static foreach (i; 0 .. 7) {
				case i:
					static foreach (layer; 0 .. 4) {{
						enum bpp = bgBPP[i][layer];
						static if (bpp > 0) {
							enum priorityHigh = (priorityTable[i][layer][0] << 12) | (layer << 8);
							enum priorityLow = (priorityTable[i][layer][1] << 12) | (layer << 8);
							if (IS_MOSAIC_ENABLED(layer)) {
								drawBackgroundMosaic!bpp(y, sub, layer, priorityHigh, priorityLow);
							} else {
								drawBackground!bpp(y, sub, layer, priorityHigh, priorityLow);
							}
						}
					}}
					break sw;
			}
			case 7:
				drawBackgroundMode7(y, sub, 0xc000);
				break;
			default:
				assert(0);
		}
	}

	private void drawWholeLine(uint y) @safe pure {
		if (forcedBlank) {
			uint[] dst = renderBuffer[(y - 1) * renderPitch .. $];
			dst[] = 0;
			return;
		}

		if (mode == 7 && (renderFlags & KPPURenderFlags.mode74x4)) {
			drawMode7Upsampled(y);
			return;
		}

		// Default background is backdrop
		ClearBackdrop(bgBuffers[0]);

		// Render main screen
		drawBackgrounds(y, false);

		// The 6:th bit is automatically zero, math is never applied to the first half of the sprites.
		uint math_enabled = mathEnabled;

		// Render also the subscreen?
		bool rendered_subscreen = false;
		if (preventMathMode != 3 && addSubscreen && math_enabled) {
			ClearBackdrop(bgBuffers[1]);
			if (screenEnabled[1] != 0) {
				drawBackgrounds(y, true);
				rendered_subscreen = true;
			}
		}

		// Color window affects the drawing mode in each region
		PpuWindows cwin;
		windowsCalc(cwin, 5);
		static const ubyte[8] kCwBitsMod = [
			0x00, 0xff, 0xff, 0x00,
			0xff, 0x00, 0xff, 0x00,
		];
		uint cw_clip_math = ((cwin.bits & kCwBitsMod[clipMode]) ^ kCwBitsMod[clipMode + 4]) |
													((cwin.bits & kCwBitsMod[preventMathMode]) ^ kCwBitsMod[preventMathMode + 4]) << 8;

		uint[] dst = cast(uint[])renderBuffer[(y - 1) * renderPitch .. $];
		uint[] dst_org = dst;

		dst = dst[extraLeftRight - extraLeftCur .. $];

		uint windex = 0;
		do {
			uint left = cwin.edges[windex] + kPpuExtraLeftRight, right = cwin.edges[windex + 1] + kPpuExtraLeftRight;
			// If clip is set, then zero out the rgb values from the main screen.
			uint clip_color_mask = (cw_clip_math & 1) ? 0x1f : 0;
			uint math_enabled_cur = (cw_clip_math & 0x100) ? math_enabled : 0;
			uint fixed_color = fixedColorR | fixedColorG << 5 | fixedColorB << 10;
			if (math_enabled_cur == 0 || fixed_color == 0 && !halfColor && !rendered_subscreen) {
				// Math is disabled (or has no effect), so can avoid the per-pixel maths check
				uint i = left;
				do {
					uint color = cgram[bgBuffers[0].data[i] & 0xff];
					dst[0] = brightnessMult[color & clip_color_mask] << 16 | brightnessMult[(color >> 5) & clip_color_mask] << 8 | brightnessMult[(color >> 10) & clip_color_mask];
					dst = dst[1 .. $];
				} while (++i < right);
			} else {
				ubyte[] half_color_map = halfColor ? brightnessMultHalf : brightnessMult;
				// Store this in locals
				math_enabled_cur |= addSubscreen << 8 | subtractColor << 9;
				// Need to check for each pixel whether to use math or not based on the main screen layer.
				uint i = left;
				do {
					uint color = cgram[bgBuffers[0].data[i] & 0xff], color2;
					ubyte main_layer = (bgBuffers[0].data[i] >> 8) & 0xf;
					uint r = color & clip_color_mask;
					uint g = (color >> 5) & clip_color_mask;
					uint b = (color >> 10) & clip_color_mask;
					ubyte[] color_map = brightnessMult;
					if (math_enabled_cur & (1 << main_layer)) {
						if (math_enabled_cur & 0x100) { // addSubscreen ?
							if ((bgBuffers[1].data[i] & 0xff) != 0) {
								color2 = cgram[bgBuffers[1].data[i] & 0xff];
								color_map = half_color_map;
							} else {// Don't halve if addSubscreen && backdrop
								color2 = fixed_color;
							}
						} else {
							color2 = fixed_color;
							color_map = half_color_map;
						}
						uint r2 = (color2 & 0x1f), g2 = ((color2 >> 5) & 0x1f), b2 = ((color2 >> 10) & 0x1f);
						if (math_enabled_cur & 0x200) { // subtractColor?
							r = (r >= r2) ? r - r2 : 0;
							g = (g >= g2) ? g - g2 : 0;
							b = (b >= b2) ? b - b2 : 0;
						} else {
							r += r2;
							g += g2;
							b += b2;
						}
					}
					dst[0] = color_map[b] | color_map[g] << 8 | color_map[r] << 16;
					dst = dst[1 .. $];
				} while (++i < right);
			}
			cw_clip_math >>= 1;
		} while (++windex < cwin.nr);

		// Clear out stuff on the sides.
		if (extraLeftRight - extraLeftCur != 0) {
			dst_org[0 .. uint.sizeof * (extraLeftRight - extraLeftCur)] = 0;
		}
		if (extraLeftRight - extraRightCur != 0) {
			const start = 256 + extraLeftRight * 2 - (extraLeftRight - extraRightCur);
			dst_org[start .. start + uint.sizeof * (extraLeftRight - extraRightCur)] = 0;
		}
	}

	private void handlePixel(int x, int y) @safe pure {
		int r = 0, r2 = 0;
		int g = 0, g2 = 0;
		int b = 0, b2 = 0;
		if (!forcedBlank) {
			int mainLayer = getPixel(x, y, false, r, g, b);

			bool colorWindowState = getWindowState(5, x);
			if (
				clipMode == 3 ||
				(clipMode == 2 && colorWindowState) ||
				(clipMode == 1 && !colorWindowState)
				) {
				r = g = b = 0;
			}
			int secondLayer = 5; // backdrop
			bool mathEnabled = mainLayer < 6 && (mathEnabled & (1 << mainLayer)) && !(
				preventMathMode == 3 ||
				(preventMathMode == 2 && colorWindowState) ||
				(preventMathMode == 1 && !colorWindowState)
				);
			if ((mathEnabled && addSubscreen) || mode == 5 || mode == 6) {
				secondLayer = getPixel(x, y, true, r2, g2, b2);
			}
			// TODO: subscreen pixels can be clipped to black as well
			// TODO: math for subscreen pixels (add/sub sub to main)
			if (mathEnabled) {
				if (subtractColor) {
					r -= (addSubscreen && secondLayer != 5) ? r2 : fixedColorR;
					g -= (addSubscreen && secondLayer != 5) ? g2 : fixedColorG;
					b -= (addSubscreen && secondLayer != 5) ? b2 : fixedColorB;
				} else {
					r += (addSubscreen && secondLayer != 5) ? r2 : fixedColorR;
					g += (addSubscreen && secondLayer != 5) ? g2 : fixedColorG;
					b += (addSubscreen && secondLayer != 5) ? b2 : fixedColorB;
				}
				if (halfColor && (secondLayer != 5 || !addSubscreen)) {
					r >>= 1;
					g >>= 1;
					b >>= 1;
				}
				if (r > 31) {
					r = 31;
				}
				if (g > 31) {
					g = 31;
				}
				if (b > 31) {
					b = 31;
				}
				if (r < 0) {
					r = 0;
				}
				if (g < 0) {
					g = 0;
				}
				if (b < 0) {
					b = 0;
				}
			}
			if (!(mode == 5 || mode == 6)) {
				r2 = r; g2 = g; b2 = b;
			}
		}
		int row = y - 1;
		renderBuffer[row * renderPitch + (x + extraLeftRight)] =
			(cast(ubyte)(((b << 3) | (b >> 2)) * brightness / 15) << 0) |
			(cast(ubyte)(((g << 3) | (g >> 2)) * brightness / 15) << 8) |
			(cast(ubyte)(((r << 3) | (r >> 2)) * brightness / 15) << 16);
	}

	immutable int[4][10] bitDepthsPerMode = [
		[2, 2, 2, 2],
		[4, 4, 2, 5],
		[4, 4, 5, 5],
		[8, 4, 5, 5],
		[8, 2, 5, 5],
		[4, 2, 5, 5],
		[4, 5, 5, 5],
		[8, 5, 5, 5],
		[4, 4, 2, 5],
		[8, 7, 5, 5]
	];

	private int getPixel(int x, int y, bool sub, ref int r, ref int g, ref int b) @safe pure {
		// array for layer definitions per mode:
		// 0-7: mode 0-7; 8: mode 1 + l3prio; 9: mode 7 + extbg
		// 0-3; layers 1-4; 4: sprites; 5: nonexistent
		static immutable int[12][10] layersPerMode = [
			[4, 0, 1, 4, 0, 1, 4, 2, 3, 4, 2, 3],
			[4, 0, 1, 4, 0, 1, 4, 2, 4, 2, 5, 5],
			[4, 0, 4, 1, 4, 0, 4, 1, 5, 5, 5, 5],
			[4, 0, 4, 1, 4, 0, 4, 1, 5, 5, 5, 5],
			[4, 0, 4, 1, 4, 0, 4, 1, 5, 5, 5, 5],
			[4, 0, 4, 1, 4, 0, 4, 1, 5, 5, 5, 5],
			[4, 0, 4, 4, 0, 4, 5, 5, 5, 5, 5, 5],
			[4, 4, 4, 0, 4, 5, 5, 5, 5, 5, 5, 5],
			[2, 4, 0, 1, 4, 0, 1, 4, 4, 2, 5, 5],
			[4, 4, 1, 4, 0, 4, 1, 5, 5, 5, 5, 5]
		];

		static immutable int[12][10] prioritysPerMode = [
			[3, 1, 1, 2, 0, 0, 1, 1, 1, 0, 0, 0],
			[3, 1, 1, 2, 0, 0, 1, 1, 0, 0, 5, 5],
			[3, 1, 2, 1, 1, 0, 0, 0, 5, 5, 5, 5],
			[3, 1, 2, 1, 1, 0, 0, 0, 5, 5, 5, 5],
			[3, 1, 2, 1, 1, 0, 0, 0, 5, 5, 5, 5],
			[3, 1, 2, 1, 1, 0, 0, 0, 5, 5, 5, 5],
			[3, 1, 2, 1, 0, 0, 5, 5, 5, 5, 5, 5],
			[3, 2, 1, 0, 0, 5, 5, 5, 5, 5, 5, 5],
			[1, 3, 1, 1, 2, 0, 0, 1, 0, 0, 5, 5],
			[3, 2, 1, 1, 0, 0, 0, 5, 5, 5, 5, 5]
		];

		static immutable int[10] layerCountPerMode = [
			12, 10, 8, 8, 8, 8, 6, 5, 10, 7
		];


		// figure out which color is on this location on main- or subscreen, sets it in r, g, b
		// returns which layer it is: 0-3 for bg layer, 4 or 6 for sprites (depending on palette), 5 for backdrop
		int actMode = mode == 1 ? 8 : mode;
		actMode = mode == 7 && m7extBg_always_zero ? 9 : actMode;
		int layer = 5;
		int pixel = 0;
		for (int i = 0; i < layerCountPerMode[actMode]; i++) {
			int curLayer = layersPerMode[actMode][i];
			int curPriority = prioritysPerMode[actMode][i];
			bool layerActive = false;
			if (!sub) {
				layerActive = IS_SCREEN_ENABLED(0, curLayer) && (
					!IS_SCREEN_WINDOWED(0, curLayer) || !getWindowState(curLayer, x)
					);
			} else {
				layerActive = IS_SCREEN_ENABLED(1, curLayer) && (
					!IS_SCREEN_WINDOWED(1, curLayer) || !getWindowState(curLayer, x)
					);
			}
			if (layerActive) {
				if (curLayer < 4) {
					// bg layer
					int lx = x;
					int ly = y;
					if (IS_MOSAIC_ENABLED(curLayer)) {
						lx -= lx % mosaicSize;
						ly -= (ly - 1) % mosaicSize;
					}
					if (mode == 7) {
						pixel = getPixelForMode7(lx, curLayer, !!curPriority);
					} else {
						lx += bgLayer[curLayer].hScroll;
						ly += bgLayer[curLayer].vScroll;
						pixel = getPixelForBGLayer(
							lx & 0x3ff, ly & 0x3ff,
							curLayer, !!curPriority
						);
					}
				} else {
					// get a pixel from the sprite buffer
					pixel = 0;
					if ((objBuffer.data[x + kPpuExtraLeftRight] >> 12) == SPRITE_PRIO_TO_PRIO_HI(curPriority)) {
						pixel = objBuffer.data[x + kPpuExtraLeftRight] & 0xff;
					}
				}
			}
			if (pixel > 0) {
				layer = curLayer;
				break;
			}
		}
		ushort color = cgram[pixel & 0xff];
		r = color & 0x1f;
		g = (color >> 5) & 0x1f;
		b = (color >> 10) & 0x1f;
		if (layer == 4 && pixel < 0xc0) {
			layer = 6; // sprites with palette color < 0xc0
		}
		return layer;

	}


	private int getPixelForBGLayer(int x, int y, int layer, bool priority) @safe pure {
		BGLayer *layerp = &bgLayer[layer];
		// figure out address of tilemap word and read it
		bool wideTiles = mode == 5 || mode == 6;
		int tileBitsX = wideTiles ? 4 : 3;
		int tileHighBitX = wideTiles ? 0x200 : 0x100;
		int tileBitsY = 3;
		int tileHighBitY = 0x100;
		ushort tilemapAdr = cast(ushort)(layerp.tilemapAdr + (((y >> tileBitsY) & 0x1f) << 5 | ((x >> tileBitsX) & 0x1f)));
		if ((x & tileHighBitX) && layerp.tilemapWider) {
			tilemapAdr += 0x400;
		}
		if ((y & tileHighBitY) && layerp.tilemapHigher) {
			tilemapAdr += layerp.tilemapWider ? 0x800 : 0x400;
		}
		ushort tile = vram[tilemapAdr & 0x7fff];
		// check priority, get palette
		if ((cast(bool)(tile & 0x2000)) != priority) {
			return 0; // wrong priority
		}
		int paletteNum = (tile & 0x1c00) >> 10;
		// figure out position within tile
		int row = (tile & 0x8000) ? 7 - (y & 0x7) : (y & 0x7);
		int col = (tile & 0x4000) ? (x & 0x7) : 7 - (x & 0x7);
		int tileNum = tile & 0x3ff;
		if (wideTiles) {
			// if unflipped right half of tile, or flipped left half of tile
			if ((cast(bool)(x & 8)) ^ (cast(bool)(tile & 0x4000))) {
				tileNum += 1;
			}
		}
		// read tiledata, ajust palette for mode 0
		int bitDepth = bitDepthsPerMode[mode][layer];
		if (mode == 0) {
			paletteNum += 8 * layer;
		}
		// plane 1 (always)
		int paletteSize = 4;
		ushort plane1 = vram[(layerp.tileAdr + ((tileNum & 0x3ff) * 4 * bitDepth) + row) & 0x7fff];
		int pixel = (plane1 >> col) & 1;
		pixel |= ((plane1 >> (8 + col)) & 1) << 1;
		// plane 2 (for 4bpp, 8bpp)
		if (bitDepth > 2) {
			paletteSize = 16;
			ushort plane2 = vram[(layerp.tileAdr + ((tileNum & 0x3ff) * 4 * bitDepth) + 8 + row) & 0x7fff];
			pixel |= ((plane2 >> col) & 1) << 2;
			pixel |= ((plane2 >> (8 + col)) & 1) << 3;
		}
		// plane 3 & 4 (for 8bpp)
		if (bitDepth > 4) {
			paletteSize = 256;
			ushort plane3 = vram[(layerp.tileAdr + ((tileNum & 0x3ff) * 4 * bitDepth) + 16 + row) & 0x7fff];
			pixel |= ((plane3 >> col) & 1) << 4;
			pixel |= ((plane3 >> (8 + col)) & 1) << 5;
			ushort plane4 = vram[(layerp.tileAdr + ((tileNum & 0x3ff) * 4 * bitDepth) + 24 + row) & 0x7fff];
			pixel |= ((plane4 >> col) & 1) << 6;
			pixel |= ((plane4 >> (8 + col)) & 1) << 7;
		}
		// return cgram index, or 0 if transparent, palette number in bits 10-8 for 8-color layers
		return pixel == 0 ? 0 : paletteSize * paletteNum + pixel;
	}

	private void calculateMode7Starts(int y) @safe pure {
		// expand 13-bit values to signed values
		int hScroll = (cast(short) (m7matrix[6] << 3)) >> 3;
		int vScroll = (cast(short) (m7matrix[7] << 3)) >> 3;
		int xCenter = (cast(short) (m7matrix[4] << 3)) >> 3;
		int yCenter = (cast(short) (m7matrix[5] << 3)) >> 3;
		// do calculation
		int clippedH = hScroll - xCenter;
		int clippedV = vScroll - yCenter;
		clippedH = (clippedH & 0x2000) ? (clippedH | ~1023) : (clippedH & 1023);
		clippedV = (clippedV & 0x2000) ? (clippedV | ~1023) : (clippedV & 1023);
		if(IS_MOSAIC_ENABLED(0)) {
			y -= (y - 1) % mosaicSize;
		}
		ubyte ry = cast(ubyte)(m7yFlip ? 255 - y : y);
		m7startX = (
			((m7matrix[0] * clippedH) & ~63) +
			((m7matrix[1] * ry) & ~63) +
			((m7matrix[1] * clippedV) & ~63) +
			(xCenter << 8)
		);
		m7startY = (
			((m7matrix[2] * clippedH) & ~63) +
			((m7matrix[3] * ry) & ~63) +
			((m7matrix[3] * clippedV) & ~63) +
			(yCenter << 8)
		);
	}

	private int getPixelForMode7(int x, int layer, bool priority) @safe pure {
		if (IS_MOSAIC_ENABLED(layer)) {
			x -= x % mosaicSize;
		}
		ubyte rx = cast(ubyte)(m7xFlip ? 255 - x : x);
		int xPos = (m7startX + m7matrix[0] * rx) >> 8;
		int yPos = (m7startY + m7matrix[2] * rx) >> 8;
		bool outsideMap = xPos < 0 || xPos >= 1024 || yPos < 0 || yPos >= 1024;
		xPos &= 0x3ff;
		yPos &= 0x3ff;
		if(!m7largeField) {
			outsideMap = false;
		}
		ubyte tile = outsideMap ? 0 : vram[(yPos >> 3) * 128 + (xPos >> 3)] & 0xff;
		ubyte pixel = outsideMap && !m7charFill ? 0 : vram[tile * 64 + (yPos & 7) * 8 + (xPos & 7)] >> 8;
		if(layer == 1) {
			if((cast(bool) (pixel & 0x80)) != priority) {
				return 0;
			}
			return pixel & 0x7f;
		}
		return pixel;
	}

	private bool getWindowState(int layer, int x) @safe pure {
		uint winflags = GET_WINDOW_FLAGS(layer);
		if (!(winflags & kWindow1Enabled) && !(winflags & kWindow2Enabled)) {
			return false;
		}
		if ((winflags & kWindow1Enabled) && !(winflags & kWindow2Enabled)) {
			bool test = x >= window1left && x <= window1right;
			return (winflags & kWindow1Inversed) ? !test : test;
		}
		if (!(winflags & kWindow1Enabled) && (winflags & kWindow2Enabled)) {
			bool test = x >= window2left && x <= window2right;
			return (winflags & kWindow2Inversed) ? !test : test;
		}
		bool test1 = x >= window1left && x <= window1right;
		bool test2 = x >= window2left && x <= window2right;
		if (winflags & kWindow1Inversed) {
			test1 = !test1;
		}
		if (winflags & kWindow2Inversed) {
			test2 = !test2;
		}
		return test1 || test2;
	}

	private bool evaluateSprites(int line) @safe pure {
		// TODO: iterate over oam normally to determine in-range sprites,
		// then iterate those in-range sprites in reverse for tile-fetching
		// TODO: rectangular sprites, wierdness with sprites at -256
		int index = 0, index_end = index;
		int spritesLeft = 32 + 1, tilesLeft = 34 + 1;
		ubyte[2] spriteSizes = [ kSpriteSizes[objSize][0], kSpriteSizes[objSize][1] ];
		int extra_left_right = extraLeftRight;
		if (renderFlags & KPPURenderFlags.noSpriteLimits) {
			spritesLeft = tilesLeft = 1024;
		}
		int tilesLeftOrg = tilesLeft;

		do {
			int yy = oam[index] >> 8;
			if (yy == 0xf0) {
				continue; // this works for zelda because sprites are always 8 or 16.
			}
			// check if the sprite is on this line and get the sprite size
			int row = (line - yy) & 0xff;
			int highOam = oam[0x100 + (index >> 4)] >> (index & 15);
			int spriteSize = spriteSizes[(highOam >> 1) & 1];
			if (row >= spriteSize) {
				continue;
			}
			// in y-range, get the x location, using the high bit as well
			int x = (oam[index] & 0xff) + (highOam & 1) * 256;
			x -= (x >= 256 + extra_left_right) * 512;
			// if in x-range
			if (x <= -(spriteSize + extra_left_right)) {
				continue;
			}
			// break if we found 32 sprites already
			if (--spritesLeft == 0) {
				break;
			}
			// get some data for the sprite and y-flip row if needed
			int oam1 = oam[index + 1];
			int objAdr = (oam1 & 0x100) ? objTileAdr2 : objTileAdr1;
			if (oam1 & 0x8000) {
				row = spriteSize - 1 - row;
			}
			// fetch all tiles in x-range
			int paletteBase = 0x80 + 16 * ((oam1 & 0xe00) >> 9);
			int prio = SPRITE_PRIO_TO_PRIO((oam1 & 0x3000) >> 12, (oam1 & 0x800) == 0);
			PpuZbufType z = cast(ushort)(paletteBase + (prio << 8));

			for (int col = 0; col < spriteSize; col += 8) {
				if (col + x > -8 - extra_left_right && col + x < 256 + extra_left_right) {
					// break if we found 34 8*1 slivers already
					if (--tilesLeft == 0) {
						return true;
					}
					// figure out which tile this uses, looping within 16x16 pages, and get it's data
					int usedCol = oam1 & 0x4000 ? spriteSize - 1 - col : col;
					int usedTile = ((((oam1 & 0xff) >> 4) + (row >> 3)) << 4) | (((oam1 & 0xf) + (usedCol >> 3)) & 0xf);
					ushort[] addr = vram[(objAdr + usedTile * 16 + (row & 0x7)) & 0x7fff .. $];
					uint plane = addr[0] | addr[8] << 16;
					// go over each pixel
					int px_left = IntMax(-(col + x + kPpuExtraLeftRight), 0);
					int px_right = IntMin(256 + kPpuExtraLeftRight - (col + x), 8);
					PpuZbufType[] dst = objBuffer.data[col + x + px_left + kPpuExtraLeftRight .. $];

					for (int px = px_left; px < px_right; px++, dst = dst[1 .. $]) {
						int shift = oam1 & 0x4000 ? px : 7 - px;
						uint bits = plane >> shift;
						int pixel = (bits >> 0) & 1 | (bits >> 7) & 2 | (bits >> 14) & 4 | (bits >> 21) & 8;
						// draw it in the buffer if there is a pixel here, and the buffer there is still empty
						if (pixel != 0 && (dst[0] & 0xff) == 0) {
							dst[0] = cast(ushort)(z + pixel);
						}
					}
				}
			}
		} while ((index = (index + 2) & 0xff) != index_end);
		return (tilesLeft != tilesLeftOrg);
	}

	ubyte readRegister(ushort adr) @safe pure {
		switch (adr & 0xFF) {
			case 0x34:
			case 0x35:
			case 0x36:
				int result = m7matrix[0] * (m7matrix[1] >> 8);
				return (result >> (8 * (adr - 0x34))) & 0xff;
			default: break;
		}
		return 0xff;
	}

	void writeRegister(ushort address, ubyte val) @safe pure {
		const adr = address & 0xFF;
		switch (adr) {
			case 0x00: // INIDISP
				brightness = val & 0xf;
				forcedBlank = !!(val & 0x80);
				break;
			case 0x01: //OBSEL
				objSize = val >> 5;
				objTileAdr1 = (val & 0b0000_0111) << 13;
				objTileAdr2 = cast(ushort)(objTileAdr1 + ((val & 0b0001_1000) + 1) << 12);
				break;
			case 0x02: //OAMADDL
				oamAdr = (oamAdr & ~0xff) | val;
				oamSecondWrite = false;
				break;
			case 0x03: //OAMADDH
				//assert((val & 0x80) == 0);
				oamAdr = (oamAdr & ~0xff00) | ((val & 1) << 8);
				oamSecondWrite = false;
				break;
			case 0x04: //OAMDATA
				if (!oamSecondWrite) {
					oamBuffer = val;
				} else {
					if (oamAdr < 0x110)
						oam[oamAdr++] = (val << 8) | oamBuffer;
				}
				oamSecondWrite = !oamSecondWrite;
				break;
			case 0x05: // BGMODE
				mode = val & 0x7;
				//assert(val == 7 || val == 9);
				//assert(mode == 1 || mode == 7);
				//assert((val & 0xf0) == 0);
				break;
			case 0x06: // MOSAIC
				mosaicSize = (val >> 4) + 1;
				mosaicEnabled = (mosaicSize > 1) ? val : 0;
				break;
			case 0x07: // BG1SC
			case 0x08: // BG2SC
			case 0x09: // BG3SC
			case 0x0a: //BG4SC
				// small tilemaps are used in attract intro
				bgLayer[adr - 7].tilemapWider = val & 0x1;
				bgLayer[adr - 7].tilemapHigher = !!(val & 0x2);
				bgLayer[adr - 7].tilemapAdr = (val & 0xfc) << 8;
				break;
			case 0x0b: // BG12NBA
				bgLayer[0].tileAdr = (val & 0xf) << 12;
				bgLayer[1].tileAdr = (val & 0xf0) << 8;
				break;
			case 0x0c: // BG34NBA
				bgLayer[2].tileAdr = (val & 0xf) << 12;
				bgLayer[3].tileAdr = (val & 0xf0) << 8;
				break;
			case 0x0d: // BG1HOFS
				m7matrix[6] = ((val << 8) | m7prev) & 0x1fff;
				m7prev = val;
				goto case;
			case 0x0f: //BG2HOFS
			case 0x11: //BG3HOFS
			case 0x13: // BG4HOFS
				bgLayer[(adr - 0xd) / 2].hScroll = ((val << 8) | (scrollPrev & 0xf8) | (scrollPrev2 & 0x7)) & 0x3ff;
				scrollPrev = val;
				scrollPrev2 = val;
				break;
			case 0x0e: // BG1VOFS
				m7matrix[7] = ((val << 8) | m7prev) & 0x1fff;
				m7prev = val;
				goto case;
			case 0x10: // BG2VOFS
			case 0x12: // BG3VOFS
			case 0x14: //BG4VOFS
				bgLayer[(adr - 0xe) / 2].vScroll = ((val << 8) | scrollPrev) & 0x3ff;
				scrollPrev = val;
				break;
			case 0x15: // VMAIN
				if((val & 3) == 0) {
					vramIncrement = 1;
				} else if((val & 3) == 1) {
					vramIncrement = 32;
				} else {
					vramIncrement = 128;
				}
				//assert(((val & 0xc) >> 2) == 0);
				vramIncrementOnHigh = !!(val & 0x80);
				break;
			case 0x16: // VMADDL
				vramPointer = (vramPointer & 0xff00) | val;
				break;
			case 0x17: // VMADDH
				vramPointer = (vramPointer & 0x00ff) | (val << 8);
				break;
			case 0x18: // VMDATAL
				ushort vramAdr = vramPointer;
				vram[vramAdr & 0x7fff] = (vram[vramAdr & 0x7fff] & 0xff00) | val;
				if(!vramIncrementOnHigh) {
					vramPointer += vramIncrement;
				}
				break;
			case 0x19: // VMDATAH
				ushort vramAdr = vramPointer;
				vram[vramAdr & 0x7fff] = (vram[vramAdr & 0x7fff] & 0x00ff) | (val << 8);
				if(vramIncrementOnHigh) {
					vramPointer += vramIncrement;
				}
				break;
			case 0x1a: // M7SEL
				m7largeField = !!(val & 0x80);
				m7charFill = !!(val & 0x40);
				m7yFlip = !!(val & 0x2);
				m7xFlip = val & 0x1;
				break;
			case 0x1b: // M7A etc
			case 0x1c:
			case 0x1d:
			case 0x1e:
				m7matrix[adr - 0x1b] = cast(short)((val << 8) | m7prev);
				m7prev = val;
				break;
			case 0x1f:
			case 0x20:
				m7matrix[adr - 0x1b] = ((val << 8) | m7prev) & 0x1fff;
				m7prev = val;
				break;
			case 0x21:
				cgramPointer = val;
				cgramSecondWrite = false;
				break;
			case 0x22:
				if(!cgramSecondWrite) {
					cgramBuffer = val;
				} else {
					cgram[cgramPointer++] = (val << 8) | cgramBuffer;
				}
				cgramSecondWrite = !cgramSecondWrite;
				break;
			case 0x23: // W12SEL
				windowsel = (windowsel & ~0xff) | val;
				break;
			case 0x24: // W34SEL
				windowsel = (windowsel & ~0xff00) | (val << 8);
				break;
			case 0x25: // WOBJSEL
				windowsel = (windowsel & ~0xff0000) | (val << 16);
				break;
			case 0x26:
				window1left = val;
				break;
			case 0x27:
				window1right = val;
				break;
			case 0x28:
				window2left = val;
				break;
			case 0x29:
				window2right = val;
				break;
			case 0x2a: // WBGLOG
				//assert(val == 0);
				break;
			case 0x2b: // WOBJLOG
				//assert(val == 0);
				break;
			case 0x2c: // TM
				screenEnabled[0] = val;
				break;
			case 0x2d: // TS
				screenEnabled[1] = val;
				break;
			case 0x2e: // TMW
				screenWindowed[0] = val;
				break;
			case 0x2f: // TSW
				screenWindowed[1] = val;
				break;
			case 0x30: // CGWSEL
				//assert((val & 1) == 0); // directColor always zero
				addSubscreen = !!(val & 0x2);
				preventMathMode = (val & 0x30) >> 4;
				clipMode = (val & 0xc0) >> 6;
				break;
			case 0x31: // CGADSUB
				subtractColor = !!(val & 0x80);
				halfColor = !!(val & 0x40);
				mathEnabled = val & 0x3f;
				break;
			case 0x32: // COLDATA
				if(val & 0x80) {
					fixedColorB = val & 0x1f;
				}
				if(val & 0x40) {
					fixedColorG = val & 0x1f;
				}
				if(val & 0x20) {
					fixedColorR = val & 0x1f;
				}
				break;
			case 0x33: //SETINI
				interlacing = !!(val & 0b00000010);
				m7extBg_always_zero = !!(val & 0x40);
				break;
			default:
				break;
		}
	}
	void writeRegisterShort(ushort addr, ushort value) {
		writeRegister(addr, value & 0xFF);
		writeRegister(addr, value >> 8);
	}
	bool IS_SCREEN_ENABLED(uint sub, uint layer) const @safe pure { return !!(screenEnabled[sub] & (1 << layer)); }
	bool IS_SCREEN_WINDOWED(uint sub, uint layer) const @safe pure { return !!(screenWindowed[sub] & (1 << layer)); }
	bool IS_MOSAIC_ENABLED(uint layer) const @safe pure { return !!(mosaicEnabled & (1 << layer)); }
	bool GET_WINDOW_FLAGS(uint layer) const @safe pure { return !!(windowsel >> (layer * 4)); }
	void debugUI(const UIState state, VideoBackend video) {
		if (ImGui.TreeNode("Global state")) {
			ImGui.Text("BG mode: %d", mode);
			ImGui.Text("Brightness: %d", brightness);
			ImGui.TreePop();
		}
		if (ImGui.TreeNode("Sprites")) {
			const oam2 = cast(ubyte[])(oam[0x100 .. $]);
			foreach (id, entry; cast(OAMEntry[])(oam[0 .. 0x100])) {
				const uint upperX = !!(oam2[id/4] & (1 << ((id % 4) * 2)));
				const size = !!(oam2[id/4] & (1 << ((id % 4) * 2 + 1)));
				if (entry.yCoord < 0xE0) {
					if (ImGui.TreeNode(format!"Sprite %s"(id))) {
						ImGui.BeginDisabled();
						ImGui.Text(format!"Tile Offset: %s"(entry.startingTile));
						ImGui.Text(format!"Coords: (%s, %s)"(entry.xCoord + (upperX << 8), entry.yCoord));
						ImGui.Text(format!"Palette: %s"(entry.palette));
						bool boolean = entry.flipVertical;
						ImGui.Checkbox("Vertical flip", &boolean);
						boolean = entry.flipHorizontal;
						ImGui.Checkbox("Horizontal flip", &boolean);
						ImGui.Text(format!"Priority: %s"(entry.priority));
						ImGui.Text(format!"Priority: %s"(entry.nameTable));
						boolean = size;
						ImGui.Checkbox("Use alt size", &boolean);
						ImGui.EndDisabled();
						ImGui.TreePop();
					}
				}
			}
			ImGui.TreePop();
		}
		if (ImGui.TreeNode("Palettes")) {
			foreach (idx, ref palette; cgram[].chunks(16).enumerate) {
				if (ImGui.TreeNode(format!"Palette %s"(idx))) {
					foreach (i, ref colour; palette) {
						float[3] c = [((colour >> 0) & 31) / 31.0, ((colour >> 5) & 31) / 31.0, ((colour >> 10) & 31) / 31.0];
						if (ImGui.ColorEdit3(format!"%s"(i), c)) {
							colour = cast(ushort)((cast(ushort)(c[2] * 31) << 10) | (cast(ushort)(c[1] * 31) << 5) | cast(ushort)(c[0] * 31));
						}
					}
					ImGui.TreePop();
				}
			}
			ImGui.TreePop();
		}
		if (ImGui.TreeNode("Layers")) {
			static foreach (layer, label; ["BG1", "BG2", "BG3", "BG4"]) {{
				if (ImGui.TreeNode(label)) {
					ImGui.Text(format!"Tilemap address: $%04X"(bgLayer[layer].tilemapAdr));
					ImGui.Text(format!"Tile base address: $%04X"(bgLayer[layer].tileAdr));
					ImGui.Text(format!"Size: %s"(["32x32", "64x32", "32x64", "64x64"][bgLayer[layer].tilemapWider + (bgLayer[layer].tilemapHigher << 1)]));
					//ImGui.Text(format!"Tile size: %s"(["8x8", "16x16"][!!(BGMODE >> (4 + layer))]));
					//disabledCheckbox("Mosaic Enabled", !!((MOSAIC >> layer) & 1));
					ImGui.TreePop();
				}
			}}
			ImGui.TreePop();
		}
		if (ImGui.TreeNode("VRAM")) {
			static int paletteID = 0;
			if (ImGui.InputInt("Palette", &paletteID)) {
				paletteID = clamp(paletteID, 0, 15);
			}
			const texWidth = 16 * 8;
			const texHeight = 0x8000 / 16 / 16 * 8;
			static ubyte[2 * texWidth * texHeight] data;
			auto pixels = cast(ushort[])(data[]);
			ushort[16] palette = cgram[paletteID * 16 .. (paletteID + 1) * 16];
			palette[] &= 0x7FFF;
			foreach (idx, tile; (cast(ushort[])vram).chunks(16).enumerate) {
				const base = (idx % 16) * 8 + (idx / 16) * texWidth * 8;
				foreach (p; 0 .. 8 * 8) {
					const px = p % 8;
					const py = p / 8;
					const plane01 = tile[py] & pixelPlaneMasks[px];
					const plane23 = tile[py + 8] & pixelPlaneMasks[px];
					const s = 7 - px;
					const pixel = ((plane01 & 0xFF) >> s) | (((plane01 >> 8) >> s) << 1) | (((plane23 & 0xFF) >> s) << 2) | (((plane23 >> 8) >> s) << 3);
					pixels[base + px + py * texWidth] = palette[pixel];
				}
			}
			static void* windowSurface;
			if (windowSurface is null) {
				windowSurface = video.createSurface(texWidth, texHeight, ushort.sizeof * kPpuXPixels, PixelFormat.rgb555);
			}
			video.setSurfacePixels(windowSurface, data);
			ImGui.Image(windowSurface, ImVec2(texWidth * 3, texHeight * 3));
			ImGui.TreePop();
		}
	}
}

immutable ubyte[2][8] kSpriteSizes = [
	[8, 16], [8, 32], [8, 64], [16, 32],
	[16, 64], [32, 64], [16, 32], [16, 32]
];

enum {
	kWindow1Inversed = 1,
	kWindow1Enabled = 2,
	kWindow2Inversed = 4,
	kWindow2Enabled = 8,
}

alias SaveLoadFunc = void function(void*, void*, size_t);


struct PpuWindows {
	short[6] edges;
	ubyte nr;
	ubyte bits;
}

unittest {
	import replatform64.snes.hardware : HDMAWrite;
	import std.algorithm.iteration : splitter;
	import std.conv : to;
	import std.file : exists, mkdirRecurse, read, readText;
	import std.format : format;
	import std.path : buildPath;
	import std.stdio : writeln;
	import std.string : lineSplitter;
	enum width = 256;
	enum height = 224;
	static HDMAWrite[] parseHDMAWrites(string filename) {
		HDMAWrite[] result;
		auto file = readText(buildPath("testdata/snes", filename));
		foreach (line; file.lineSplitter) {
			HDMAWrite write;
			auto split = line.splitter('\t');
			write.vcounter = split.front.to!ushort;
			split.popFront();
			write.addr = split.front.to!ubyte(16);
			split.popFront();
			write.value = split.front.to!ubyte(16);
			result ~= write;
		}
		return result;
	}
	static ubyte[] draw(ref PPU ppu, HDMAWrite[] hdmaWrites, int flags) {
		ubyte[] buffer = new ubyte[](width * height * 4);
		enum pitch = width * 4;
		ppu.beginDrawing(buffer, pitch, flags);
		foreach (i; 0 .. height + 1) {
			foreach (write; hdmaWrites) {
				if (write.vcounter + 1 == i) {
					ppu.writeRegister(write.addr, write.value);
				}
			}
			ppu.runLine(i);
		}
		auto pixels = cast(uint[])buffer;
		foreach (ref pixel; pixels) { //swap red and blue, remove transparency
			pixel = 0xFF000000 | ((pixel & 0xFF) << 16) | (pixel & 0xFF00) | ((pixel & 0xFF0000) >> 16);
		}
		return buffer;
	}
	static ubyte[] renderMesen2State(string filename, HDMAWrite[] hdma = [], int flags) {
		PPU ppu;
		auto file = cast(ubyte[])read(buildPath("testdata/snes", filename));
		INIDISPValue INIDISP;
		OBSELValue OBSEL;
		BGMODEValue BGMODE;
		MOSAICValue MOSAIC;
		BGxSCValue BG1SC, BG2SC, BG3SC, BG4SC;
		BGxxNBAValue BG12NBA, BG34NBA;
		ushort BG1HOFS, BG1VOFS, BG2HOFS, BG2VOFS, BG3HOFS, BG3VOFS, BG4HOFS, BG4VOFS;
		M7SELValue M7SEL;
		ushort M7A, M7B, M7C, M7D, M7X, M7Y;
		ubyte W12SEL, W34SEL, WOBJSEL;
		ubyte WH0, WH1, WH2, WH3;
		ubyte WBGLOG, WOBJLOG;
		ScreenWindowEnableValue TM, TS;
		ScreenWindowEnableValue TMW, TSW;
		CGWSELValue CGWSEL;
		CGADSUBValue CGADSUB;
		ubyte COLDATAB, COLDATAG, COLDATAR;
		SETINIValue SETINI;
		loadMesen2SaveState(file, 0, (key, data) @safe pure {
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
				case "ppu.forcedBlank":
					INIDISP.forcedBlank = byteData & 1;
					break;
				case "ppu.screenBrightness":
					INIDISP.screenBrightness = byteData & 0b00001111;
					break;
				case "ppu.bgMode":
					BGMODE.mode = byteData & 0b00000111;
					break;
				case "ppu.oamMode":
					OBSEL.size = byteData & 0b00000111;
					break;
				case "ppu.oamBaseAddress":
					OBSEL.tileBase = (shortData & 0xE000) >> 13;
					break;
				case "ppu.oamAddressOffset":
					OBSEL.hiOffset = (shortData & 0xC000) >> 14;
					break;
				case "ppu.mode1Bg3Priority":
					BGMODE.bg3Priority = byteData & 1;
					break;
				case "ppu.mosaicEnabled":
					MOSAIC.enabledBG1 = !!(byteData & 0b00000001);
					MOSAIC.enabledBG2 = !!(byteData & 0b00000010);
					MOSAIC.enabledBG3 = !!(byteData & 0b00000100);
					MOSAIC.enabledBG4 = !!(byteData & 0b00001000);
					break;
				case "ppu.mosaicSize":
					// saved +1, for some reason.
					MOSAIC.size = (byteData - 1) & 0b00001111;
					break;
				case "ppu.mainScreenLayers":
					TM.bg1 = !!(byteData & 0b00000001);
					TM.bg2 = !!(byteData & 0b00000010);
					TM.bg3 = !!(byteData & 0b00000100);
					TM.bg4 = !!(byteData & 0b00001000);
					TM.obj = !!(byteData & 0b00010000);
					break;
				case "ppu.subScreenLayers":
					TS.bg1 = !!(byteData & 0b00000001);
					TS.bg2 = !!(byteData & 0b00000010);
					TS.bg3 = !!(byteData & 0b00000100);
					TS.bg4 = !!(byteData & 0b00001000);
					TS.obj = !!(byteData & 0b00010000);
					break;
				case "ppu.windowMaskMain[0]":
					TMW.bg1 = byteData & 1;
					break;
				case "ppu.windowMaskMain[1]":
					TMW.bg2 = byteData & 1;
					break;
				case "ppu.windowMaskMain[2]":
					TMW.bg3 = byteData & 1;
					break;
				case "ppu.windowMaskMain[3]":
					TMW.bg4 = byteData & 1;
					break;
				case "ppu.windowMaskMain[4]":
					TMW.obj = byteData & 1;
					break;
				case "ppu.windowMaskSub[0]":
					TSW.bg1 = byteData & 1;
					break;
				case "ppu.windowMaskSub[1]":
					TSW.bg2 = byteData & 1;
					break;
				case "ppu.windowMaskSub[2]":
					TSW.bg3 = byteData & 1;
					break;
				case "ppu.windowMaskSub[3]":
					TSW.bg4 = byteData & 1;
					break;
				case "ppu.windowMaskSub[4]":
					TSW.obj = byteData & 1;
					break;
				case "ppu.layers[0].chrAddress":
					BG12NBA.bg1 = (shortData & 0xF000) >> 12;
					break;
				case "ppu.layers[0].largeTiles":
					BGMODE.largeBG1Tiles = byteData & 1;
					break;
				case "ppu.layers[0].tilemapAddress":
					BG1SC.baseAddress = (shortData & 0xFC00) >> 10;
					break;
				case "ppu.layers[0].doubleHeight":
					BG1SC.doubleHeight = byteData & 1;
					break;
				case "ppu.layers[0].doubleWidth":
					BG1SC.doubleWidth = byteData & 1;
					break;
				case "ppu.layers[0].hscroll":
					BG1HOFS |= shortData;
					break;
				case "ppu.layers[0].vscroll":
					BG1VOFS |= shortData;
					break;
				case "ppu.layers[1].chrAddress":
					BG12NBA.bg2 = (shortData & 0xF000) >> 12;
					break;
				case "ppu.layers[1].largeTiles":
					BGMODE.largeBG2Tiles = byteData & 1;
					break;
				case "ppu.layers[1].tilemapAddress":
					BG2SC.baseAddress = (shortData & 0xFC00) >> 10;
					break;
				case "ppu.layers[1].doubleHeight":
					BG2SC.doubleHeight = byteData & 1;
					break;
				case "ppu.layers[1].doubleWidth":
					BG2SC.doubleWidth = byteData & 1;
					break;
				case "ppu.layers[1].hscroll":
					BG2HOFS |= shortData;
					break;
				case "ppu.layers[1].vscroll":
					BG2VOFS |= shortData;
					break;
				case "ppu.layers[2].chrAddress":
					BG34NBA.bg3 = (shortData & 0xF000) >> 12;
					break;
				case "ppu.layers[2].largeTiles":
					BGMODE.largeBG3Tiles = byteData & 1;
					break;
				case "ppu.layers[2].tilemapAddress":
					BG3SC.baseAddress = (shortData & 0xFC00) >> 10;
					break;
				case "ppu.layers[2].doubleHeight":
					BG3SC.doubleHeight = byteData & 1;
					break;
				case "ppu.layers[2].doubleWidth":
					BG3SC.doubleWidth = byteData & 1;
					break;
				case "ppu.layers[2].hscroll":
					BG3HOFS |= shortData;
					break;
				case "ppu.layers[2].vscroll":
					BG3VOFS |= shortData;
					break;
				case "ppu.layers[3].chrAddress":
					BG34NBA.bg4 = (shortData & 0xF000) >> 12;
					break;
				case "ppu.layers[3].largeTiles":
					BGMODE.largeBG4Tiles = byteData & 1;
					break;
				case "ppu.layers[3].tilemapAddress":
					BG4SC.baseAddress = (shortData & 0xFC00) >> 10;
					break;
				case "ppu.layers[3].doubleHeight":
					BG4SC.doubleHeight = byteData & 1;
					break;
				case "ppu.layers[3].doubleWidth":
					BG4SC.doubleWidth = byteData & 1;
					break;
				case "ppu.layers[3].hscroll":
					BG4HOFS |= shortData;
					break;
				case "ppu.layers[3].vscroll":
					BG4VOFS |= shortData;
					break;
				case "ppu.directColorMode":
					CGWSEL.directColour = byteData & 1;
					break;
				case "ppu.colorMathAddSubscreen":
					CGWSEL.subscreenEnable = byteData & 1;
					break;
				case "ppu.colorMathPreventMode":
					CGWSEL.mathPreventMode = intData & 0b00000011;
					break;
				case "ppu.colorMathClipMode":
					CGWSEL.mathClipMode = intData & 0b00000011;
					break;
				case "ppu.colorMathEnabled":
					CGADSUB.enableBG1 = !!(byteData & 0b00000001);
					CGADSUB.enableBG2 = !!(byteData & 0b00000010);
					CGADSUB.enableBG3 = !!(byteData & 0b00000100);
					CGADSUB.enableBG4 = !!(byteData & 0b00001000);
					CGADSUB.enableOBJ = !!(byteData & 0b00010000);
					CGADSUB.enableBackdrop = !!(byteData & 0b00100000);
					break;
				case "ppu.colorMathHalveResult":
					CGADSUB.enableHalf = byteData & 1;
					break;
				case "ppu.colorMathSubtractMode":
					CGADSUB.enableSubtract = byteData & 1;
					break;
				case "ppu.mode7.horizontalMirroring":
					M7SEL.screenHFlip = byteData & 1;
					break;
				case "ppu.mode7.verticalMirroring":
					M7SEL.screenVFlip = byteData & 1;
					break;
				case "ppu.mode7.fillWithTile0":
					M7SEL.tile0Fill = byteData & 1;
					break;
				case "ppu.mode7.largeMap":
					M7SEL.largeMap = byteData & 1;
					break;
				case "ppu.mode7.matrix[0]":
					M7A |= shortData;
					break;
				case "ppu.mode7.matrix[1]":
					M7B |= shortData;
					break;
				case "ppu.mode7.matrix[2]":
					M7C |= shortData;
					break;
				case "ppu.mode7.matrix[3]":
					M7D |= shortData;
					break;
				case "ppu.mode7.centerX":
					M7X |= shortData;
					break;
				case "ppu.mode7.centerY":
					M7Y |= shortData;
					break;
				case "ppu.screenInterlace":
					SETINI.screenInterlace = byteData & 1;
					break;
				case "ppu.objInterlace":
					SETINI.objInterlace = byteData & 1;
					break;
				case "ppu.overscanMode":
					SETINI.overscan = byteData & 1;
					break;
				case "ppu.hiResMode":
					SETINI.hiRes = byteData & 1;
					break;
				case "ppu.extBgEnabled":
					SETINI.extbg = byteData & 1;
					break;
				case "ppu.window[0].invertedLayers[0]":
					W12SEL |= byteData & 1;
					break;
				case "ppu.window[0].activeLayers[0]":
					W12SEL |= (byteData & 1) << 1;
					break;
				case "ppu.window[1].invertedLayers[0]":
					W12SEL |= (byteData & 1) << 2;
					break;
				case "ppu.window[1].activeLayers[0]":
					W12SEL |= (byteData & 1) << 3;
					break;
				case "ppu.window[0].invertedLayers[1]":
					W12SEL |= (byteData & 1) << 4;
					break;
				case "ppu.window[0].activeLayers[1]":
					W12SEL |= (byteData & 1) << 5;
					break;
				case "ppu.window[1].invertedLayers[1]":
					W12SEL |= (byteData & 1) << 6;
					break;
				case "ppu.window[1].activeLayers[1]":
					W12SEL |= (byteData & 1) << 7;
					break;
				case "ppu.window[0].invertedLayers[2]":
					W34SEL |= byteData & 1;
					break;
				case "ppu.window[0].activeLayers[2]":
					W34SEL |= (byteData & 1) << 1;
					break;
				case "ppu.window[1].invertedLayers[2]":
					W34SEL |= (byteData & 1) << 2;
					break;
				case "ppu.window[1].activeLayers[2]":
					W34SEL |= (byteData & 1) << 3;
					break;
				case "ppu.window[0].invertedLayers[3]":
					W34SEL |= (byteData & 1) << 4;
					break;
				case "ppu.window[0].activeLayers[3]":
					W34SEL |= (byteData & 1) << 5;
					break;
				case "ppu.window[1].invertedLayers[3]":
					W34SEL |= (byteData & 1) << 6;
					break;
				case "ppu.window[1].activeLayers[3]":
					W34SEL |= (byteData & 1) << 7;
					break;
				case "ppu.window[0].invertedLayers[4]":
					WOBJSEL |= byteData & 1;
					break;
				case "ppu.window[0].activeLayers[4]":
					WOBJSEL |= (byteData & 1) << 1;
					break;
				case "ppu.window[1].invertedLayers[4]":
					WOBJSEL |= (byteData & 1) << 2;
					break;
				case "ppu.window[1].activeLayers[4]":
					WOBJSEL |= (byteData & 1) << 3;
					break;
				case "ppu.window[0].invertedLayers[5]":
					WOBJSEL |= (byteData & 1) << 4;
					break;
				case "ppu.window[0].activeLayers[5]":
					WOBJSEL |= (byteData & 1) << 5;
					break;
				case "ppu.window[1].invertedLayers[5]":
					WOBJSEL |= (byteData & 1) << 6;
					break;
				case "ppu.window[1].activeLayers[5]":
					WOBJSEL |= (byteData & 1) << 7;
					break;
				case "ppu.window[0].left":
					WH0 |= byteData;
					break;
				case "ppu.window[0].right":
					WH1 |= byteData;
					break;
				case "ppu.window[1].left":
					WH2 |= byteData;
					break;
				case "ppu.window[1].right":
					WH3 |= byteData;
					break;
				case "ppu.maskLogic[0]":
					WBGLOG |= intData & 3;
					break;
				case "ppu.maskLogic[1]":
					WBGLOG |= (intData & 3) << 2;
					break;
				case "ppu.maskLogic[2]":
					WBGLOG |= (intData & 3) << 4;
					break;
				case "ppu.maskLogic[3]":
					WBGLOG |= (intData & 3) << 6;
					break;
				case "ppu.maskLogic[4]":
					WOBJLOG |= intData & 3;
					break;
				case "ppu.maskLogic[5]":
					WOBJLOG |= (intData & 3) << 2;
					break;
				case "ppu.fixedColor":
					COLDATAB |= (shortData & 0b000000000011111) >> 0;
					COLDATAG |= (shortData & 0b000001111100000) >> 5;
					COLDATAR |= (shortData & 0b111110000000000) >> 10;
					break;
				case "ppu.vram":
					ppu.vram[] = cast(const(ushort)[])data;
					break;
				case "ppu.oamRam":
					ppu.oam[] = cast(const(ushort)[])data;
					break;
				case "ppu.cgram":
					ppu.cgram[] = cast(const(ushort)[])data;
					break;
				default: break;
			}
		});
		ppu.writeRegister(Register.INIDISP, INIDISP.raw);
		ppu.writeRegister(Register.OBSEL, OBSEL.raw);
		ppu.writeRegister(Register.BGMODE, BGMODE.raw);
		ppu.writeRegister(Register.MOSAIC, MOSAIC.raw);
		ppu.writeRegister(Register.BG1SC, BG1SC.raw);
		ppu.writeRegister(Register.BG2SC, BG2SC.raw);
		ppu.writeRegister(Register.BG3SC, BG3SC.raw);
		ppu.writeRegister(Register.BG4SC, BG4SC.raw);
		ppu.writeRegister(Register.BG12NBA, BG12NBA.raw);
		ppu.writeRegister(Register.BG34NBA, BG34NBA.raw);
		ppu.writeRegisterShort(Register.BG1HOFS, BG1HOFS);
		ppu.writeRegisterShort(Register.BG1VOFS, BG1VOFS);
		ppu.writeRegisterShort(Register.BG2HOFS, BG2HOFS);
		ppu.writeRegisterShort(Register.BG2VOFS, BG2VOFS);
		ppu.writeRegisterShort(Register.BG3HOFS, BG3HOFS);
		ppu.writeRegisterShort(Register.BG3VOFS, BG3VOFS);
		ppu.writeRegisterShort(Register.BG4HOFS, BG4HOFS);
		ppu.writeRegisterShort(Register.BG4VOFS, BG4VOFS);
		ppu.writeRegister(Register.M7SEL, M7SEL.raw);
		ppu.writeRegisterShort(Register.M7A, M7A);
		ppu.writeRegisterShort(Register.M7B, M7B);
		ppu.writeRegisterShort(Register.M7C, M7C);
		ppu.writeRegisterShort(Register.M7D, M7D);
		ppu.writeRegisterShort(Register.M7X, M7X);
		ppu.writeRegisterShort(Register.M7Y, M7Y);
		ppu.writeRegister(Register.W12SEL, W12SEL);
		ppu.writeRegister(Register.W34SEL, W34SEL);
		ppu.writeRegister(Register.WOBJSEL, WOBJSEL);
		ppu.writeRegister(Register.WH0, WH0);
		ppu.writeRegister(Register.WH1, WH1);
		ppu.writeRegister(Register.WH2, WH2);
		ppu.writeRegister(Register.WH3, WH3);
		ppu.writeRegister(Register.WBGLOG, WBGLOG);
		ppu.writeRegister(Register.WOBJLOG, WOBJLOG);
		ppu.writeRegister(Register.TM, TM.raw);
		ppu.writeRegister(Register.TS, TS.raw);
		ppu.writeRegister(Register.TMW, TMW.raw);
		ppu.writeRegister(Register.TSW, TSW.raw);
		ppu.writeRegister(Register.CGWSEL, CGWSEL.raw);
		ppu.writeRegister(Register.CGADSUB, CGADSUB.raw);
		ppu.writeRegister(Register.COLDATA, COLDATAB | 0x80);
		ppu.writeRegister(Register.COLDATA, COLDATAG | 0x40);
		ppu.writeRegister(Register.COLDATA, COLDATAR | 0x20);
		ppu.writeRegister(Register.SETINI, SETINI.raw);
		return draw(ppu, hdma, flags);
	}
	static void runTest(string name, bool oldRenderer, bool newRenderer) {
		HDMAWrite[] writes;
		if (buildPath("testdata/snes", name~".hdma").exists) {
			writes = parseHDMAWrites(name~".hdma");
		}
		static void compare(ubyte[] frame, bool expected, string renderName, string dumpSuffix, string testName) {
			if (const result = comparePNG(frame, "testdata/snes", testName~".png", width, height)) {
				mkdirRecurse("failed");
				dumpPNG(frame, "failed/"~testName~"-"~dumpSuffix~".png", width, height);
				if (!expected) {
					writeln(format!"(Expected) %s pixel mismatch at %s, %s in %s (got %08X, expecting %08X)"(renderName, result.x, result.y, testName, result.got, result.expected));
				} else {
					assert(0, format!"%s pixel mismatch at %s, %s in %s (got %08X, expecting %08X)"(renderName, result.x, result.y, testName, result.got, result.expected));
				}
			} else {
				assert(expected, format!"Unexpected %s success in %s"(renderName, testName));
			}
		}
		compare(renderMesen2State(name~".mss", writes, 0), oldRenderer, "Old renderer", "old", name);
		compare(renderMesen2State(name~".mss", writes, KPPURenderFlags.newRenderer), newRenderer, "New renderer", "new", name);
	}
	// TODO: change all falses to true
	runTest("helloworld", true, true);
	runTest("mosaicm3", true, false);
	runTest("mosaicm5", false, false);
	runTest("ebswirl", false, false);
	runTest("ebnorm", true, true);
	runTest("ebspriteprio", true, true);
	runTest("ebspriteprio2", true, false);
	runTest("ebbattle", true, true);
	runTest("ebmeteor", false, false);
	runTest("ebgas", true, true);
	runTest("8x8BG1Map2BPP32x328PAL", true, true);
	runTest("8x8BG2Map2BPP32x328PAL", true, false);
	runTest("8x8BG3Map2BPP32x328PAL", true, false);
	runTest("8x8BG4Map2BPP32x328PAL", true, false);
	runTest("8x8BGMap4BPP32x328PAL", true, true);
	runTest("8x8BGMap8BPP32x32", true, true);
	runTest("8x8BGMap8BPP32x64", true, true);
	runTest("8x8BGMap8BPP64x32", true, true);
	runTest("8x8BGMap8BPP64x64", true, true);
	runTest("8x8BGMapTileFlip", true, true);
	runTest("HiColor575Myst", true, true);
	runTest("HiColor1241DLair", true, true);
	runTest("HiColor3840", true, true);
	runTest("InterlaceFont", false, false);
	runTest("InterlaceMystHDMA", false, false);
	runTest("Perspective", false, false);
	runTest("Rings", true, false);
	runTest("RotZoom", false, false);
}

union INIDISPValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			uint, "screenBrightness", 4,
			uint, "", 3,
			bool, "forcedBlank", 1,
		));
	}
}

union OBSELValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			uint, "tileBase", 3,
			uint, "hiOffset", 2,
			uint, "size", 3,
		));
	}
}

union BGMODEValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			uint, "mode", 3,
			bool, "bg3Priority", 1,
			bool, "largeBG1Tiles", 1,
			bool, "largeBG2Tiles", 1,
			bool, "largeBG3Tiles", 1,
			bool, "largeBG4Tiles", 1,
		));
	}
}

union MOSAICValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			bool, "enabledBG1", 1,
			bool, "enabledBG2", 1,
			bool, "enabledBG3", 1,
			bool, "enabledBG4", 1,
			uint, "size", 4,
		));
	}
}

union BGxSCValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			bool, "doubleWidth", 1,
			bool, "doubleHeight", 1,
			uint, "baseAddress", 6,
		));
	}
}

union BGxxNBAValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			uint, "bg1", 4,
			uint, "bg2", 4,
		));
	}
	struct {
		mixin(bitfields!(
			uint, "bg3", 4,
			uint, "bg4", 4,
		));
	}
}

union M7SELValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			bool, "screenHFlip", 1,
			bool, "screenVFlip", 1,
			uint, "", 4,
			bool, "tile0Fill", 1,
			bool, "largeMap", 1,
		));
	}
}

union ScreenWindowEnableValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			bool, "bg1", 1,
			bool, "bg2", 1,
			bool, "bg3", 1,
			bool, "bg4", 1,
			bool, "obj", 1,
			uint, "", 3,
		));
	}
}

union CGWSELValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			bool, "directColour", 1,
			bool, "subscreenEnable", 1,
			uint, "", 2,
			uint, "mathPreventMode", 2,
			uint, "mathClipMode", 2,
		));
	}
}

union CGADSUBValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			bool, "enableBG1", 1,
			bool, "enableBG2", 1,
			bool, "enableBG3", 1,
			bool, "enableBG4", 1,
			bool, "enableOBJ", 1,
			bool, "enableBackdrop", 1,
			bool, "enableHalf", 1,
			bool, "enableSubtract", 1,
		));
	}
}

union SETINIValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			bool, "screenInterlace", 1,
			bool, "objInterlace", 1,
			bool, "overscan", 1,
			bool, "hiRes", 1,
			uint, "", 2,
			bool, "extbg", 1,
			bool, "", 1,
		));
	}
}

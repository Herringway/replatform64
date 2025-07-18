module replatform64.snes.hardware.ppu;

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

import replatform64.dumping;
import replatform64.testhelpers;
import replatform64.snes.hardware;
import replatform64.ui;
import replatform64.util;

import pixelmancy.colours;
import pixelmancy.tiles;

import std.algorithm.comparison;
import std.algorithm.iteration;
import std.algorithm.mutation;
import std.bitmanip;
import std.format;
import std.range;
import std.typecons;

enum MaskLogic {
	or = 0,
	and = 1,
	xor = 2,
	xnor = 3,
}

///
enum LayerID {
	bg1, /// Background layer 1
	bg2, /// Background layer 2 (also EXTBG)
	bg3, /// Background layer 3
	bg4, /// Background layer 4
	obj, /// Sprites
	math, /// Colour math pseudo-layer
}

struct Layer {
	static struct MainSub {
		bool screenEnabled;
		bool windowEnabled;
	}
	MainSub main;
	MainSub sub;
	bool layerDisabled;
	bool window1Inverted;
	bool window1Enabled;
	bool window2Inverted;
	bool window2Enabled;
	MaskLogic maskLogic; // NYI
	// only used for background layers
	ushort hScroll = 0;
	ushort vScroll = 0;
	bool tilemapWider = false;
	bool tilemapHigher = false;
	ushort tilemapAdr = 0;
	bool doubleTileSize;
	bool mosaic;
	ushort tileAdr = 0;
}

enum kPpuExtraLeftRight = 88;

enum kPpuXPixels = 256 + kPpuExtraLeftRight * 2;

struct ZBufType {
	ubyte priority;
	ubyte pixel;
	this(ubyte priority, ubyte pixel) @safe pure {
		this.priority = priority;
		this.pixel = pixel;
	}
	this(ubyte priority, LayerID layer, ubyte pixel) @safe pure {
		this(cast(ubyte)((priority << 4) | layer), pixel);
	}
	this(ubyte priority, ubyte pixel, ubyte palette, ubyte bpp) @safe pure {
		this(priority, cast(ubyte)(pixel + (palette << bpp)));
	}
	ubyte layer() const @safe pure => priority & 0xF;
}

struct PpuPixelPrioBufs {
	// This holds the prio in the upper 8 bits and the color in the lower 8 bits.
	ZBufType[kPpuXPixels] data;
}

enum PPURenderFlags {
	newRenderer = 1 << 0,
	// Render mode7 upsampled by 4x4
	mode74x4 = 1 << 1,
	// Use 240 height instead of 224
	height240 = 1 << 2,
	// Disable sprite render limits
	noSpriteLimits = 1 << 3,
}

struct PPU {
	alias ColourFormat = BGR555;
	bool lineHasSprites;
	ubyte lastBrightnessMult = 0xff;
	ubyte lastMosaicModulo = 0xff;
	BitFlags!PPURenderFlags renderFlags;
	ubyte extraLeftCur = 0;
	ubyte extraRightCur = 0;
	ubyte extraLeftRight = 0;
	ubyte extraBottomCur = 0;
	float mode7PerspectiveLow, mode7PerspectiveHigh;
	bool interlacing;

	// TMW / TSW etc
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
	Layer[6] layers;

	// color math
	MathClipMode clipMode;
	ColourMathEnabled preventMathMode;
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
	ubyte scrollPrev = 0;
	ubyte scrollPrev2 = 0;
	bool bg3Priority;

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

	@Skip:
	union {
		struct {
			OAMEntry[128] oam;
			ubyte[oam.length / 4] oamHigh;
		}
		ubyte[oam.sizeof + oamHigh.sizeof] oamRaw;
	}

	// store 31 extra entries to remove the need for clamp
	ubyte[32 + 31] brightnessMult;
	ubyte[32 * 2] brightnessMultHalf;
	BGR555[0x100] cgram;
	ubyte[kPpuXPixels] mosaicModulo;
	ColourFormat[256] colorMapRgb;
	ushort[0x8000] vram;

	int getCurrentRenderScale(BitFlags!PPURenderFlags flags) const @safe pure {
		bool hq = mode == 7 && !forcedBlank && flags.mode74x4 && flags.newRenderer;
		return hq ? 4 : 1;
	}

	void beginDrawing(PPURenderFlags flags) @safe pure {
		renderFlags = BitFlags!PPURenderFlags(flags);

		// Cache the brightness computation
		if (brightness != lastBrightnessMult) {
			ubyte ppu_brightness = brightness;
			lastBrightnessMult = ppu_brightness;
			for (int i = 0; i < 32; i++) {
				brightnessMultHalf[i * 2] = brightnessMultHalf[i * 2 + 1] = brightnessMult[i] = cast(ubyte)((i * ppu_brightness) / 15);
			}
			// Store 31 extra entries to remove the need for clamping to 31.
			brightnessMult[32 .. 63] = brightnessMult[31];
		}

		if (getCurrentRenderScale(renderFlags) == 4) {
			for (int i = 0; i < colorMapRgb.length; i++) {
				const color = cgram[i];
				colorMapRgb[i] = ColourFormat(brightnessMult[color.red], brightnessMult[color.green], brightnessMult[color.blue]);
			}
		}
	}

	private void ClearBackdrop(ref PpuPixelPrioBufs buf) const @safe pure {
		buf.data[] = ZBufType(0, LayerID.math, 0);
	}

	void runLine(Array2D!ColourFormat renderBuffer, int line) @safe pure {
		if(line != 0) {
			if (mosaicSize != lastMosaicModulo) {
				int mod = mosaicSize;
				lastMosaicModulo = cast(ubyte)mod;
				for (int i = 0, j = 0; i < mosaicModulo.length; i++) {
					mosaicModulo[i] = cast(ubyte)(i - j);
					j = (j + 1 == mod ? 0 : j + 1);
				}
			}
			PpuPixelPrioBufs[3] winBuffers;
			// evaluate sprites
			ClearBackdrop(winBuffers[2]);
			lineHasSprites = !forcedBlank && evaluateSprites(line - 1, winBuffers[2]);

			// outside of visible range?
			if (line >= 225 + extraBottomCur) {
				renderBuffer[0 .. 256 + extraLeftRight * 2, line - 1] = ColourFormat(0, 0, 0);
				return;
			}

			if (renderFlags.newRenderer) {
				drawWholeLine(renderBuffer, winBuffers, line);
			} else {
				if (mode == 7) {
					calculateMode7Starts(line);
				}
				for (int x = 0; x < 256; x++) {
					handlePixel(renderBuffer, winBuffers[2], x, line);
				}

				if (extraLeftRight != 0) {
					renderBuffer[0 .. extraLeftRight, line - 1] = ColourFormat(0, 0, 0);
					renderBuffer[256 + extraLeftRight .. $, line - 1] = ColourFormat(0, 0, 0);
				}
			}
		}
	}

	private PpuWindows windowsClear(uint layer) const @safe pure {
		PpuWindows win;
		win.edges[0] = -(layer != 2 ? extraLeftCur : 0);
		win.edges[1] = 256 + (layer != 2 ? extraRightCur : 0);
		win.nr = 1;
		win.bits = 0;
		return win;
	}

	private PpuWindows windowsCalc(uint layer) const @safe pure {
		PpuWindows win;
		// Evaluate which spans to render based on the window settings.
		// There are at most 5 windows.
		// Algorithm from Snes9x
		const winflags = layers[layer];
		uint nr = 1;
		int window_right = 256 + (layer != 2 ? extraRightCur : 0);
		win.edges[0] = - (layer != 2 ? extraLeftCur : 0);
		win.edges[1] = cast(short)window_right;
		uint i, j;
		int t;
		bool w1_ena = winflags.window1Enabled && window1left <= window1right;
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
		bool w2_ena = winflags.window2Enabled && window2left <= window2right;
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
		if (winflags.window1Enabled && winflags.window1Inverted) {
			w1_bits = cast(ubyte)~w1_bits;
		}
		if (w2_ena) {
			for (i = 0; win.edges[i] != window2left; i++) {}
			for (j = i; win.edges[j] != window2right + 1; j++) {}
			w2_bits = cast(ubyte)(((1 << (j - i)) - 1) << i);
		}
		if (winflags.window2Enabled && winflags.window2Inverted) {
			w2_bits = cast(ubyte)~w2_bits;
		}
		win.bits = w1_bits | w2_bits;
		return win;
	}
	private Array2D!(const TilemapEntry)[4] getBackgroundTilemaps(uint layer) const return @safe pure {
		static immutable tilemapOffsets = [
			[0x000, 0x000, 0x000, 0x000],
			[0x000, 0x400, 0x000, 0x400],
			[0x000, 0x000, 0x400, 0x400],
			[0x000, 0x400, 0x800, 0xC00],
		];
		alias Tilemap = Array2D!(const TilemapEntry);
		const base = layers[layer].tilemapAdr;
		const offsets = tilemapOffsets[layers[layer].tilemapWider + layers[layer].tilemapHigher * 2];
		return [
			Tilemap(32, 32, cast(const(TilemapEntry)[])vram[base + offsets[0] .. $][0 .. 32 * 32]),
			Tilemap(32, 32, cast(const(TilemapEntry)[])vram[base + offsets[1] .. $][0 .. 32 * 32]),
			Tilemap(32, 32, cast(const(TilemapEntry)[])vram[base + offsets[2] .. $][0 .. 32 * 32]),
			Tilemap(32, 32, cast(const(TilemapEntry)[])vram[base + offsets[3] .. $][0 .. 32 * 32]),
		];
	}
	// Draw a whole line of a background layer into bgBuffer
	private void drawBackground(size_t bpp)(uint y, LayerID layer, ubyte[2] priorities, scope ref PpuPixelPrioBufs bgBuffer, const PpuWindows win) const @safe pure {
		const bglayer = layers[layer];
		const tilemaps = getBackgroundTilemaps(layer);
		static if (bpp == 2) {
			alias TileType = Intertwined2BPP;
		} else static if (bpp == 4) {
			alias TileType = Intertwined4BPP;
		} else static if (bpp == 8) {
			alias TileType = Intertwined8BPP;
		}
		if (bglayer.mosaic) {
			y -= (y - 1) % mosaicSize;
		}
		if (mode == 7) {
			// expand 13-bit values to signed values
			int hScroll = (cast(short)(m7matrix[6] << 3)) >> 3;
			int vScroll = (cast(short)(m7matrix[7] << 3)) >> 3;
			int xCenter = (cast(short)(m7matrix[4] << 3)) >> 3;
			int yCenter = (cast(short)(m7matrix[5] << 3)) >> 3;
			int clippedH = hScroll - xCenter;
			int clippedV = vScroll - yCenter;
			clippedH = (clippedH & 0x2000) ? (clippedH | ~1023) : (clippedH & 1023);
			clippedV = (clippedV & 0x2000) ? (clippedV | ~1023) : (clippedV & 1023);
			uint ry = m7yFlip ? 255 - y : y;
			uint m7startX = (m7matrix[0] * clippedH & ~63) + (m7matrix[1] * ry & ~63) + (m7matrix[1] * clippedV & ~63) + (xCenter << 8);
			uint m7startY = (m7matrix[2] * clippedH & ~63) + (m7matrix[3] * ry & ~63) + (m7matrix[3] * clippedV & ~63) + (yCenter << 8);
			foreach (edges; win.validEdges) {
				int x = edges[0], x2 = edges[1], tile;
				auto dstz = bgBuffer.data[x + kPpuExtraLeftRight .. x2 + kPpuExtraLeftRight];
				uint rx = m7xFlip ? 255 - x : x;
				uint xpos = m7startX + m7matrix[0] * rx;
				uint ypos = m7startY + m7matrix[2] * rx;
				uint dx = m7xFlip ? -m7matrix[0] : m7matrix[0];
				uint dy = m7xFlip ? -m7matrix[2] : m7matrix[2];
				uint outside_value = m7largeField ? 0x3ffff : 0xffffffff;
				foreach (ref dst; dstz) {
					if (cast(uint)(xpos | ypos) > outside_value) {
						if (!m7charFill) {
							break;
						}
						tile = 0;
					} else {
						tile = vram[(ypos >> 11 & 0x7f) * 128 + (xpos >> 11 & 0x7f)] & 0xff;
					}
					ubyte pixel = vram[tile * 64 + (ypos >> 8 & 7) * 8 + (xpos >> 8 & 7)] >> 8;
					if (pixel) {
						dst = ZBufType(priority: 12, layer: layer, pixel: pixel);
					}
					xpos += dx;
					ypos += dy;
				}
			}
		} else {
			auto tiles = (cast(const(TileType)[])vram).cycle[(bglayer.tileAdr * 2) / TileType.sizeof .. (bglayer.tileAdr * 2) / TileType.sizeof + 0x400];
			y += bglayer.vScroll;
			foreach (edges; win.validEdges) {
				uint x = edges[0] + bglayer.hScroll;
				uint w = edges[1] - edges[0];
				auto dstz = bgBuffer.data[edges[0] + kPpuExtraLeftRight .. $];
				const tileLine = (y / 8) % 32;
				const tileMap = ((y >> 8) & 1) * 2;
				auto tp = tilemaps[tileMap][0 .. $, tileLine].chain(tilemaps[tileMap + 1][0 .. $, tileLine]).cycle.drop((x / 8) & 0x3F).take(w);
				foreach (px; 0 .. w) {
					const baseX_ = px + x % 8;
					const baseX = bglayer.mosaic ? (baseX_ - baseX_ % mosaicSize) : baseX_;
					const tileMapEntry = tp[baseX / 8];
					const tile = tiles[tileMapEntry.index];
					const tileX = autoFlip(baseX % 8, tileMapEntry.flipHorizontal);
					const tileY = autoFlip(y % 8, tileMapEntry.flipVertical);
					const priority = priorities[tileMapEntry.priority];
					const pixel = tile[tileX, tileY];
					if (pixel && (priority > dstz[px].priority)) {
						dstz[px] = ZBufType(priority, tile[tileX, tileY], tileMapEntry.palette, bpp);
					}
				}
			}
		}
	}

	// level6 should be set if it's from palette 0xc0 which means color math is not applied
	ubyte SPRITE_PRIO_TO_PRIO(uint prio, bool level6) const @safe pure {
		return cast(ubyte)(SPRITE_PRIO_TO_PRIO_HI(prio) * 16 + 4 + (level6 ? 2 : 0));
	}
	ubyte SPRITE_PRIO_TO_PRIO_HI(uint prio) const @safe pure {
		return cast(ubyte)((prio + 1) * 3);
	}

	private void drawSprites(uint y, bool clearBackdrop, scope ref PpuPixelPrioBufs bgBuffer, scope const ref PpuPixelPrioBufs objBuffer, const PpuWindows win) const @safe pure {
		foreach (edges; win.validEdges) {
			const left = edges[0];
			const width = edges[1] - left;
			auto src = objBuffer.data[left + kPpuExtraLeftRight .. $];
			auto dst = bgBuffer.data[left + kPpuExtraLeftRight .. $];
			if (clearBackdrop) {
				dst[0 .. min($, width * ushort.sizeof)] = src[0 .. min($, width * ushort.sizeof)];
			} else {
				foreach (_; 0 .. width) {
					if (src[0].priority > dst[0].priority) {
						dst[0] = src[0];
					}
					src = src[1 .. $];
					dst = dst[1 .. $];
				}
			}
		}
	}


	void setMode7PerspectiveCorrection(int low, int high) @safe pure {
		mode7PerspectiveLow = low ? 1.0f / low : 0.0f;
		mode7PerspectiveHigh = 1.0f / high;
	}

	void setExtraSideSpace(int left, int right, int bottom) @safe pure {
		extraLeftCur = cast(ubyte)min(left, extraLeftRight);
		extraRightCur = cast(ubyte)min(right, extraLeftRight);
		extraBottomCur = cast(ubyte)min(bottom, 16);
	}

	// Upsampled version of mode7 rendering. Draws everything in 4x the normal resolution.
	// Draws directly to the pixel buffer and bypasses any math, and supports only
	// a subset of the normal features (all that zelda needs)
	private void drawMode7Upsampled(Array2D!ColourFormat renderBuffer, scope ref PpuPixelPrioBufs objBuffer, uint y) const @safe pure {
		// expand 13-bit values to signed values
		const xCenter = (cast(short)(m7matrix[4] << 3)) >> 3, yCenter = (cast(short)(m7matrix[5] << 3)) >> 3;
		const clippedH = ((cast(short)(m7matrix[6] << 3)) >> 3) - xCenter;
		const clippedV = ((cast(short)(m7matrix[7] << 3)) >> 3) - yCenter;
		int[4] m0v;
		if (*cast(const(uint)*)&mode7PerspectiveLow == 0) {
			m0v[] = m7matrix[0] << 12;
		} else {
			static immutable float[4] kInterpolateOffsets = [ -1, -1 + 0.25f, -1 + 0.5f, -1 + 0.75f ];
			for (int i = 0; i < 4; i++) {
				m0v[i] = cast(int)(4096.0f / interpolate(cast(int)y + kInterpolateOffsets[i], 0, 223, mode7PerspectiveLow, mode7PerspectiveHigh));
			}
		}
		auto render_buffer_ptr = renderBuffer[0 .. $, (y - 1) * 4 .. y * 4];
		const draw_width = 256 + extraLeftCur + extraRightCur;
		const m1 = m7matrix[1] << 12; // xpos increment per vert movement
		const m2 = m7matrix[2] << 12; // ypos increment per horiz movement
		for (int j = 0; j < 4; j++) {
			const m0 = m0v[j], m3 = m0;
			uint xpos = m0 * clippedH + m1 * (clippedV + y) + (xCenter << 20), xcur;
			uint ypos = m2 * clippedH + m3 * (clippedV + y) + (yCenter << 20), ycur;

			xpos -= (m0 + m1) >> 1;
			ypos -= (m2 + m3) >> 1;
			xcur = (xpos << 2) + j * m1;
			ycur = (ypos << 2) + j * m3;

			xcur -= extraLeftCur * 4 * m0;
			ycur -= extraLeftCur * 4 * m2;

			foreach (ref destPixel; render_buffer_ptr[0 .. draw_width * 4, j]) {
				const tile = vram[(ycur >> 25 & 0x7f) * 128 + (xcur >> 25 & 0x7f)] & 0xff;
				auto pixel = vram[tile * 64 + (ycur >> 22 & 7) * 8 + (xcur >> 22 & 7)] >> 8;
				pixel = (xcur & 0x80000000) ? 0 : pixel;
				destPixel = halfColor ? integerToColour!ColourFormat((colourToInteger(colorMapRgb[pixel]) & 0xfefefe) >> 1) : colorMapRgb[pixel];
				xcur += m0;
				ycur += m2;
			}
		}

		if (lineHasSprites) {
			auto dst = render_buffer_ptr[0 .. $, 0];
			const pixels = objBuffer.data[kPpuExtraLeftRight - extraLeftCur .. $];
			for (size_t i = 0; i < draw_width; i++, dst = dst[16 .. $]) {
				uint pixel = pixels[i].pixel;
				if (pixel) {
					dst[0 .. 7][] = colorMapRgb[pixel];
				}
			}
		}

		if (extraLeftRight - extraLeftCur != 0) {
			const n = 4 * uint.sizeof * (extraLeftRight - extraLeftCur);
			for(int i = 0; i < 4; i++) {
				render_buffer_ptr[0 .. n, i] = ColourFormat(0, 0, 0);
			}
		}
		if (extraLeftRight - extraRightCur != 0) {
			const n = 4 * uint.sizeof * (extraLeftRight - extraRightCur);
			for (int i = 0; i < 4; i++) {
				const start = 256 + extraLeftRight * 2 - (extraLeftRight - extraRightCur);
				render_buffer_ptr[start .. $, i] = ColourFormat(0, 0, 0);
			}
		}
	}

	private void drawBackgrounds(int y, bool sub, scope ref PpuPixelPrioBufs[3] winBuffers) const @safe pure {
		// Top 4 bits contain the prio level, and bottom 4 bits the layer num
		// split into minimums and maximums
		enum ubyte[2][4][2][8] priorityTable = [
			0: [[[11, 8], [10, 7], [5, 2], [4, 1]], [[11, 8], [10, 7], [5, 2], [4, 1]]],
			1: [[[11, 8], [10, 7], [2, 1], [0, 0]], [[11, 8], [10, 7], [15, 5], [0, 0]]],
			2: [[[11, 5], [8, 2], [0, 0], [0, 0]], [[11, 5], [8, 2], [0, 0], [0, 0]]],
			3: [[[11, 5], [8, 2], [0, 0], [0, 0]], [[11, 5], [8, 2], [0, 0], [0, 0]]],
			4: [[[11, 5], [8, 2], [0, 0], [0, 0]], [[11, 5], [8, 2], [0, 0], [0, 0]]],
			5: [[[11, 5], [8, 2], [0, 0], [0, 0]], [[11, 5], [8, 2], [0, 0], [0, 0]]],
			6: [[[11, 5], [0, 0], [0, 0], [0, 0]], [[11, 5], [0, 0], [0, 0], [0, 0]]],
			7: [[[11, 5], [0, 0], [0, 0], [0, 0]], [[11, 5], [0, 0], [0, 0], [0, 0]]],
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
			const layer = 4;
			const mainSub = sub ? layers[layer].sub : layers[layer].main;
			if (mainSub.screenEnabled) {
				const win = mainSub.windowEnabled ? windowsCalc(layer) : windowsClear(layer);
				drawSprites(y, mode != 7, winBuffers[sub], winBuffers[2], win);
			}
		}
		sw: switch (mode) {
			static foreach (i; 0 .. 8) {
				case i:
					static foreach (LayerID layer; LayerID.bg1 .. cast(LayerID)(LayerID.bg4 + 1)) {{
						enum bpp = bgBPP[i][layer];
						static if (bpp > 0) {
							const mainSub = sub ? layers[layer].sub : layers[layer].main;
							if (mainSub.screenEnabled) {
								const priorityHigh = cast(ubyte)((priorityTable[i][bg3Priority][layer][0] << 4) | layer);
								const priorityLow = cast(ubyte)((priorityTable[i][bg3Priority][layer][1] << 4) | layer);
								const win = mainSub.windowEnabled ? windowsCalc(layer) : windowsClear(layer);
								drawBackground!bpp(y, layer, [priorityLow, priorityHigh], winBuffers[sub], win);
							}
						}
					}}
					break sw;
			}
			default:
				assert(0);
		}
	}

	// new renderer
	private void drawWholeLine(Array2D!ColourFormat renderBuffer, scope ref PpuPixelPrioBufs[3] winBuffers, uint y) const @safe pure {
		if (forcedBlank) {
			renderBuffer[0 .. $, y - 1] = ColourFormat(0, 0, 0);
			return;
		}

		if (mode == 7 && (renderFlags.mode74x4)) {
			drawMode7Upsampled(renderBuffer, winBuffers[2], y);
			return;
		}

		// Default background is backdrop
		ClearBackdrop(winBuffers[0]);

		// Render main screen
		drawBackgrounds(y, false, winBuffers);

		// Render also the subscreen?
		if (preventMathMode != ColourMathEnabled.never && addSubscreen && mathEnabled) {
			ClearBackdrop(winBuffers[1]);
			drawBackgrounds(y, true, winBuffers);
		}

		// Color window affects the drawing mode in each region
		const cwin = windowsCalc(5);
		static immutable ubyte[4] keepBits = [
			0x00, 0xFF, 0xFF, 0x00,
		];
		static immutable ubyte[4] flipBits = [
			0xFF, 0x00, 0xFF, 0x00,
		];
		auto clipMath = only(clipMode, preventMathMode).map!(x => bitRangeOf((cwin.bits & keepBits[x]) ^ flipBits[x]));

		auto dst_org = renderBuffer[0 .. $, y - 1];
		auto dst = dst_org[extraLeftRight - extraLeftCur .. $];

		foreach (idx, edges; cwin.allEdges.enumerate) {
			const left = edges[0] + kPpuExtraLeftRight;
			const right = edges[1] + kPpuExtraLeftRight;
			// If clip is set, then zero out the rgb values from the main screen.
			const clipColourMask = clipMath[0][idx] ? 0x1F : 0;
			uint colourMathEnabled = clipMath[1][idx] ? mathEnabled : 0;
			const fixedColour = BGR555(fixedColorR, fixedColorG, fixedColorB);
			const halfColourMap = halfColor ? brightnessMultHalf : brightnessMult;
			// Store this in locals
			colourMathEnabled |= addSubscreen << 8 | subtractColor << 9;
			// Need to check for each pixel whether to use math or not based on the main screen layer.
			foreach (i; left .. right) {
				const color = cgram[winBuffers[0].data[i].pixel];
				BGR555 color2;
				const mainLayer = winBuffers[0].data[i].layer;
				uint r = color.red & clipColourMask;
				uint g = color.green & clipColourMask;
				uint b = color.blue & clipColourMask;
				const(ubyte)[] colourMap = brightnessMult;
				if (colourMathEnabled & (1 << mainLayer)) {
					if (colourMathEnabled & 0x100) { // addSubscreen ?
						if (winBuffers[1].data[i].pixel != 0) {
							color2 = cgram[winBuffers[1].data[i].pixel];
							colourMap = halfColourMap;
						} else {// Don't halve if addSubscreen && backdrop
							color2 = fixedColour;
						}
					} else {
						color2 = fixedColour;
						colourMap = halfColourMap;
					}
					if (colourMathEnabled & 0x200) { // subtractColor?
						r = (r >= color2.red) ? r - color2.red : 0;
						g = (g >= color2.green) ? g - color2.green : 0;
						b = (b >= color2.blue) ? b - color2.blue : 0;
					} else {
						r += color2.red;
						g += color2.green;
						b += color2.blue;
					}
				}
				dst[0] = ColourFormat(colourMap[r], colourMap[g], colourMap[b]);
				dst = dst[1 .. $];
			}
		}

		// Clear out stuff on the sides.
		if (extraLeftRight - extraLeftCur != 0) {
			dst_org[0 .. uint.sizeof * (extraLeftRight - extraLeftCur)] = ColourFormat(0, 0, 0);
		}
		if (extraLeftRight - extraRightCur != 0) {
			const start = 256 + extraLeftRight * 2 - (extraLeftRight - extraRightCur);
			dst_org[start .. start + uint.sizeof * (extraLeftRight - extraRightCur)] = ColourFormat(0, 0, 0);
		}
	}
	private bool shouldDoClipMath(T)(int x, T value) const @safe pure {
		const colorWindowState = getWindowState(5, x);
		return (value == T.always) ||
			((value == T.mathWindow) && colorWindowState) ||
			((value == T.notMathWindow) && !colorWindowState);
	}
	private bool shouldForceMainScreenBlack(int x) const @safe pure => shouldDoClipMath(x, clipMode);
	private bool colourMathEnabled(int x) const @safe pure => shouldDoClipMath(x, preventMathMode);
	// old renderer
	private void handlePixel(Array2D!ColourFormat renderBuffer, scope ref PpuPixelPrioBufs objBuffer, int x, int y) const @safe pure {
		BGR555 colour1;
		BGR555 colour2;
		if (!forcedBlank) {
			int mainLayer = getPixel(x, y, false, colour1, objBuffer);

			if (shouldForceMainScreenBlack(x)) {
				colour1 = BGR555(0, 0, 0);
			}
			int secondLayer = LayerID.math; // backdrop
			const mathEnabled = mainLayer < 6 && (mathEnabled & (1 << mainLayer)) && colourMathEnabled(x);
			if ((mathEnabled && addSubscreen) || mode == 5 || mode == 6) {
				secondLayer = getPixel(x, y, true, colour2, objBuffer);
			}
			// TODO: subscreen pixels can be clipped to black as well
			// TODO: math for subscreen pixels (add/sub sub to main)
			if (mathEnabled) {
				auto r = colour1.red;
				auto g = colour1.green;
				auto b = colour1.blue;
				if (subtractColor) {
					r -= (addSubscreen && secondLayer != LayerID.math) ? colour2.red: fixedColorR;
					g -= (addSubscreen && secondLayer != LayerID.math) ? colour2.green: fixedColorG;
					b -= (addSubscreen && secondLayer != LayerID.math) ? colour2.blue: fixedColorB;
				} else {
					r += (addSubscreen && secondLayer != LayerID.math) ? colour2.red : fixedColorR;
					g += (addSubscreen && secondLayer != LayerID.math) ? colour2.green : fixedColorG;
					b += (addSubscreen && secondLayer != LayerID.math) ? colour2.blue : fixedColorB;
				}
				if (halfColor && (secondLayer != LayerID.math || !addSubscreen)) {
					r >>= 1;
					g >>= 1;
					b >>= 1;
				}
				colour1.red = cast(ubyte)clamp(r, short(0), short(31));
				colour1.green = cast(ubyte)clamp(g, short(0), short(31));
				colour1.blue = cast(ubyte)clamp(b, short(0), short(31));
			}
			if (!(mode == 5 || mode == 6)) {
				colour2 = colour1;
			}
		}
		int row = y - 1;
		renderBuffer[x + extraLeftRight, row] = ColourFormat(brightnessMult[colour1.red], brightnessMult[colour1.green], brightnessMult[colour1.blue]);
	}

	static immutable int[4][10] bitDepthsPerMode = [
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

	private int getPixel(int x, int y, bool sub, ref BGR555 colour, scope ref PpuPixelPrioBufs objBuffer) const @safe pure {
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
			const mainSub = sub ? layers[curLayer].sub : layers[curLayer].main;
			layerActive = mainSub.screenEnabled && (!mainSub.windowEnabled || !getWindowState(curLayer, x));
			if (layerActive) {
				if (curLayer < 4) {
					// bg layer
					int lx = x;
					int ly = y;
					if (layers[curLayer].mosaic) {
						lx -= lx % mosaicSize;
						ly -= (ly - 1) % mosaicSize;
					}
					if (mode == 7) {
						pixel = getPixelForMode7(lx, curLayer, !!curPriority);
					} else {
						lx += layers[curLayer].hScroll;
						ly += layers[curLayer].vScroll;
						pixel = getPixelForBGLayer(
							lx & 0x3ff, ly & 0x3ff,
							curLayer, !!curPriority
						);
					}
				} else {
					// get a pixel from the sprite buffer
					pixel = 0;
					if ((objBuffer.data[x + kPpuExtraLeftRight].priority >> 4) == SPRITE_PRIO_TO_PRIO_HI(curPriority)) {
						pixel = objBuffer.data[x + kPpuExtraLeftRight].pixel;
					}
				}
			}
			if (pixel > 0) {
				layer = curLayer;
				break;
			}
		}
		colour = cgram[pixel & 0xff];
		if (layer == 4 && pixel < 0xc0) {
			layer = 6; // sprites with palette color < 0xc0
		}
		return layer;

	}


	private int getPixelForBGLayer(int x, int y, int layer, bool priority) const @safe pure {
		const layerp = layers[layer];
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
		const tile = (cast(const(TilemapEntry)[])vram)[tilemapAdr & 0x7fff];
		// check priority, get palette
		if (tile.priority != priority) {
			return 0; // wrong priority
		}
		int paletteNum = tile.palette;
		// figure out position within tile
		int row = tile.flipVertical ? 7 - (y & 0x7) : (y & 0x7);
		int col = tile.flipHorizontal ? (x & 0x7) : 7 - (x & 0x7);
		int tileNum = tile.index;
		if (wideTiles) {
			// if unflipped right half of tile, or flipped left half of tile
			if ((cast(bool)(x & 8)) ^ tile.flipVertical) {
				tileNum += 1;
			}
		}
		tileNum &= 0x3FF;
		// read tiledata, ajust palette for mode 0
		int bitDepth = bitDepthsPerMode[mode][layer];
		if (mode == 0) {
			paletteNum += 8 * layer;
		}
		// plane 1 (always)
		int paletteSize = 4;
		ushort plane1 = vram[(layerp.tileAdr + (tileNum * 4 * bitDepth) + row) & 0x7fff];
		int pixel = (plane1 >> col) & 1;
		pixel |= ((plane1 >> (8 + col)) & 1) << 1;
		// plane 2 (for 4bpp, 8bpp)
		if (bitDepth > 2) {
			paletteSize = 16;
			ushort plane2 = vram[(layerp.tileAdr + (tileNum * 4 * bitDepth) + 8 + row) & 0x7fff];
			pixel |= ((plane2 >> col) & 1) << 2;
			pixel |= ((plane2 >> (8 + col)) & 1) << 3;
		}
		// plane 3 & 4 (for 8bpp)
		if (bitDepth > 4) {
			paletteSize = 256;
			ushort plane3 = vram[(layerp.tileAdr + (tileNum * 4 * bitDepth) + 16 + row) & 0x7fff];
			pixel |= ((plane3 >> col) & 1) << 4;
			pixel |= ((plane3 >> (8 + col)) & 1) << 5;
			ushort plane4 = vram[(layerp.tileAdr + (tileNum * 4 * bitDepth) + 24 + row) & 0x7fff];
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
		if(layers[0].mosaic) {
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

	private int getPixelForMode7(int x, int layer, bool priority) const @safe pure {
		if (layers[layer].mosaic) {
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

	private bool getWindowState(int layer, int x) const @safe pure {
		const winflags = layers[layer];
		if (!winflags.window1Enabled && !winflags.window2Enabled) {
			return false;
		}
		if (winflags.window1Enabled && !winflags.window2Enabled) {
			bool test = x >= window1left && x <= window1right;
			return winflags.window1Inverted ? !test : test;
		}
		if (!winflags.window1Enabled && winflags.window2Enabled) {
			bool test = x >= window2left && x <= window2right;
			return winflags.window2Inverted ? !test : test;
		}
		bool test1 = x >= window1left && x <= window1right;
		if (winflags.window1Inverted) {
			test1 = !test1;
		}
		bool test2 = x >= window2left && x <= window2right;
		if (winflags.window2Inverted) {
			test2 = !test2;
		}
		return test1 || test2;
	}

	private bool evaluateSprites(int line, scope ref PpuPixelPrioBufs objBuffer) const @safe pure {
		int spritesLeft = 32 + 1, tilesLeft = 34 + 1;
		const spriteSizes = kSpriteSizes[objSize];
		if (renderFlags.noSpriteLimits) {
			spritesLeft = tilesLeft = 1024;
		}
		int tilesLeftOrg = tilesLeft;

		foreach (lowOBJ, highOBJ; zip(oam[], oamHigh[].map!(x => only((x >> 0) & 3, (x >> 2) & 3, (x >> 4) & 3, (x >> 6) & 3)).joiner)) {
			int yy = lowOBJ.yCoord;
			const spriteSize = spriteSizes[highOBJ >> 1];
			if ((yy == 240) && (spriteSize < 32)) { // small sprites are completely offscreen here
				continue;
			}
			// check if the sprite is on this line and get the sprite size
			int row = (line - yy) & 0xff;
			if (row >= spriteSize) {
				continue;
			}
			// right edge wraps around to -256
			int x = lowOBJ.xCoord + (highOBJ & 1) * 256;
			x -= (x >= 256 + extraLeftRight) * 512;
			// still on screen?
			if (x <= -(spriteSize + extraLeftRight)) {
				continue;
			}
			// check against the sprite limit
			if (--spritesLeft == 0) {
				break;
			}
			// get some data for the sprite and y-flip row if needed
			const objAdr = (lowOBJ.tile & 0x100) ? objTileAdr2 : objTileAdr1;
			if (lowOBJ.flipVertical) {
				row = spriteSize - 1 - row;
			}
			// fetch all tiles in x-range
			const paletteBase = cast(ubyte)(8 + lowOBJ.palette);
			const prio = SPRITE_PRIO_TO_PRIO(lowOBJ.priority, (lowOBJ.palette & 8) == 0);

			for (int col = 0; col < spriteSize; col += 8) {
				if (col + x > -8 - extraLeftRight && col + x < 256 + extraLeftRight) {
					// can only draw 34 tiles per line
					if (--tilesLeft == 0) {
						return true;
					}
					// figure out which tile this uses, looping within 16x16 pages, and get it's data
					int usedCol = autoFlip(col, lowOBJ.flipHorizontal, spriteSize);
					int usedTile = (((lowOBJ.startingTile >> 4) + (row >> 3)) << 4) | (((lowOBJ.startingTile & 0xf) + (usedCol >> 3)) & 0xf);
					auto addr = vram[(objAdr + usedTile * 16 + (row & 0x7)) & 0x7fff .. $];
					uint plane = addr[0] | addr[8] << 16;
					// go over each pixel
					int px_left = max(-(col + x + kPpuExtraLeftRight), 0);
					int px_right = min(256 + kPpuExtraLeftRight - (col + x), 8);
					auto dst = objBuffer.data[col + x + px_left + kPpuExtraLeftRight .. $];

					for (int px = px_left; px < px_right; px++) {
						int shift = autoFlip(px, !lowOBJ.flipHorizontal);
						uint bits = plane >> shift;
						ubyte pixel = (bits >> 0) & 1 | (bits >> 7) & 2 | (bits >> 14) & 4 | (bits >> 21) & 8;
						// draw it in the buffer if there is a pixel here, and the buffer there is still empty
						if (pixel != 0 && (dst[px - px_left].pixel == 0)) {
							// sprites are always 4BPP
							dst[px - px_left] = ZBufType(prio, pixel, paletteBase, 4);
						}
					}
				}
			}
		}
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
		void setWinSel(size_t layer, ubyte value) {
			layers[layer].window1Inverted = !!(value & (1 << 0));
			layers[layer].window1Enabled = !!(value & (1 << 1));
			layers[layer].window2Inverted = !!(value & (1 << 2));
			layers[layer].window2Enabled = !!(value & (1 << 3));
		}
		const adr = address & 0xFF;
		switch (adr) {
			case 0x00: // INIDISP
				brightness = val & 0xf;
				forcedBlank = !!(val & 0x80);
				break;
			case 0x01: //OBSEL
				objSize = val >> 5;
				objTileAdr1 = (val & 0b0000_0111) << 13;
				objTileAdr2 = cast(ushort)(objTileAdr1 + (((val & 0b0001_1000) + 1) << 12));
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
					if (oamAdr < 0x110) {
						(cast(ushort[])oam)[oamAdr++] = (val << 8) | oamBuffer;
					}
				}
				oamSecondWrite = !oamSecondWrite;
				break;
			case 0x05: // BGMODE
				mode = val & 0b00000111;
				bg3Priority = !!(val & 0b00001000);
				layers[0].doubleTileSize = !!(val & 0b00010000);
				layers[1].doubleTileSize = !!(val & 0b00100000);
				layers[2].doubleTileSize = !!(val & 0b01000000);
				layers[3].doubleTileSize = !!(val & 0b10000000);
				break;
			case 0x06: // MOSAIC
				mosaicSize = (val >> 4) + 1;
				if (mosaicSize > 1) {
					layers[0].mosaic = !!(val & 0b00000001);
					layers[1].mosaic = !!(val & 0b00000010);
					layers[2].mosaic = !!(val & 0b00000100);
					layers[3].mosaic = !!(val & 0b00001000);
				}
				break;
			case 0x07: // BG1SC
			case 0x08: // BG2SC
			case 0x09: // BG3SC
			case 0x0a: //BG4SC
				layers[adr - 7].tilemapWider = val & 0x1;
				layers[adr - 7].tilemapHigher = !!(val & 0x2);
				layers[adr - 7].tilemapAdr = (val & 0xfc) << 8;
				break;
			case 0x0b: // BG12NBA
				layers[0].tileAdr = (val & 0xf) << 12;
				layers[1].tileAdr = (val & 0xf0) << 8;
				break;
			case 0x0c: // BG34NBA
				layers[2].tileAdr = (val & 0xf) << 12;
				layers[3].tileAdr = (val & 0xf0) << 8;
				break;
			case 0x0d: // BG1HOFS
				m7matrix[6] = ((val << 8) | m7prev) & 0x1fff;
				m7prev = val;
				goto case;
			case 0x0f: //BG2HOFS
			case 0x11: //BG3HOFS
			case 0x13: // BG4HOFS
				layers[(adr - 0xd) / 2].hScroll = ((val << 8) | (scrollPrev & 0xf8) | (scrollPrev2 & 0x7)) & 0x3ff;
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
				layers[(adr - 0xe) / 2].vScroll = ((val << 8) | scrollPrev) & 0x3ff;
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
					cgram[cgramPointer++] = integerToColour!BGR555((val << 8) | cgramBuffer);
				}
				cgramSecondWrite = !cgramSecondWrite;
				break;
			case 0x23: // W12SEL
				setWinSel(0, val & 0xF);
				setWinSel(1, val >> 4);
				break;
			case 0x24: // W34SEL
				setWinSel(2, val & 0xF);
				setWinSel(3, val >> 4);
				break;
			case 0x25: // WOBJSEL
				setWinSel(4, val & 0xF);
				setWinSel(5, val >> 4);
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
				layers[0].maskLogic = cast(MaskLogic)(val & 3);
				layers[1].maskLogic = cast(MaskLogic)((val >> 2) & 3);
				layers[2].maskLogic = cast(MaskLogic)((val >> 4) & 3);
				layers[3].maskLogic = cast(MaskLogic)((val >> 6) & 3);
				break;
			case 0x2b: // WOBJLOG
				layers[4].maskLogic = cast(MaskLogic)(val & 3);
				layers[5].maskLogic = cast(MaskLogic)((val >> 2) & 3);
				break;
			case 0x2c: // TM
				foreach (layer; 0 .. 5) {
					layers[layer].main.screenEnabled = !!(val & (1 << layer));
				}
				break;
			case 0x2d: // TS
				foreach (layer; 0 .. 5) {
					layers[layer].sub.screenEnabled = !!(val & (1 << layer));
				}
				break;
			case 0x2e: // TMW
				foreach (layer; 0 .. 5) {
					layers[layer].main.windowEnabled = !!(val & (1 << layer));
				}
				break;
			case 0x2f: // TSW
				foreach (layer; 0 .. 5) {
					layers[layer].sub.windowEnabled = !!(val & (1 << layer));
				}
				break;
			case 0x30: // CGWSEL
				const parsed = CGWSELValue(val);
				//assert(parsed.directColour); // direct colour not supported yet
				addSubscreen = parsed.subscreenEnable;
				preventMathMode = parsed.mathPreventMode;
				clipMode = parsed.mathClipMode;
				break;
			case 0x31: // CGADSUB
				const parsed = CGADSUBValue(val);
				halfColor = parsed.enableHalf;
				subtractColor = parsed.enableSubtract;
				mathEnabled = parsed.layers;
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
	void debugUI(UIState state) {
		if (ImGui.BeginTabBar("rendererpreview")) {
			if (ImGui.BeginTabItem("State")) {
				ImGui.Text("BG mode: %d", mode);
				ImGui.Text("Brightness: %d", brightness);
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Sprites")) {
				.drawSprites!BGR555(oam.length, state, 64, 64, (canvas, index) {
					canvas[] = BGR555(31, 0, 31); // placeholder until we have some real drawing code
				}, (index) {
					const entry = oam[index];
					const uint upperX = !!(oamHigh[index / 4] & (1 << ((index % 4) * 2)));
					const size = !!(oamHigh[index / 4] & (1 << ((index % 4) * 2 + 1)));
					ImGui.BeginDisabled();
					ImGui.Text(format!"Tile Offset: %s"(entry.startingTile));
					ImGui.Text(format!"Coords: (%s, %s)"(entry.xCoord + (upperX << 8), entry.yCoord));
					ImGui.Text(format!"Palette: %s"(entry.palette));
					bool boolean = entry.flipVertical;
					ImGui.Checkbox("Vertical flip", &boolean);
					boolean = entry.flipHorizontal;
					ImGui.Checkbox("Horizontal flip", &boolean);
					ImGui.Text(format!"Priority: %s"(entry.priority));
					boolean = size;
					ImGui.Checkbox("Use alt size", &boolean);
					ImGui.EndDisabled();
				});
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Palettes")) {
				showPalette(cgram[], 16);
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Layers")) {
				static foreach (layer, label; ["BG1", "BG2", "BG3", "BG4"]) {{
					if (ImGui.TreeNode(label)) {
						ImGui.Text(format!"Tilemap address: $%04X"(layers[layer].tilemapAdr));
						ImGui.Text(format!"Tile base address: $%04X"(layers[layer].tileAdr));
						ImGui.Text(format!"Size: %s"(["32x32", "64x32", "32x64", "64x64"][layers[layer].tilemapWider + (layers[layer].tilemapHigher << 1)]));
						//ImGui.Text(format!"Tile size: %s"(["8x8", "16x16"][!!(BGMODE >> (4 + layer))]));
						//disabledCheckbox("Mosaic Enabled", !!((MOSAIC >> layer) & 1));
						ImGui.TreePop();
					}
				}}
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("VRAM")) {
				static void* surface;
				drawZoomableTiles(cast(Intertwined4BPP[])vram, cast(BGR555[16][])cgram, state, surface);
				ImGui.EndTabItem();
			}
			ImGui.EndTabBar();
		}
	}
}

immutable ubyte[2][8] kSpriteSizes = [
	[8, 16], [8, 32], [8, 64], [16, 32],
	[16, 64], [32, 64], [16, 32], [16, 32]
];

struct PpuWindows {
	short[6] edges;
	ubyte nr;
	ubyte bits;
	auto validEdges() const {
		return zip(iota(edges.length), edges[].slide(2)).filter!(x => !(bits & (1 << x[0]))).map!(x => x[1]).take(nr);
	}
	auto allEdges() const {
		return edges[0 .. nr + 1].slide(2);
	}
}

unittest {
	import replatform64.dumping : writePNG;
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
	static Array2D!(PPU.ColourFormat) draw(ref PPU ppu, FauxDMA[] dma, PPURenderFlags flags) {
		auto buffer = Array2D!(PPU.ColourFormat)(width, height);
		ppu.beginDrawing(flags);
		foreach (i; 0 .. height + 1) {
			foreach (write; dma) {
				if (write.scanline + 1 == i) {
					ppu.writeRegister(cast(ushort)write.register, write.value);
				}
			}
			ppu.runLine(buffer, i);
		}
		return buffer;
	}
	static Array2D!(PPU.ColourFormat) renderMesen2State(const(ubyte)[] file, FauxDMA[] dma, PPURenderFlags flags) {
		PPU ppu;
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
					CGWSEL.mathPreventMode = cast(ColourMathEnabled)(intData & 0b00000011);
					break;
				case "ppu.colorMathClipMode":
					CGWSEL.mathClipMode = cast(MathClipMode)(intData & 0b00000011);
					break;
				case "ppu.colorMathEnabled":
					CGADSUB.layers = byteData & 0b00111111;
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
					COLDATAR |= (shortData & 0b000000000011111) >> 0;
					COLDATAG |= (shortData & 0b000001111100000) >> 5;
					COLDATAB |= (shortData & 0b111110000000000) >> 10;
					break;
				case "ppu.vram":
					ppu.vram[] = cast(const(ushort)[])data;
					break;
				case "ppu.oamRam":
					ppu.oam[] = cast(const(OAMEntry)[])data[0 .. 0x200];
					ppu.oamHigh[] = data[0x200 .. 0x220];
					break;
				case "ppu.cgram":
					ppu.cgram[] = cast(const(BGR555)[])data;
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
		return draw(ppu, dma, flags);
	}
	const result = // we don't want short-circuiting, so use & instead of &&
		runTests!renderMesen2State("snes", "old", cast(PPURenderFlags)0) &
		runTests!renderMesen2State("snes", "new", PPURenderFlags.newRenderer);
	assert(result, "Tests failed");
}

private float interpolate(float x, float xmin, float xmax, float ymin, float ymax) @safe pure {
	return ymin + (ymax - ymin) * (x - xmin) * (1.0f / (xmax - xmin));
}

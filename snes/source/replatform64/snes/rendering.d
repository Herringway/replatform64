module replatform64.snes.rendering;

import replatform64.backend.common;
import replatform64.common;
import replatform64.snes.bsnes.renderer;
import replatform64.snes.hardware;
import replatform64.snes.ppu;
import replatform64.ui;

import std.bitmanip;
import std.exception;
import std.logger;
import std.range;
import std.stdio;

import arsd.png;

enum Renderer {
	bsnes,
	neo,
}

SNESRenderer renderer;

struct RendererSettings {
	Renderer engine = Renderer.bsnes;
}

struct SNESRenderer {
	private enum defaultWidth = 256;
	private enum defaultHeight = 224;
	private SnesDrawFrameData bsnesFrame;
	private PPU neoRenderer;
	private HDMAWrite[4*8*240] neoHDMAData;
	private ushort neoNumHDMA;
	ushort width = defaultWidth;
	ushort height = defaultHeight;
	private Renderer renderer;
	private VideoBackend backend;

	void initialize(string title, VideoBackend newBackend, RendererSettings rendererSettings) {
		this.renderer = rendererSettings.engine;
		PixelFormat textureType;
		final switch (rendererSettings.engine) {
			case Renderer.bsnes:
				textureType = PixelFormat.rgb555;
				width = defaultWidth * 2;
				height = defaultHeight * 2;
				enforce(loadSnesDrawFrame(), "Could not load SnesDrawFrame");
				enforce(initSnesDrawFrame(), "Could not initialize SnesDrawFrame");
				break;
			case Renderer.neo:
				textureType = PixelFormat.argb8888;
				neoRenderer.extraLeftRight = (defaultWidth - 256) / 2;
				neoRenderer.setExtraSideSpace((defaultWidth - 256) / 2, (defaultWidth - 256) / 2, (defaultHeight - 224) / 2);
				break;
		}
		WindowSettings window;
		window.baseWidth = width;
		window.baseHeight = height;
		backend = newBackend;
		backend.createWindow(title, window);
		backend.createTexture(width, height, textureType);
	}
	void draw() {
		backend.startFrame();
		{
			Texture texture;
			backend.getDrawingTexture(texture);
			assert(texture.buffer.length > 0, "No buffer");
			draw(texture.buffer, texture.pitch);
		}
		backend.finishFrame();
	}
	private void draw(ubyte[] texture, int pitch) {
		final switch (renderer) {
			case Renderer.bsnes:
				.drawFrame(cast(ushort[])(texture[]), pitch, &bsnesFrame);
				break;
			case Renderer.neo:
				auto buffer = Array2D!uint(width, height, pitch / uint.sizeof, cast(uint[])texture);
				neoRenderer.beginDrawing(KPPURenderFlags.newRenderer);
				HDMAWrite[] hdmaTemp = neoHDMAData[0 .. neoNumHDMA];
				foreach (i; 0 .. height) {
					while ((hdmaTemp.length > 0) && (hdmaTemp[0].vcounter == i)) {
						neoRenderer.write(hdmaTemp[0].addr, hdmaTemp[0].value);
						hdmaTemp = hdmaTemp[1 .. $];
					}
					neoRenderer.runLine(buffer, i);
				}
				break;
		}
	}
	ushort[] getFrameData() {
		uint _;
		return getFrameData(_);
	}
	const(ubyte)[] getRGBA8888() {
		static union PixelConverter {
			ushort data;
			struct {
				mixin(bitfields!(
					ubyte, "r", 5,
					ubyte, "g", 5,
					ubyte, "b", 5,
					bool, "", 1,
				));
			}
		}
		uint stride;
		const source = cast(ubyte[])getFrameData(stride);
		if (renderer == Renderer.bsnes) {
			const(uint)[] result;
			result.reserve(width * height);
			foreach (rowRaw; source.chunks(stride)) {
				foreach (pixel; cast(const ushort[])rowRaw) {
					const pixelParsed = PixelConverter(pixel);
					result ~= 0xFF000000 | (pixelParsed.r << 19) | (pixelParsed.g << 11) | (pixelParsed.b << 3);
				}
			}
			return cast(const(ubyte)[])result;
		} else {
			return source;
		}
	}
	ushort[] getFrameData(out uint pitch) {
		final switch (renderer) {
			case Renderer.bsnes:
				pitch = 256 * 4;
				return .getFrameData(&bsnesFrame);
			case Renderer.neo:
				auto frame = new ubyte[](width * height * 4);
				pitch = width * 4;
				draw(frame, width * 4);
				return cast(ushort[])frame;
		}
	}
	ref inout(ushort) numHDMA() inout {
		final switch (renderer) {
			case Renderer.bsnes:
				return bsnesFrame.numHdmaWrites;
			case Renderer.neo:
				return neoNumHDMA;
		}
	}
	inout(HDMAWrite)[] hdmaData() inout {
		final switch (renderer) {
			case Renderer.bsnes:
				return bsnesFrame.hdmaData[];
			case Renderer.neo:
				return neoHDMAData[];
			}
	}
	ubyte[] vram() {
		final switch (renderer) {
			case Renderer.bsnes:
				return cast(ubyte[])bsnesFrame.vram[];
			case Renderer.neo:
				return cast(ubyte[])(neoRenderer.vram[]);
		}
	}
	ushort[] cgram() {
		final switch (renderer) {
			case Renderer.bsnes:
				return bsnesFrame.cgram[];
			case Renderer.neo:
				return neoRenderer.cgram[];
		}
	}
	OAMEntry[] oam1() {
		final switch (renderer) {
			case Renderer.bsnes:
				return cast(OAMEntry[])(bsnesFrame.oam1[]);
			case Renderer.neo:
				return neoRenderer.oam;
		}
	}
	ubyte[] oam2() {
		final switch (renderer) {
			case Renderer.bsnes:
				return bsnesFrame.oam2[];
			case Renderer.neo:
				return cast(ubyte[])(neoRenderer.oamHigh[]);
		}
	}
	const(ubyte)[] registers() const {
		final switch (renderer) {
			case Renderer.bsnes:
				return bsnesFrame.getRegistersConst;
			case Renderer.neo:
				return []; // unsupported
		}
	}
	const(HDMAWrite[]) allHDMAData() const {
		return hdmaData[0 .. numHDMA];
	}
	void writeRegister(ushort addr, ubyte value) @safe pure {
		final switch (renderer) {
			case Renderer.bsnes:
				bsnesFrame.writeRegister(addr, value);
				break;
			case Renderer.neo:
				neoRenderer.writeRegister(addr, value);
				break;
		}
	}
	ubyte readRegister(ushort addr) @safe pure {
		final switch (renderer) {
			case Renderer.bsnes:
				return bsnesFrame.readRegister(addr);
				break;
			case Renderer.neo:
				return neoRenderer.readRegister(addr);
				break;
		}
	}
	void debugUI(const UIState state, VideoBackend video) {
		final switch (renderer) {
			case Renderer.bsnes:
				return bsnesFrame.debugUI(state, video);
				break;
			case Renderer.neo:
				return neoRenderer.debugUI(state, video);
				break;
		}
	}
}

void writePalettedTilesPNG(string path, ushort[] data, ushort[] palette, uint tileWidth, uint tileHeight) {
	const imageWidth = tileWidth * 8;
	const imageHeight = tileHeight * 8;
	auto img = new IndexedImage(imageWidth, imageHeight);
	foreach (colour; renderer.cgram) {
		img.addColor(Color(((colour >> 10) & 0x1F) << 3, ((colour >> 5) & 0x1F) << 3, ((colour >> 0) & 0x1F) << 3));
	}
	foreach (idx, tile; (cast(ushort[])renderer.vram).chunks(16).enumerate) {
		const base = (idx % tileWidth) * 8 + (idx / tileWidth) * imageWidth * 8;
		foreach (p; 0 .. 8 * 8) {
			const px = p % 8;
			const py = p / 8;
			const plane01 = tile[py] & pixelPlaneMasks[px];
			const plane23 = tile[py + 8] & pixelPlaneMasks[px];
			const s = 7 - px;
			const pixel = ((plane01 & 0xFF) >> s) | (((plane01 >> 8) >> s) << 1) | (((plane23 & 0xFF) >> s) << 2) | (((plane23 >> 8) >> s) << 3);
			img.data[base + px + py * imageWidth] = cast(ubyte)pixel;
		}
	}
	writePng(path, img);
}

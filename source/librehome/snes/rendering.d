module librehome.snes.rendering;

import librehome.backend.common;
import librehome.snes.bsnes.renderer;
import librehome.snes.hardware;
import librehome.snes.ppu;

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

	void initialize(string title, WindowSettings settings, VideoBackend newBackend, Renderer renderer) {
		this.renderer = renderer;
		PixelFormat textureType;
		final switch (renderer) {
			case Renderer.bsnes:
				textureType = PixelFormat.rgb555;
				width = defaultWidth * 2;
				height = defaultHeight * 2;
				enforce(loadSnesDrawFrame(), "Could not load SnesDrawFrame");
				enforce(initSnesDrawFrame(), "Could not initialize SnesDrawFrame");
				info("SnesDrawFrame initialized");
				break;
			case Renderer.neo:
				textureType = PixelFormat.argb8888;
				neoRenderer.extraLeftRight = (defaultWidth - 256) / 2;
				neoRenderer.setExtraSideSpace((defaultWidth - 256) / 2, (defaultWidth - 256) / 2, (defaultHeight - 224) / 2);
				info("Neo initialized");
				break;
		}
		settings.width = width;
		settings.height = height;
		backend = newBackend;
		backend.initialize(null);
		backend.createWindow(title, settings);
		backend.createTexture(width, height, textureType);
	}
	void draw() {
		Texture texture;
		backend.getDrawingTexture(texture);
		assert(texture.buffer.length > 0, "No buffer");
		draw(texture.buffer, texture.pitch);
	}
	private void draw(ubyte[] texture, int pitch) {
		final switch (renderer) {
			case Renderer.bsnes:
				.drawFrame(cast(ushort[])(texture[]), pitch, &bsnesFrame);
				break;
			case Renderer.neo:
				neoRenderer.beginDrawing(texture, pitch, KPPURenderFlags.newRenderer);
				HDMAWrite[] hdmaTemp = neoHDMAData[0 .. neoNumHDMA];
				foreach (i; 0 .. height) {
					while ((hdmaTemp.length > 0) && (hdmaTemp[0].vcounter == i)) {
						neoRenderer.write(hdmaTemp[0].addr, hdmaTemp[0].value);
						hdmaTemp = hdmaTemp[1 .. $];
					}
					neoRenderer.runLine(i);
				}
				break;
		}
	}
	ushort[] getFrameData() {
		uint _;
		return getFrameData(_);
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
				return cast(OAMEntry[])(neoRenderer.oam[0 .. 0x100]);
		}
	}
	ubyte[] oam2() {
		final switch (renderer) {
			case Renderer.bsnes:
				return bsnesFrame.oam2[];
			case Renderer.neo:
				return cast(ubyte[])(neoRenderer.oam[0x100 .. $]);
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
	private  template Register(ubyte addr, string Reg) {
		alias T = typeof(__traits(getMember, bsnesFrame, Reg));
		static T remembered;
		T Register() {
			final switch (renderer) {
				case Renderer.bsnes:
					return __traits(getMember, bsnesFrame, Reg);
				case Renderer.neo:
					return remembered;
			}
		}
		void Register(T newValue) {
			final switch (renderer) {
				case Renderer.bsnes:
					__traits(getMember, bsnesFrame, Reg) = newValue;
					break;
				case Renderer.neo:
					remembered = newValue;
					static if (is(T : ubyte)) {
						neoRenderer.write(addr, newValue);
					} else {
						neoRenderer.write(addr, newValue & 0xFF);
						neoRenderer.write(addr, newValue >> 8);
					}
					break;
			}
		}
	}
	alias INIDISP = Register!(0x00, "INIDISP");
	alias OBSEL = Register!(0x01, "OBSEL");
	alias BGMODE = Register!(0x05, "BGMODE");
	ushort OAMADDR() {
		return bsnesFrame.OAMADDR;
	}
	alias MOSAIC = Register!(0x06, "MOSAIC");
	alias BG1SC = Register!(0x07, "BG1SC");
	alias BG2SC = Register!(0x08, "BG2SC");
	alias BG3SC = Register!(0x09, "BG3SC");
	alias BG4SC = Register!(0x0A, "BG4SC");
	alias BG12NBA = Register!(0x0B, "BG12NBA");
	alias BG34NBA = Register!(0x0C, "BG34NBA");
	alias BG1HOFS = Register!(0x0D, "BG1HOFS");
	alias BG1VOFS = Register!(0x0E, "BG1VOFS");
	alias BG2HOFS = Register!(0x0F, "BG2HOFS");
	alias BG2VOFS = Register!(0x10, "BG2VOFS");
	alias BG3HOFS = Register!(0x11, "BG3HOFS");
	alias BG3VOFS = Register!(0x12, "BG3VOFS");
	alias BG4HOFS = Register!(0x13, "BG4HOFS");
	alias BG4VOFS = Register!(0x14, "BG4VOFS");
	alias M7SEL = Register!(0x1A, "M7SEL");
	alias M7A = Register!(0x1B, "M7A");
	alias M7B = Register!(0x1C, "M7B");
	alias M7C = Register!(0x1D, "M7C");
	alias M7D = Register!(0x1E, "M7D");
	alias M7X = Register!(0x1F, "M7X");
	alias M7Y = Register!(0x20, "M7Y");
	alias W12SEL = Register!(0x23, "W12SEL");
	alias W34SEL = Register!(0x24, "W34SEL");
	alias WOBJSEL = Register!(0x25, "WOBJSEL");
	alias WH0 = Register!(0x26, "WH0");
	alias WH1 = Register!(0x27, "WH1");
	alias WH2 = Register!(0x28, "WH2");
	alias WH3 = Register!(0x29, "WH3");
	alias WBGLOG = Register!(0x2A, "WBGLOG");
	alias WOBJLOG = Register!(0x2B, "WOBJLOG");
	alias TM = Register!(0x2C, "TM");
	alias TS = Register!(0x2D, "TS");
	alias TMW = Register!(0x2E, "TMW");
	alias TSW = Register!(0x2F, "TSW");
	alias CGWSEL = Register!(0x30, "CGWSEL");
	alias CGADSUB = Register!(0x31, "CGADSUB");
	alias SETINI = Register!(0x33, "SETINI");
	ubyte FIXED_COLOUR_DATA_B() {
		return bsnesFrame.FIXED_COLOUR_DATA_B;
	}
	ubyte FIXED_COLOUR_DATA_G() {
		return bsnesFrame.FIXED_COLOUR_DATA_G;
	}
	ubyte FIXED_COLOUR_DATA_R() {
		return bsnesFrame.FIXED_COLOUR_DATA_R;
	}
	void FIXED_COLOUR_DATA_B(ubyte i) {
		bsnesFrame.FIXED_COLOUR_DATA_B = i;
	}
	void FIXED_COLOUR_DATA_G(ubyte i) {
		bsnesFrame.FIXED_COLOUR_DATA_G = i;
	}
	void FIXED_COLOUR_DATA_R(ubyte i) {
		bsnesFrame.FIXED_COLOUR_DATA_R = i;
	}
}

immutable ushort[8] pixelPlaneMasks = [
	0b1000000010000000,
	0b0100000001000000,
	0b0010000000100000,
	0b0001000000010000,
	0b0000100000001000,
	0b0000010000000100,
	0b0000001000000010,
	0b0000000100000001,
];

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

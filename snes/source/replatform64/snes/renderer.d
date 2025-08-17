module replatform64.snes.renderer;

import replatform64.snes.bsnes.renderer;
import replatform64.snes.hardware;
import replatform64.dumping;
import replatform64.ui;
import replatform64.util;

import std.bitmanip;
import std.exception;
import std.logger;
import std.range;
import std.stdio;

import pixelmancy.colours;
import bindbc.loader;

enum Renderer {
	autoSelect,
	bsnes,
	neo,
}

SNESRenderer renderer;

struct RendererSettings {
	Renderer engine = Renderer.autoSelect;
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
	PixelFormat textureType;

	void selectRenderer(RendererSettings rendererSettings) {
		if (rendererSettings.engine == Renderer.autoSelect) {
			rendererSettings.engine = (loadLibSFCPPU() == LoadMsg.success) ? Renderer.bsnes : Renderer.neo;
		}
		this.renderer = rendererSettings.engine;
		infof("Initializing SNES PPU renderer %s", this.renderer);
		final switch (rendererSettings.engine) {
			case Renderer.autoSelect: assert(0);
			case Renderer.bsnes:
				textureType = PixelFormatOf!(SnesDrawFrameData.ColourFormat);
				width = defaultWidth * 2;
				height = defaultHeight * 2;
				enforce(loadLibSFCPPU() == LoadMsg.success, "Could not load SnesDrawFrame");
				enforce(libsfcppu_init(), "Could not initialize SnesDrawFrame");
				break;
			case Renderer.neo:
				textureType = PixelFormatOf!(PPU.ColourFormat);
				neoRenderer.extraLeftRight = (defaultWidth - 256) / 2;
				neoRenderer.setExtraSideSpace((defaultWidth - 256) / 2, (defaultWidth - 256) / 2, (defaultHeight - 224) / 2);
				break;
		}
		infof("SNES PPU renderer initialized");
	}

	void draw(ubyte[] texture, int pitch) @safe {
		final switch (renderer) {
			case Renderer.autoSelect: assert(0);
			case Renderer.bsnes:
				alias Fmt = SnesDrawFrameData.ColourFormat;
				bsnesFrame.drawFrame(Array2D!Fmt(width, height, pitch / Fmt.sizeof, cast(Fmt[])(texture[])));
				break;
			case Renderer.neo:
				alias Fmt = PPU.ColourFormat;
				auto buffer = Array2D!Fmt(width, height, pitch / Fmt.sizeof, cast(Fmt[])texture);
				neoRenderer.beginDrawing(PPURenderFlags.newRenderer);
				HDMAWrite[] hdmaTemp = neoHDMAData[0 .. neoNumHDMA];
				foreach (i; 0 .. height) {
					while ((hdmaTemp.length > 0) && (hdmaTemp[0].vcounter == i)) {
						neoRenderer.writeRegister(hdmaTemp[0].addr, hdmaTemp[0].value);
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
	ushort[] getFrameData(out uint pitch) {
		final switch (renderer) {
			case Renderer.autoSelect: assert(0);
			case Renderer.bsnes:
				pitch = 256 * 4;
				return cast(ushort[])bsnesFrame.getFrameData();
			case Renderer.neo:
				auto frame = new ubyte[](width * height * 4);
				pitch = width * 4;
				draw(frame, width * 4);
				return cast(ushort[])frame;
		}
	}
	ref inout(ushort) numHDMA() inout return @safe pure {
		final switch (renderer) {
			case Renderer.autoSelect: assert(0);
			case Renderer.bsnes:
				return bsnesFrame.numHdmaWrites;
			case Renderer.neo:
				return neoNumHDMA;
		}
	}
	inout(HDMAWrite)[] hdmaData() inout return @safe pure {
		final switch (renderer) {
			case Renderer.autoSelect: assert(0);
			case Renderer.bsnes:
				return bsnesFrame.hdmaData[];
			case Renderer.neo:
				return neoHDMAData[];
			}
	}
	ubyte[] vram() return @safe pure {
		final switch (renderer) {
			case Renderer.autoSelect: assert(0);
			case Renderer.bsnes:
				return cast(ubyte[])bsnesFrame.vram[];
			case Renderer.neo:
				return cast(ubyte[])(neoRenderer.vram[]);
		}
	}
	ushort[] cgram() return @safe pure {
		final switch (renderer) {
			case Renderer.autoSelect: assert(0);
			case Renderer.bsnes:
				return bsnesFrame.cgram[];
			case Renderer.neo:
				return cast(ushort[])(neoRenderer.cgram[]);
		}
	}
	OAMEntry[] oam1() return @safe pure {
		final switch (renderer) {
			case Renderer.autoSelect: assert(0);
			case Renderer.bsnes:
				return cast(OAMEntry[])(bsnesFrame.oam1[]);
			case Renderer.neo:
				return neoRenderer.oam;
		}
	}
	ubyte[] oamFull() return @safe pure {
		final switch (renderer) {
			case Renderer.autoSelect: assert(0);
			case Renderer.bsnes:
				return bsnesFrame.oamFull[];
			case Renderer.neo:
				return neoRenderer.oamRaw[];
		}
	}
	ubyte[] oam2() return @safe pure {
		final switch (renderer) {
			case Renderer.autoSelect: assert(0);
			case Renderer.bsnes:
				return bsnesFrame.oam2[];
			case Renderer.neo:
				return cast(ubyte[])(neoRenderer.oamHigh[]);
		}
	}
	const(HDMAWrite[]) allHDMAData() const return @safe pure {
		return hdmaData[0 .. numHDMA];
	}
	void writeRegister(ushort addr, ubyte value) @safe pure {
		final switch (renderer) {
			case Renderer.autoSelect: assert(0);
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
			case Renderer.autoSelect: assert(0);
			case Renderer.bsnes:
				return bsnesFrame.readRegister(addr);
				break;
			case Renderer.neo:
				return neoRenderer.readRegister(addr);
				break;
		}
	}
	void debugUI(UIState state) {
		final switch (renderer) {
			case Renderer.autoSelect: assert(0);
			case Renderer.bsnes:
				return bsnesFrame.debugUI(state);
				break;
			case Renderer.neo:
				return neoRenderer.debugUI(state);
				break;
		}
	}
	void dump(StateDumper dumpFile) @safe {
		final switch (renderer) {
			case Renderer.autoSelect: assert(0);
			case Renderer.bsnes:
				dumpFile("gfxstate.registers.yaml", bsnesFrame.serialized);
				break;
			case Renderer.neo:
				dumpFile("gfxstate.registers.yaml", neoRenderer.serialized);
				break;
		}
		dumpFile("gfxstate.vram", cast(const(ubyte)[])vram);
		dumpFile("gfxstate.cgram", cast(const(ubyte)[])cgram);
		dumpFile("gfxstate.oam", cast(const(ubyte)[])oam1);
		dumpFile("gfxstate.oam2", cast(const(ubyte)[])oam2);
		dumpFile("gfxstate.hdma", cast(const(ubyte)[])allHDMAData());
	}
	Resolution getResolution() @safe pure {
		final switch (renderer) {
			case Renderer.autoSelect: assert(0);
			case Renderer.bsnes:
				return Resolution(512, 448);
			case Renderer.neo:
				return Resolution(256, 224);
		}
	}
}

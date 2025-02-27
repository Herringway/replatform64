module replatform64.snes.hardware.registers;

import std.bitmanip;
import replatform64.registers;

enum Register {
	INIDISP = 0x2100,
	OBSEL = 0x2101,
	OAMADDL = 0x2102,
	OAMADDH = 0x2103,
	OAMDATA = 0x2104,
	BGMODE = 0x2105,
	MOSAIC = 0x2106,
	BG1SC = 0x2107,
	BG2SC = 0x2108,
	BG3SC = 0x2109,
	BG4SC = 0x210A,
	BG12NBA = 0x210B,
	BG34NBA = 0x210C,
	@DoubleWrite BG1HOFS = 0x210D,
	@DoubleWrite BG1VOFS = 0x210E,
	@DoubleWrite BG2HOFS = 0x210F,
	@DoubleWrite BG2VOFS = 0x2110,
	@DoubleWrite BG3HOFS = 0x2111,
	@DoubleWrite BG3VOFS = 0x2112,
	@DoubleWrite BG4HOFS = 0x2113,
	@DoubleWrite BG4VOFS = 0x2114,
	VMAIN = 0x2115,
	VMADDL = 0x2116,
	VMADDH = 0x2117,
	VMDATAL = 0x2118,
	VMDATAH = 0x2119,
	M7SEL = 0x211A,
	M7A = 0x211B,
	M7B = 0x211C,
	M7C = 0x211D,
	M7D = 0x211E,
	M7X = 0x211F,
	M7Y = 0x2120,
	CGADD = 0x2121,
	CGDATA = 0x2122,
	W12SEL = 0x2123,
	W34SEL = 0x2124,
	WOBJSEL = 0x2125,
	WH0 = 0x2126,
	WH1 = 0x2127,
	WH2 = 0x2128,
	WH3 = 0x2129,
	WBGLOG = 0x212A,
	WOBJLOG = 0x212B,
	TM = 0x212C,
	TS = 0x212D,
	TD = TS,
	TMW = 0x212E,
	TSW = 0x212F,
	CGWSEL = 0x2130,
	CGADSUB = 0x2131,
	COLDATA = 0x2132,
	SETINI = 0x2133,
	MPYL = 0x2134,
	MPYM = 0x2135,
	MPYH = 0x2136,
	SLHV = 0x2137,
	RDOAM = 0x2138,
	RDVRAML = 0x2139,
	RDVRAMH = 0x213A,
	RDCGRAM = 0x213B,
	OPHCT = 0x213C,
	OPVCT = 0x213D,
	STAT77 = 0x213E,
	STAT78 = 0x213F,
	APUIO0 = 0x2140,
	APUIO1 = 0x2141,
	APUIO2 = 0x2142,
	APUIO3 = 0x2143,
}

///
enum Pad {
	extra4 = 0x0001, /// The SNES controller doesn't actually have a button like this. Unmapped by default
	extra3 = 0x0002, /// The SNES controller doesn't actually have a button like this. Unmapped by default
	extra2 = 0x0004, /// The SNES controller doesn't actually have a button like this. Unmapped by default
	extra1 = 0x0008, /// The SNES controller doesn't actually have a button like this. Unmapped by default
	r = 0x0010, /// Right shoulder button
	l = 0x0020, /// Left shoulder button
	x = 0x0040, /// The northern face button
	a = 0x0080, /// The eastern face button
	right = 0x0100, /// Right on the d-pad
	left = 0x0200, /// Left on the d-pad
	down = 0x0400, /// Down on the d-pad
	up = 0x0800, /// Up on the d-pad
	start = 0x1000, /// The start button in the centre
	select = 0x2000, /// The select button in the centre
	y = 0x4000, /// The western face button
	b = 0x8000, /// The southern face button
}

enum OAMFlags : ubyte {
	nameTable = 0b00000001,
	palette = 0b00001110,
	palette0 = 0 << 1,
	palette1 = 1 << 1,
	palette2 = 2 << 1,
	palette3 = 3 << 1,
	palette4 = 4 << 1,
	palette5 = 5 << 1,
	palette6 = 6 << 1,
	palette7 = 7 << 1,
	priority = 0b00110000,
	priority0 = 0 << 4,
	priority1 = 1 << 4,
	priority2 = 2 << 4,
	priority3 = 3 << 4,
	hFlip = 0b01000000,
	vFlip = 0b10000000,
}

///
struct OAMEntry {
	align(1):
	ubyte xCoord; ///
	ubyte yCoord; ///
	union {
		ushort raw;
		struct {
			ubyte startingTile;
			ubyte flags;
		}
		struct {
			mixin(bitfields!(
				ushort, "tile", 9,
				ubyte, "palette", 3,
				ubyte, "priority", 2,
				bool, "flipHorizontal", 1,
				bool, "flipVertical", 1,
			));
		}
	}
	static OAMEntry offscreen() {
		return OAMEntry(ubyte(0), ubyte(240), ubyte(0), ubyte(0));
	}
	this(ubyte x, ubyte y, ubyte tileLower, ubyte flags) {
		this.xCoord = x;
		this.yCoord = y;
		this.startingTile = tileLower;
		this.flags = flags;
	}
	this(ubyte x, ubyte y, ushort tile, bool hFlip = false, bool vFlip = false, ubyte palette = 0, ubyte priority = 0) {
		this.xCoord = x;
		this.yCoord = y;
		this.tile = tile;
		this.palette = palette;
		this.priority = priority;
		this.flipHorizontal = hFlip;
		this.flipVertical = vFlip;
	}
}

public struct HDMAWrite {
	ushort vcounter;
	ubyte addr;
	ubyte value;
}
///
struct DMAChannel {
	///DMAPx - $43x0
	ubyte DMAP;
	///BBADx - $43x1
	ubyte BBAD;
	/// A1Tx - $43x2
	union {
		struct {
			ubyte A1TL; ///
			ubyte A1TH; ///
			ubyte A1B; ///
		}
		const(void)* A1T; ///
	}
	/// DASx - $43x5
	union {
		struct {
			ubyte DASL; ///
			ubyte DASH; ///
			ubyte DASB; /// HDMA only
		}
		ushort DAS; /// not for HDMA
		const(void)* HDMADAS; ///
	}
	/// A2Ax - $43x8, HDMA only
	union {
		struct {
			ubyte A2AL; ///
			ubyte A2AH; ///
		}
		ushort A2A; ///
	}
	///NTLRx - $43xA - HDMA only
	ubyte NTLR;
	private ubyte[5] __unused;
}
///
align(1) struct HDMAIndirectTableEntry {
	align(1):
	ubyte lines;
	const(ubyte)* address;
}
///
enum DMATransferUnit {
	Byte = 0,
	Word = 1,
	ByteTwice = 2,
	WordTwiceInterlaced = 3,
	Int = 4,
	WordTwice = 5,
	WordCopy = 6,
	WordTwiceInterlacedCopy = 7,
}
///
align(1) struct HDMAWordTransfer {
	align(1):
	ubyte scanlines; ///
	ushort value; ///
}

///
enum CGWSELFlags {
	MainScreenBlackNever = 0<<6,
	MainScreenBlackNotMathWin = 1<<6,
	MainScreenBlackMathWin = 2<<6,
	MainScreenBlackAlways = 3<<6,
	ColourMathEnableAlways = 0 << 4,
	ColourMathEnableMathWin = 1 << 4,
	ColourMathEnableNotMathWin = 2 << 4,
	ColourMathEnableNever = 3 << 4,
	SubscreenBGOBJEnable = 1 << 1,
	SubscreenBGOBJDisable = 0 << 1,
	DirectColour = 1,
	UsePalette = 0,
}

///
enum CGADSUBFlags {
	ColourMathAddsub = 1 << 7,
	ColourMathDiv2 = 1 << 6,
	ColourMathMainIsBackdrop = 1 << 5,
	ColourMathMainIsOBJ47 = 1 << 4,
	ColourMathMainIsBG4 = 1 << 3,
	ColourMathMainIsBG3 = 1 << 2,
	ColourMathMainIsBG2 = 1 << 1,
	ColourMathMainIsBG1 = 1 << 0,
}

///
enum BGR555Mask {
	Red = 0x1F,
	Green = 0x3E0,
	Blue = 0x7C00,
}
///
enum TilemapFlag {
	palette0 = 0x0000,
	palette1 = 0x0400,
	palette2 = 0x0800,
	palette3 = 0x0C00,
	palette4 = 0x1000,
	palette5 = 0x1400,
	palette6 = 0x1800,
	palette7 = 0x1C00,
	priority = 0x2000,
	hFlip = 0x4000,
	vFlip = 0x8000,
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

///
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

///
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

///
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

///
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

///
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

///
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

///
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

///
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

///
union CGWSELValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			bool, "directColour", 1,
			bool, "subscreenEnable", 1,
			ubyte, "", 2,
			ubyte, "mathPreventMode", 2,
			ubyte, "mathClipMode", 2,
		));
	}
}

///
union CGADSUBValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			ubyte, "layers", 6,
			bool, "enableHalf", 1,
			bool, "enableSubtract", 1,
		));
	}
}

///
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

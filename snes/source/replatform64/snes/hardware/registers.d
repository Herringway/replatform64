module replatform64.snes.hardware.registers;

import std.bitmanip;
import replatform64.registers;
import replatform64.util;

enum Register {
	@RegisterValueType!INIDISPValue INIDISP = 0x2100,
	@RegisterValueType!OBSELValue OBSEL = 0x2101,
	OAMADDL = 0x2102,
	OAMADDH = 0x2103,
	OAMDATA = 0x2104,
	@RegisterValueType!BGMODEValue BGMODE = 0x2105,
	@RegisterValueType!MOSAICValue MOSAIC = 0x2106,
	@RegisterValueType!BGxSCValue BG1SC = 0x2107,
	@RegisterValueType!BGxSCValue BG2SC = 0x2108,
	@RegisterValueType!BGxSCValue BG3SC = 0x2109,
	@RegisterValueType!BGxSCValue BG4SC = 0x210A,
	@RegisterValueType!BGxxNBAValue BG12NBA = 0x210B,
	@RegisterValueType!BGxxNBAValue BG34NBA = 0x210C,
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
	@RegisterValueType!M7SELValue M7SEL = 0x211A,
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
	@RegisterValueType!CGWSELValue CGWSEL = 0x2130,
	@RegisterValueType!CGADSUBValue CGADSUB = 0x2131,
	COLDATA = 0x2132,
	@RegisterValueType!SETINIValue SETINI = 0x2133,
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
	// APUIO0-3 are mirrored up until 0x2180
	WMDATA = 0x2180,
	WMADDL = 0x2181,
	WMADDM = 0x2182,
	WMADDH = 0x2183,
	// open bus
	JOYWR = 0x4016,
	JOYA = JOYWR,
	JOYB = 0x4017,
	// open bus
	NMITIMEN = 0x4200,
	WRIO = 0x4201,
	WRMPYA = 0x4202,
	WRMPYB = 0x4203,
	WRDIVL = 0x4204,
	WRDIVH = 0x4205,
	WRDIVB = 0x4206,
	HTIMEL = 0x4207,
	HTIMEH = 0x4208,
	VTIMEL = 0x4209,
	VTIMEH = 0x420A,
	MDMAEN = 0x420B,
	HDMAEN = 0x420C,
	MEMSEL = 0x420D,
	// open bus
	RDNMI = 0x4210,
	TIMEUP = 0x4211,
	HVBJOY = 0x4212,
	RDIO = 0x4213,
	RDDIVL = 0x4214,
	RDDIVH = 0x4215,
	RDMPYL = 0x4216,
	RDMPYH = 0x4217,
	JOY1L = 0x4218,
	JOY1H = 0x4219,
	JOY2L = 0x421A,
	JOY2H = 0x421B,
	JOY3L = 0x421C,
	JOY3H = 0x421D,
	JOY4L = 0x421E,
	JOY4H = 0x421F,
	// open bus
	DMAP0 = 0x4300,
	BBAD0 = 0x4301,
	A1T0L = 0x4302,
	A1T0H = 0x4303,
	A1B0 = 0x4304,
	DAS0L = 0x4305,
	DAS0H = 0x4306,
	DASB0 = 0x4307,
	A2A0L = 0x4308,
	A2A0H = 0x4309,
	NTRL0 = 0x430A,
	DMAP1 = 0x4310,
	BBAD1 = 0x4311,
	A1T1L = 0x4312,
	A1T1H = 0x4313,
	A1B1 = 0x4314,
	DAS1L = 0x4315,
	DAS1H = 0x4316,
	DASB1 = 0x4317,
	A2A1L = 0x4318,
	A2A1H = 0x4319,
	NTRL1 = 0x431A,
	DMAP2 = 0x4320,
	BBAD2 = 0x4321,
	A1T2L = 0x4322,
	A1T2H = 0x4323,
	A1B2 = 0x4324,
	DAS2L = 0x4325,
	DAS2H = 0x4326,
	DASB2 = 0x4327,
	A2A2L = 0x4328,
	A2A2H = 0x4329,
	NTRL2 = 0x432A,
	DMAP3 = 0x4330,
	BBAD3 = 0x4331,
	A1T3L = 0x4332,
	A1T3H = 0x4333,
	A1B3 = 0x4334,
	DAS3L = 0x4335,
	DAS3H = 0x4336,
	DASB3 = 0x4337,
	A2A3L = 0x4338,
	A2A3H = 0x4339,
	NTRL3 = 0x433A,
	DMAP4 = 0x4340,
	BBAD4 = 0x4341,
	A1T4L = 0x4342,
	A1T4H = 0x4343,
	A1B4 = 0x4344,
	DAS4L = 0x4345,
	DAS4H = 0x4346,
	DASB4 = 0x4347,
	A2A4L = 0x4348,
	A2A4H = 0x4349,
	NTRL4 = 0x434A,
	DMAP5 = 0x4350,
	BBAD5 = 0x4351,
	A1T5L = 0x4352,
	A1T5H = 0x4353,
	A1B5 = 0x4354,
	DAS5L = 0x4355,
	DAS5H = 0x4356,
	DASB5 = 0x4357,
	A2A5L = 0x4358,
	A2A5H = 0x4359,
	NTRL5 = 0x435A,
	DMAP6 = 0x4360,
	BBAD6 = 0x4361,
	A1T6L = 0x4362,
	A1T6H = 0x4363,
	A1B6 = 0x4364,
	DAS6L = 0x4365,
	DAS6H = 0x4366,
	DASB6 = 0x4367,
	A2A6L = 0x4368,
	A2A6H = 0x4369,
	NTRL6 = 0x436A,
	DMAP7 = 0x4370,
	BBAD7 = 0x4371,
	A1T7L = 0x4372,
	A1T7H = 0x4373,
	A1B7 = 0x4374,
	DAS7L = 0x4375,
	DAS7H = 0x4376,
	DASB7 = 0x4377,
	A2A7L = 0x4378,
	A2A7H = 0x4379,
	NTRL7 = 0x437A,
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
	static OAMEntry offscreen() @safe pure {
		return OAMEntry.fromBytes(x: 0, y: 240, tileLower: 0, flags: 0);
	}
	static OAMEntry fromBytes(ubyte x, ubyte y, ubyte tileLower, ubyte flags) @safe pure {
		OAMEntry result;
		result.xCoord = x;
		result.yCoord = y;
		result.startingTile = tileLower;
		result.flags = flags;
		return result;
	}
	this(ubyte x, ubyte y, ushort tile, bool hFlip = false, bool vFlip = false, ubyte palette = 0, ubyte priority = 0) @safe pure {
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
	const(ubyte)* A1TDirect() const @trusted pure {
		assert(!(DMAP & 0b01000000), "Attempted to access direct HDMA data in indirect mode!");
		return cast(const(ubyte)*)A1T;
	}
	const(HDMAIndirectTableEntry)* A1TIndirect() const @trusted pure {
		assert(!!(DMAP & 0b01000000), "Attempted to access indirect HDMA data in direct mode!");
		return cast(const(HDMAIndirectTableEntry)*)A1T;
	}
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
union TilemapEntry {
	mixin RegisterValue!(ushort,
		ushort, "index", 10,
		ubyte, "palette", 3,
		bool, "priority", 1,
		bool, "flipHorizontal", 1,
		bool, "flipVertical", 1,
	);
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
	mixin RegisterValue!(ubyte,
		uint, "screenBrightness", 4,
		uint, "", 3,
		bool, "forcedBlank", 1,
	);
}

enum OBJSize {
	small8x8Large16x16,
	small8x8Large32x32,
	small8x8Large64x64,
	small16x16Large32x32,
	small16x16Large64x64,
	small32x32Large64x64,
	small16x32Large32x64,
	small16x32Large32x32,
}

///
union OBSELValue {
	mixin RegisterValue!(ubyte,
		uint, "tileBase", 3,
		uint, "hiOffset", 2,
		OBJSize, "size", 3,
	);
}

///
union BGMODEValue {
	mixin RegisterValue!(ubyte,
		uint, "mode", 3,
		bool, "bg3Priority", 1,
		bool, "largeBG1Tiles", 1,
		bool, "largeBG2Tiles", 1,
		bool, "largeBG3Tiles", 1,
		bool, "largeBG4Tiles", 1,
	);
}

///
union MOSAICValue {
	mixin RegisterValue!(ubyte,
		bool, "enabledBG1", 1,
		bool, "enabledBG2", 1,
		bool, "enabledBG3", 1,
		bool, "enabledBG4", 1,
		uint, "size", 4,
	);
}

///
union BGxSCValue {
	mixin RegisterValue!(ubyte,
		bool, "doubleWidth", 1,
		bool, "doubleHeight", 1,
		uint, "baseAddress", 6,
	);
}

///
union BGxxNBAValue {
	mixin RegisterValue!(ubyte,
		uint, "bg1", 4,
		uint, "bg2", 4,
	);
	alias bg3 = bg1;
	alias bg4 = bg2;
}

///
union M7SELValue {
	mixin RegisterValue!(ubyte,
		bool, "screenHFlip", 1,
		bool, "screenVFlip", 1,
		uint, "", 4,
		bool, "tile0Fill", 1,
		bool, "largeMap", 1,
	);
}

///
union ScreenWindowEnableValue {
	mixin RegisterValue!(ubyte,
		bool, "bg1", 1,
		bool, "bg2", 1,
		bool, "bg3", 1,
		bool, "bg4", 1,
		bool, "obj", 1,
		uint, "", 3,
	);
}

enum MathClipMode {
	never = 0,
	notMathWindow = 1,
	mathWindow = 2,
	always = 3,
}

enum ColourMathEnabled {
	always = 0,
	mathWindow = 1,
	notMathWindow = 2,
	never = 3,
}

///
union CGWSELValue{
	mixin RegisterValue!(ubyte,
		bool, "directColour", 1,
		bool, "subscreenEnable", 1,
		ubyte, "", 2,
		ColourMathEnabled, "mathPreventMode", 2,
		MathClipMode, "mathClipMode", 2,
	);
}

///
union CGADSUBValue {
	mixin RegisterValue!(ubyte,
		ubyte, "layers", 6,
		bool, "enableHalf", 1,
		bool, "enableSubtract", 1,
	);
}

///
union SETINIValue {
	mixin RegisterValue!(ubyte,
		bool, "screenInterlace", 1,
		bool, "objInterlace", 1,
		bool, "overscan", 1,
		bool, "hiRes", 1,
		uint, "", 2,
		bool, "extbg", 1,
		bool, "", 1,
	);
}

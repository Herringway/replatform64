module librehome.snes.hardware;

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
	BG1HOFS = 0x210D,
	BG1VOFS = 0x210E,
	BG2HOFS = 0x210F,
	BG2VOFS = 0x2110,
	BG3HOFS = 0x2111,
	BG3VOFS = 0x2112,
	BG4HOFS = 0x2113,
	BG4VOFS = 0x2114,
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
}

///
enum Pad {
	extra4 = 0x0001, ///The SNES controller doesn't actually have a button like this
	extra3 = 0x0002, ///The SNES controller doesn't actually have a button like this
	extra2 = 0x0004, ///The SNES controller doesn't actually have a button like this
	extra1 = 0x0008, ///The SNES controller doesn't actually have a button like this
	r = 0x0010, ///
	l = 0x0020, ///
	x = 0x0040, ///
	a = 0x0080, ///
	right = 0x0100, ///
	left = 0x0200, ///
	down = 0x0400, ///
	up = 0x0800, ///
	start = 0x1000, ///
	select = 0x2000, ///
	y = 0x4000, ///
	b = 0x8000, ///
}

///
struct OAMEntry {
	ubyte xCoord; ///
	ubyte yCoord; ///
	ubyte startingTile; ///
	ubyte flags; ///
	///
	bool flipVertical() const {
		return !!(flags & 0b10000000);
	}
	///
	bool flipHorizontal() const {
		return !!(flags & 0b01000000);
	}
	///
	ubyte priority() const {
		return (flags & 0b00110000) >> 4;
	}
	///
	ubyte palette() const {
		return (flags & 0b00001110) >> 1;
	}
	///
	bool nameTable() const {
		return !!(flags & 0b00000001);
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

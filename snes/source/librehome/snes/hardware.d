module librehome.snes.hardware;

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
module librehome.snes.hardware;

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

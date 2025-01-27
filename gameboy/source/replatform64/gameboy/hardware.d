module replatform64.gameboy.hardware;

alias P1Value = JOYPValue;
///
enum JOYPValue : ubyte {
	a = 1 << 0, ///
	right = 1 << 0, ///
	b = 1 << 1, ///
	left = 1 << 1, ///
	select = 1 << 2, ///
	up = 1 << 2, ///
	start = 1 << 3, ///
	down = 1 << 3, ///
	dpadSelect = 1 << 4, ///
	buttonSelect = 1 << 5, ///
}

alias IEValue = InterruptFlag;
alias IFValue = InterruptFlag;
///
enum InterruptFlag : ubyte {
	vblank = 1 << 0, ///
	lcd = 1 << 1, ///
	timer = 1 << 2, ///
	serial = 1 << 3, ///
	joypad = 1 << 4, ///
}

///
enum TACValue : ubyte {
	clockSlowest = 0 << 0, /// 4096 Hz
	clockFastest = 1 << 0, /// 262144 Hz
	clockFaster = 2 << 0, /// 65536 Hz
	clockSlower = 3 << 0, /// 16384 Hz
	enabled = 1 << 2, // Enable timer
}

///
enum KEY1Value : ubyte {
	noChange = 0 << 0, /// Don't prepare a speed change
	changeSpeed = 1 << 0, /// Prepares a speed change
	singleSpeed = 0 << 7, /// CPU is in single-speed (DMG) mode
	doubleSpeed = 1 << 7, /// CPU is in double-speed (CGB) mode
}

///
enum STATValues : ubyte {
	ppuMode = 3 << 0, /// The PPU's current status
	mode0 = 0 << 0, /// PPU Mode 0 (hblank, can write all VRAM)
	mode1 = 1 << 0, /// PPU Mode 1 (vblank, can write all VRAM)
	mode2 = 2 << 0, /// PPU Mode 2 (OAM scan, can write all VRAM except OAM)
	mode3 = 3 << 0, /// PPU Mode 3 (drawing, cannot access VRAM)
	lycEqualLY = 1 << 2, /// Set when LY == LYC (current rendered scanline == LYC)
	mode0Interrupt = 1 << 3, /// Trigger STAT interrupt when PPU is in mode 0
	mode1Interrupt = 1 << 4, /// Trigger STAT interrupt when PPU is in mode 1
	mode2Interrupt = 1 << 5, /// Trigger STAT interrupt when PPU is in mode 2
	lycInterrupt = 1 << 6, /// Trigger STAT interrupt when LY == LYC
}

///
struct OAMEntry {
	align(1):
	ubyte y; /// Y coordinate (0 or any value >= 160 hides an object)
	ubyte x; /// X coordinate (0 or any value >= 168 hides an object)
	ubyte tile; /// Tile index. Least significant bit is ignored in tall sprite mode
	ubyte flags; /// Palette, bank, X flip, Y flip, priority
	///
	this(byte a, byte b, ubyte c, ubyte d) {
		y = a;
		x = b;
		tile = c;
		flags = d;
	}
	///
	this(ubyte a) {
		y = a;
	}
}

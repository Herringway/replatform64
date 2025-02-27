module replatform64.nes.hardware.registers;

import std.bitmanip;

enum Register {
	PPUCTRL = 0x2000,
	PPUMASK = 0x2001,
	PPUSTATUS = 0x2002,
	OAMADDR = 0x2003,
	OAMDATA = 0x2004,
	PPUSCROLL = 0x2005,
	PPUADDR = 0x2006,
	PPUDATA = 0x2007,
	SQ1 = 0x4000,
	SQ1_VOL = 0x4000,
	SQ1_SWEEP = 0x4001,
	SQ1_LO = 0x4002,
	SQ1_HI = 0x4003,
	SQ2 = 0x4004,
	SQ2_VOL = 0x4004,
	SQ2_SWEEP = 0x4005,
	SQ2_LO = 0x4006,
	SQ2_HI = 0x4007,
	TRI = 0x4008,
	TRI_LINEAR = 0x4008,
	TRI_LO = 0x400A,
	TRI_HI = 0x400B,
	NOISE = 0x400C,
	NOISE_VOL = 0x400C,
	NOISE_LO = 0x400E,
	NOISE_HI = 0x400F,
	DMC = 0x4010,
	DMC_FREQ = 0x4010,
	DMC_RAW = 0x4011,
	DMC_START = 0x4012,
	DMC_LEN = 0x4013,
	OAMDMA = 0x4014,
	SND_CHN = 0x4015,
	JOY1 = 0x4016,
	JOY2 = 0x4017,
}

///
enum Pad {
	right = 0x01, /// Right on the d-pad
	left = 0x02, /// Left on the d-pad
	down = 0x04, /// Down on the d-pad
	up = 0x08, /// Up on the d-pad
	start = 0x10, /// The start button in the centre
	select = 0x20, /// The select button in the centre
	b = 0x40, /// The left face button
	a = 0x80, /// The right face button
}

///
union PPUMASKValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			bool, "grayscale", 1,
			bool, "showBGLeft8", 1,
			bool, "showSpritesLeft8", 1,
			bool, "enableBG", 1,
			bool, "enableSprites", 1,
			bool, "emphasizeRed", 1,
			bool, "emphasizeGreen", 1,
			bool, "emphasizeBlue", 1,
		));
	}
}

///
union PPUCTRLValue {
	ubyte raw;
	struct {
		mixin(bitfields!(
			ubyte, "nameTableBase", 2,
			bool, "ppuDataIncreaseByRow", 1,
			bool, "spritePatternTable", 1,
			bool, "bgPatternTable", 1,
			bool, "tallSprites", 1,
			bool, "extColourOutput", 1,
			bool, "vblankNMI", 1,
		));
	}
}

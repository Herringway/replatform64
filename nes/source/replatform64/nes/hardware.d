module replatform64.nes.hardware;

import std.bitmanip;

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

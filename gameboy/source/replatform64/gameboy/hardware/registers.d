module replatform64.gameboy.hardware.registers;

import replatform64.registers;

public import pixelmancy.colours : BGR555;

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
	noDpadSelect = 1 << 4, ///
	dpadSelect = noButtonSelect, ///
	noButtonSelect = 1 << 5, ///
	buttonSelect = noDpadSelect, ///
	noneSelect = noDpadSelect | noButtonSelect, ///
}

///
enum Pad : ubyte {
	a = 1 << 0,
	b = 1 << 1,
	select = 1 << 2,
	start = 1 << 3,
	right = 1 << 4,
	left = 1 << 5,
	up = 1 << 6,
	down = 1 << 7,
}

alias IFValue = IEValue;
union IEValue {
	mixin RegisterValue!(ubyte,
		bool, "vblank", 1,
		bool, "lcd", 1,
		bool, "timer", 1,
		bool, "serial", 1,
		bool, "joypad", 1,
		ubyte, "", 3,
	);
	alias stat = lcd;
}
///
enum InterruptFlag : ubyte {
	vblank = 1 << 0, ///
	stat = 1 << 1, ///
	lcd = stat, ///
	timer = 1 << 2, ///
	serial = 1 << 3, ///
	joypad = 1 << 4, ///
}

enum ClockSpeed {
	slowest,  /// 4096 Hz
	fastest,  /// 262144 Hz
	faster,  /// 65536 Hz
	slower,  /// 16384 Hz
}

///
union TACValue {
	mixin RegisterValue!(ubyte,
		ClockSpeed, "clock", 2,
		bool, "enabled", 1,
		ubyte, "", 5,
	);
}

///
union KEY1Value {
	mixin RegisterValue!(ubyte,
		bool, "prepareSwitch", 1,
		ubyte, "", 6,
		bool, "doubleSpeed", 1,
	);
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

alias OBPValue = BGPValue;
///
union BGPValue {
	mixin RegisterValue!(ubyte,
		ubyte, "colour0", 2,
		ubyte, "colour1", 2,
		ubyte, "colour2", 2,
		ubyte, "colour3", 2,
	);
}
///
struct OAMEntry {
	align(1):
	ubyte y; /// Y coordinate (0 or any value >= 160 hides an object)
	ubyte x; /// X coordinate (0 or any value >= 168 hides an object)
	ubyte tile; /// Tile index. Least significant bit is ignored in tall sprite mode
	OAMFlagsValue flags; /// Palette, bank, X flip, Y flip, priority
	///
	this(byte y, byte x, ubyte tile, ubyte flags) @safe pure {
		this.y = y;
		this.x = x;
		this.tile = tile;
		this.flags.raw = flags;
	}
	///
	this(ubyte a) @safe pure {
		y = a;
	}
	this(ubyte x, ubyte y, ubyte tile, bool hFlip = false, bool vFlip = false, bool dmgPalette = false, bool priority = false, ubyte cgbPalette = 0) @safe pure {
		this.x = x;
		this.y = y;
		this.tile = tile;
		this.flags.dmgPalette = dmgPalette;
		this.flags.cgbPalette = cgbPalette;
		this.flags.priority = priority;
		this.flags.xFlip = hFlip;
		this.flags.yFlip = vFlip;
	}
	static OAMEntry offscreen() @safe pure {
		return OAMEntry(y: cast(byte)160, x: 0, tile: 0, flags: 0);
	}
}

///
enum LCDCFlags {
	bgEnabled = 1 << 0,
	spritesEnabled = 1 << 1,
	tallSprites = 1 << 2,
	bgTilemap = 1 << 3,
	useAltBG = 1 << 4,
	windowDisplay = 1 << 5,
	windowTilemap = 1 << 6,
	lcdEnabled = 1 << 7,
}

///
enum OAMFlags {
	cgbPalette = 7 << 0,
	bank = 1 << 3,
	dmgPalette = 1 << 4,
	xFlip = 1 << 5,
	yFlip = 1 << 6,
	priority = 1 << 7,
}

///
enum CGBBGAttributes {
	palette = 7 << 0,
	bank = 1 << 3,
	xFlip = 1 << 5,
	yFlip = 1 << 6,
	priority = 1 << 7,
}

///
union CGBBGAttributeValue {
	mixin RegisterValue!(ubyte,
		ubyte, "palette", 3,
		bool, "bank", 1,
		bool, "", 1,
		bool, "xFlip", 1,
		bool, "yFlip", 1,
		bool, "priority", 1,
	);
}
///
union LCDCValue {
	mixin RegisterValue!(ubyte,
		bool, "bgEnabled", 1,
		bool, "spritesEnabled", 1,
		bool, "tallSprites", 1,
		ubyte, "bgTilemap", 1,
		bool, "useAltBG", 1,
		bool, "windowDisplay", 1,
		ubyte, "windowTilemap", 1,
		bool, "lcdEnabled", 1,
	);
}
///
union OAMFlagsValue {
	mixin RegisterValue!(ubyte,
		ubyte, "cgbPalette", 3,
		bool, "bank", 1,
		bool, "dmgPalette", 1,
		bool, "xFlip", 1,
		bool, "yFlip", 1,
		bool, "priority", 1,
	);
}

///
union STATValue {
	mixin RegisterValue!(ubyte,
		uint, "mode", 2,
		bool, "lycEqualLY", 1,
		bool, "mode0Interrupt", 1,
		bool, "mode1Interrupt", 1,
		bool, "mode2Interrupt", 1,
		bool, "lycInterrupt", 1,
		bool, "", 1,
	);
}

///
union NR52Value {
	mixin RegisterValue!(ubyte,
		bool, "channel1Enabled", 1,
		bool, "channel2Enabled", 1,
		bool, "channel3Enabled", 1,
		bool, "channel4Enabled", 1,
		ubyte, "", 3,
		bool, "soundEnabled", 1,
	);
}

enum Register : ushort {
	JOYP = 0xFF00,
	P1 = JOYP,
	SB = 0xFF01,
	SC = 0xFF02,
	DIV = 0xFF04,
	TIMA = 0xFF05,
	TMA = 0xFF06,
	@RegisterValueType!TACValue TAC = 0xFF07,
	@RegisterValueType!IFValue IF = 0xFF0F,
	NR10 = 0xFF10,
	AUD1SWEEP = NR10,
	NR11 = 0xFF11,
	AUD1LEN = NR11,
	NR12 = 0xFF12,
	AUD1ENV = NR12,
	NR13 = 0xFF13,
	AUD1LOW = NR13,
	NR14 = 0xFF14,
	AUD1HIGH = NR14,
	NR21 = 0xFF16,
	AUD2LEN = NR21,
	NR22 = 0xFF17,
	AUD2ENV = NR22,
	NR23 = 0xFF18,
	AUD2LOW = NR23,
	NR24 = 0xFF19,
	AUD2HIGH = NR24,
	NR30 = 0xFF1A,
	AUD3ENA = NR30,
	NR31 = 0xFF1B,
	AUD3LEN = NR31,
	NR32 = 0xFF1C,
	AUD3LEVEL = NR32,
	NR33 = 0xFF1D,
	AUD3LOW = NR33,
	NR34 = 0xFF1E,
	AUD3HIGH = NR34,
	NR41 = 0xFF20,
	AUD4LEN = NR41,
	NR42 = 0xFF21,
	AUD4ENV = NR42,
	NR43 = 0xFF22,
	AUD4POLY = NR43,
	NR44 = 0xFF23,
	AUD4GO = NR44,
	NR50 = 0xFF24,
	AUDVOL = NR50,
	NR51 = 0xFF25,
	AUDTERM = NR51,
	@RegisterValueType!NR52Value NR52 = 0xFF26,
	@RegisterValueType!NR52Value AUDENA = NR52,
	WAVESTART = 0xFF30,
	WAVEEND = 0xFF3F,
	@RegisterValueType!LCDCValue LCDC = 0xFF40,
	@RegisterValueType!STATValue STAT = 0xFF41,
	SCY = 0xFF42,
	SCX = 0xFF43,
	LY = 0xFF44,
	LYC = 0xFF45,
	DMA = 0xFF46,
	@RegisterValueType!BGPValue BGP = 0xFF47,
	@RegisterValueType!OBPValue OBP0 = 0xFF48,
	@RegisterValueType!OBPValue OBP1 = 0xFF49,
	WY = 0xFF4A,
	WX = 0xFF4B,
	@RegisterValueType!KEY1Value KEY1 = 0xFF4D,
	VBK = 0xFF4F,
	HDMA1 = 0xFF51,
	HDMA2 = 0xFF52,
	HDMA3 = 0xFF53,
	HDMA4 = 0xFF54,
	HDMA5 = 0xFF55,
	RP = 0xFF56,
	BCPS = 0xFF68,
	BCPD = 0xFF69,
	OCPS = 0xFF6A,
	OCPD = 0xFF6B,
	SVBK = 0xFF70,
	@RegisterValueType!IEValue IE = 0xFFFF,
}

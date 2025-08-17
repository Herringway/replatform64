module replatform64.gameboy.hardware.serial;

import std.logger;

struct Serial {
	void writeRegister(ushort addr, ubyte value) @safe {
		tracef("Unimplemented register write: %04X (%02X)", addr, value);
	}
	ubyte readRegister(ushort addr) @safe {
		tracef("Unimplemented register read: %04X", addr);
		return 0;
	}
}

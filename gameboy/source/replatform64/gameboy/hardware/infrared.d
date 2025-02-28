module replatform64.gameboy.hardware.infrared;

import std.logger;

struct Infrared {
	void writeRegister(ushort addr, ubyte value) {
		tracef("Unimplemented register write: %04X (%02X)", addr, value);
	}
	ubyte readRegister(ushort addr) {
		tracef("Unimplemented register read: %04X", addr);
		return 0;
	}
}

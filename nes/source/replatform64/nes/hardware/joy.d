module replatform64.nes.hardware.joy;

import replatform64.nes.hardware.registers;

struct JOY {
	ubyte[2] padData;
	ubyte[2] tmpRead;
	bool parallel;
	ubyte readRegister(ushort addr) @safe pure {
		const id = addr - Register.JOY1;
		ubyte value = tmpRead[id] & 1;
		tmpRead[id] >>= 1;
		if (parallel) {
			tmpRead[id] = padData[id];
		}
		return value;
	}
	void writeRegister(ushort addr, ubyte value) @safe pure {
		if (addr == Register.JOY1) {
			parallel = value & 1;
			if (parallel) {
				tmpRead[] = padData[];
			}
		}
	}
}

@safe pure unittest {
	bool[8] readBits;
	with (JOY()) {
		padData[0] = 0b0000_0001;
		foreach (_; 0 .. 8) {
			assert(readRegister(Register.JOY1) == 0);
		}
		writeRegister(Register.JOY1, 1);
		foreach (bit; 0 .. 8) {
			readBits[bit] = !!readRegister(Register.JOY1);
		}
		assert(readBits == [true, true, true, true, true, true, true, true]);
		writeRegister(Register.JOY1, 0);
		foreach (bit; 0 .. 8) {
			readBits[bit] = !!readRegister(Register.JOY1);
		}
		import std.logger; debug infof("%s, %b, %b", readBits, padData[0], tmpRead[0]);
		assert(readBits == [true, false, false, false, false, false, false, false]);
	}
}

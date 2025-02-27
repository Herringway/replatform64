module replatform64.gameboy.hardware.joy;

import replatform64.gameboy.hardware.registers;

struct JOY {
	private ubyte select;
	ubyte pad;
	ubyte readRegister(ushort addr) const @safe pure {
		assert (addr == Register.JOYP);
		if ((select & JOYPValue.noneSelect) == JOYPValue.noneSelect) {
			return 0x0F;
		} else if ((select & JOYPValue.noneSelect) == JOYPValue.dpadSelect) {
			return cast(ubyte)~pad >> 4;
		} else if ((select & JOYPValue.noneSelect) == JOYPValue.buttonSelect) {
			return ~pad & 0xF;
		} else {
			return 0;
		}
	}
	void writeRegister(ushort addr, ubyte value) @safe pure {
		assert (addr == Register.JOYP);
		select = value & JOYPValue.noneSelect;
	}
}

@safe pure unittest {
	with (JOY()) {
		writeRegister(Register.JOYP, JOYPValue.noneSelect);
		assert(readRegister(Register.JOYP) == 0xF);
	}
	with (JOY()) {
		pad = Pad.a | Pad.start | Pad.up;
		writeRegister(Register.JOYP, JOYPValue.buttonSelect);
		assert(readRegister(Register.JOYP) == (~(JOYPValue.a | JOYPValue.start) & 0xF));
	}
	with (JOY()) {
		pad = Pad.a | Pad.start | Pad.up;
		writeRegister(Register.JOYP, JOYPValue.dpadSelect);
		assert(readRegister(Register.JOYP) == (~JOYPValue.up & 0xF));
	}
	with (JOY()) {
		pad = Pad.a | Pad.start | Pad.up;
		writeRegister(Register.JOYP, 0x10);
		assert(readRegister(Register.JOYP) == (~(JOYPValue.a | JOYPValue.start) & 0xF));
	}
	with (JOY()) {
		pad = Pad.a | Pad.start | Pad.up;
		writeRegister(Register.JOYP, 0x20);
		assert(readRegister(Register.JOYP) == (~JOYPValue.up & 0xF));
	}
}

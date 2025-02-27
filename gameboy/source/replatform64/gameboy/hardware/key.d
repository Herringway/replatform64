module replatform64.gameboy.hardware.key;

import replatform64.gameboy.hardware.registers;
import std.logger;

struct KEY {
	bool preparingSwitch;
	bool pretendDoubleSpeed;
	ubyte readRegister(ushort addr) const @safe pure {
		assert (addr == Register.KEY1);
		return pretendDoubleSpeed << 7;
	}
	void writeRegister(ushort addr, ubyte value) @safe pure {
		assert (addr == Register.KEY1);
		debug tracef("Preparing to switch to %s mode", ["single-speed", "double-speed"][!!(pretendDoubleSpeed & 1)]);
		preparingSwitch = !!(value & 1);
	}
	void commitSpeedChange() @safe pure {
		if (preparingSwitch) {
			pretendDoubleSpeed ^= true;
			preparingSwitch = false;
			debug tracef("Switched to %s speed mode", ["single", "double"][pretendDoubleSpeed]);
		}
	}
}

@safe pure unittest {
	with(KEY()) {
		commitSpeedChange();
		assert(!pretendDoubleSpeed);
		assert(readRegister(Register.KEY1) == KEY1Value.singleSpeed);
	}
	with(KEY()) {
		writeRegister(Register.KEY1, KEY1Value.changeSpeed);
		commitSpeedChange();
		assert(pretendDoubleSpeed);
		assert(readRegister(Register.KEY1) == KEY1Value.doubleSpeed);
	}
	with(KEY()) {
		writeRegister(Register.KEY1, KEY1Value.changeSpeed);
		commitSpeedChange();
		writeRegister(Register.KEY1, KEY1Value.changeSpeed);
		commitSpeedChange();
		assert(!pretendDoubleSpeed);
		assert(readRegister(Register.KEY1) == KEY1Value.singleSpeed);
	}
}

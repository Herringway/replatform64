module replatform64.gameboy.timer;

import replatform64.gameboy.hardware;

struct Timer {
	ubyte tac;
	ubyte _tma;
	ubyte tma() const @safe pure {
		return _tma;
	}
	void tma(ubyte newValue) @safe pure {
		_tma = newValue;
		timerInternal = _tma * increment;
	}
	ubyte tima;
	ubyte timerMultiplier = 1;
	uint timerInternal;
	bool interruptTriggered;
	private ubyte increment() const @safe pure {
		return cast(ubyte)(456 / (4 / timerMultiplier));
	}
	void scanlineUpdate() @safe pure {
		if ((tac & 0b100) == 0) {
			return;
		}
		timerInternal += increment;
		auto timaTmp = timerInternal / ([256, 4, 16, 64][tac & 0b11]);
		if (timaTmp > 0xFF) {
			interruptTriggered = true;
			timaTmp = _tma;
			timerInternal -= increment * (256 - _tma);
		}
		tima = timaTmp & 0xFF;
	}
	void writeRegister(ushort addr, ubyte value) @safe pure {
		switch (addr) {
			case Register.TIMA:
				tima = value;
				break;
			case Register.TMA:
				tma = value;
				break;
			case Register.TAC:
				tac = value;
				break;
			default: assert(0);
		}
	}
	ubyte readRegister(ushort addr) const @safe pure {
		switch (addr) {
			case Register.TIMA: return tima;
			case Register.TMA: return tma;
			case Register.TAC: return tac;
			default: assert(0);
		}
	}
}

@safe pure unittest {
	with (Timer()) {
		tac = 0b100;
		timerMultiplier = 2;
		tma = 119;
		int interrupts = 0;
		foreach (i; 0 .. 153 * 4) {
			scanlineUpdate();
			if (interruptTriggered) {
				interrupts++;
				interruptTriggered = false;
				assert(tima == 119);
			}
		}
		assert(interrupts == 4);
	}
	with (Timer()) {
		tac = 0b100;
		tma = 187;
		int interrupts = 0;
		foreach (i; 0 .. 153 * 4) {
			scanlineUpdate();
			if (interruptTriggered) {
				interrupts++;
				interruptTriggered = false;
				assert(tima == 187);
			}
		}
		assert(interrupts == 4);
	}
}

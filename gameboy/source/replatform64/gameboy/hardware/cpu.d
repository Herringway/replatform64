module replatform64.gameboy.hardware.cpu;

alias rrca = rrc;
ubyte rrc(ubyte value, ref bool carry) @safe pure {
	const inCarry = carry;
	carry = !!(value & 0b00000001);
	value >>= 1;
	value |= (inCarry << 7);
	return value;
}
///
@safe pure unittest {
	runTest!rrc(0b00000000, false, 0b00000000, false);
	runTest!rrc(0b00000000, true, 0b10000000, false);
	runTest!rrc(0b00000001, false, 0b00000000, true);
	runTest!rrc(0b00000010, false, 0b00000001, false);
	runTest!rrc(0b00000011, false, 0b00000001, true);
}

ubyte sra(ubyte value, ref bool carry) @safe pure {
	carry = !!(value & 0b00000001);
	const msb = value & 0b10000000;
	value >>= 1;
	value |= msb;
	return value;
}
///
@safe pure unittest {
	runTest!sra(0b00000000, false, 0b00000000, false);
	runTest!sra(0b10000000, false, 0b11000000, false);
	runTest!sra(0b00000000, true, 0b00000000, false);
	runTest!sra(0b10000000, true, 0b11000000, false);
	runTest!sra(0b00000001, false, 0b00000000, true);
	runTest!sra(0b00000010, false, 0b00000001, false);
	runTest!sra(0b00000011, false, 0b00000001, true);
}
ubyte rra(ubyte value, ref bool carry) @safe pure {
	const inCarry = carry;
	carry = !!(value & 0b00000001);
	const msb = inCarry << 7;
	value >>= 1;
	value |= msb;
	return value;
}
///
@safe pure unittest {
	runTest!rra(0b00000000, false, 0b00000000, false);
	runTest!rra(0b10000000, false, 0b01000000, false);
	runTest!rra(0b00000000, true, 0b10000000, false);
	runTest!rra(0b10000000, true, 0b11000000, false);
	runTest!rra(0b00000001, false, 0b00000000, true);
	runTest!rra(0b00000010, false, 0b00000001, false);
	runTest!rra(0b00000011, false, 0b00000001, true);
}
ubyte srl(ubyte value, ref bool carry) @safe pure {
	carry = !!(value & 0b00000001);
	value >>= 1;
	return value;
}
///
@safe pure unittest {
	runTest!srl(0b00000000, false, 0b00000000, false);
	runTest!srl(0b10000000, false, 0b01000000, false);
	runTest!srl(0b00000000, true, 0b00000000, false);
	runTest!srl(0b10000000, true, 0b01000000, false);
	runTest!srl(0b00000001, false, 0b00000000, true);
	runTest!srl(0b00000010, false, 0b00000001, false);
	runTest!srl(0b00000011, false, 0b00000001, true);
}

alias rla = rl;
ubyte rl(ubyte value, ref bool carry) @safe pure {
	const inCarry = carry;
	carry = !!(value & 0b10000000);
	value <<= 1;
	value |= inCarry;
	return value;
}
///
@safe pure unittest {
	runTest!rl(0b00000000, false, 0b00000000, false);
	runTest!rl(0b00000000, true, 0b00000001, false);
	runTest!rl(0b00000001, false, 0b00000010, false);
	runTest!rl(0b01000000, false, 0b10000000, false);
	runTest!rl(0b11000000, false, 0b10000000, true);
}
ubyte sla(ubyte value, ref bool carry) @safe pure {
	carry = !!(value & 0b10000000);
	value <<= 1;
	return value;
}
///
@safe pure unittest {
	runTest!sla(0b00000000, false, 0b00000000, false);
	runTest!sla(0b00000000, true, 0b00000000, false);
	runTest!sla(0b00000001, false, 0b00000010, false);
	runTest!sla(0b01000000, false, 0b10000000, false);
	runTest!sla(0b11000000, false, 0b10000000, true);
}

version(unittest) {
	private static void runTest(alias func)(ubyte input, bool inCarry, ubyte expectedOutput, bool expectedCarry, string file = __FILE__, ulong line = __LINE__) {
		import core.exception : AssertError;
		bool carry = inCarry;
		if (func(input, carry) != expectedOutput) {
			throw new AssertError("Assertion failure (value)", file, line);
		}
		if (carry != expectedCarry) {
			throw new AssertError("Assertion failure (carry)", file, line);
		}
	}
}

///
ubyte swap(ubyte value) @safe pure {
	return cast(ubyte)((value >> 4) | (value << 4));
}
///
@safe pure unittest {
	assert(swap(0x00) == 0x00);
	assert(swap(0x24) == 0x42);
	assert(swap(0x80) == 0x08);
}

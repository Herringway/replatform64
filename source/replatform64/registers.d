module replatform64.registers;

import std.traits : Parameters;

struct DoubleWrite_ {}
enum DoubleWrite = DoubleWrite_();

template doubleSized(T) {
	static if (is(T == ubyte)) {
		alias doubleSized = ushort;
	} else static if (is(T == ushort)) {
		alias doubleSized = uint;
	} else static if (is(T == uint)) {
		alias doubleSized = ulong;
	} else {
		static assert(0, "Unsupported");
	}
}

module replatform64.registers;

import std.traits : Parameters;

void writeRegisterLogged(T, A, V)(ref T target, A address, V val) {
	import replatform64.util : printRegisterAccess;
	alias p = Parameters!(T.writeRegister);
	printRegisterAccess(cast(p[0])address, cast(p[1])val);
	target.writeRegister(cast(p[0])address, cast(p[1])val);
}

mixin template RegisterRedirect(string name, string target) {
	static if (__traits(compiles, mixin(target, "()"))) {
		mixin("
			typeof(", target, "()) ", name, "() {
				return ", target, ";
			}
			void ", name, "(typeof(", target, "()) val) {
				", target, " = val;
			}
		");
	} else {
		mixin("
			typeof(", target, ") ", name, "() {
				return ", target, ";
			}
			void ", name, "(typeof(", target, ") val) {
				", target, " = val;
			}
		");
	}
}
mixin template RegisterRedirect(string name, string target, ulong address) {
	alias type = typeof(mixin(target, ".readRegister(0)"));
	mixin("
		type ", name, "() {
			return ", target, ".readRegister(", address, ");
		}
		void ", name, "(type val) {
			.writeRegisterLogged(", target, ", ", address, ", val);
		}
	");
}

mixin template DoubleWriteRegisterRedirect(string name, string target, ulong address) {
	mixin RegisterRedirect!(name, target, address);
	alias doubleType = doubleSized!type;
	mixin("
		void ", name, "(doubleType val) {
			.writeRegisterLogged(", target, ", ", address, ", val & ((1 << (type.sizeof * 8)) - 1));
			.writeRegisterLogged(", target, ", ", address, ", val >> (type.sizeof * 8));
		}
	");
}

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

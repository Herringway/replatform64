module replatform64.registers;

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
			", target, ".writeRegister(", address, ", val);
		}
	");
}

mixin template DoubleWriteRegisterRedirect(string name, string target, ulong address) {
	mixin RegisterRedirect!(name, target, address);
	alias doubleType = doubleSized!type;
	mixin("
		void ", name, "(doubleType val) {
			", target, ".writeRegister(", address, ", val & ((1 << (type.sizeof * 8)) - 1));
			", target, ".writeRegister(", address, ", val >> (type.sizeof * 8));
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

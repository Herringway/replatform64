module librehome.registers;

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
	mixin("
		typeof(", target, ".read(0)) ", name, "() {
			return ", target, ".read(", address, ");
		}
		void ", name, "(typeof(", target, ".read(0)) val) {
			", target, ".write(", address, ", val);
		}
	");
}
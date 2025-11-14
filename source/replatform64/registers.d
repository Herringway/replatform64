module replatform64.registers;

import std.traits : Parameters;

struct DoubleWrite_ {}
enum DoubleWrite = DoubleWrite_();

struct RegisterValueType_(T) {}
enum RegisterValueType(T) = RegisterValueType_!T();

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

mixin template RegisterValue(T, Fields...) {
	import std.bitmanip : bitfields;
	T raw;
	struct {
		mixin(bitfields!Fields);
	}
	this(T raw) @safe pure {
		this.raw = raw;
	}
	mixin(generateConstructor);
	private static string generateConstructor() {
		import std.algorithm.iteration : filter, map;
		import std.array : array, staticArray;
		import std.format : format;
		import std.meta : staticMap;
		import std.range : iota;
		enum FieldName(size_t i) = Fields[i * 3 + 1];
		enum _F = iota(0, Fields.length / 3).array;
		enum FieldNames = [staticMap!(FieldName, _F.staticArray.tupleof)];
		return format!"this(%-(%s, %)) @safe pure { %-(%s; %|%)}"(iota(0, Fields.length / 3).filter!(x => FieldNames[x] != "").map!(x=> format!"Fields[%s] %s"(x * 3, FieldNames[x])), iota(0, Fields.length / 3).filter!(x => FieldNames[x] != "").map!(x=> format!"this.%s = %s"(FieldNames[x], FieldNames[x])));
	}
}

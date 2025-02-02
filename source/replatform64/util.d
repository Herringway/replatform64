module replatform64.util;

import std.algorithm.comparison;
import std.bitmanip;
import std.range;

import replatform64.backend.common.interfaces;

public import tilemagic.util : Array2D;

/// Dumps the game state to a human-readable file
void function(string path) dumpStateToFile = (str) {};

template typeMatches(T) {
	enum typeMatches(alias t) = is(typeof(t) == T);
}

PixelFormat pixelFormat(T)(const Array2D!T) {
	import tilemagic.colours : BGR555;
	static if (is(T == BGR555)) {
		return PixelFormat.bgr555;
	}
}

private struct _NoDump {}
enum NoDump = _NoDump();

private struct _DumpableGameState {}
enum DumpableGameState = _DumpableGameState();

mixin template generateStateDumpFunctions() {
	private import std.meta : Filter;
	private enum isIgnoredStateVar(alias sym) = Filter!(typeMatches!(typeof(NoDump)), __traits(getAttributes, sym)).length == 1;
	private enum isStateVar(alias sym) =
		!isIgnoredStateVar!sym &&
		(Filter!(typeMatches!(typeof(DumpableGameState)), __traits(getAttributes, sym)).length == 1) &&
		__traits(compiles, { sym = sym.init; }) &&
		!__traits(isDeprecated, sym);
	shared static this() {
		dumpStateToFile = &dumpStateToYAML;
	}
	void dumpStateToYAML(string outPath) {
		import siryul : toFile, YAML;
		getState().toFile!YAML(outPath);
	}
	auto getState() {
		static struct State {
			static foreach (mem; __traits(allMembers, mixin(__MODULE__))) {
				static if (isStateVar!(__traits(getMember, mixin(__MODULE__), mem))) {
					mixin("typeof(__traits(getMember, mixin(__MODULE__), mem)) ", mem, ";");
				}
			}
		}
		State result;
		static foreach (mem; __traits(allMembers, mixin(__MODULE__))) {
			static if (isStateVar!(__traits(getMember, mixin(__MODULE__), mem))) {
				__traits(getMember, result, mem) = __traits(getMember, mixin(__MODULE__), mem);
			}
		}
		return result;
	}
}

void wrappedLoad(scope ubyte[] dest, scope const(ubyte)[] source, size_t start) @safe pure {
	const wrappedStart = dest.length - start;
	dest[start .. min(start + source.length, dest.length)] = source[0 .. min(wrappedStart, $)];
	if (start + source.length > dest.length) {
		dest[0 .. wrappedStart] = source[wrappedStart .. $];
	}
}

@safe pure unittest {
	{
		ubyte[4] buf;
		wrappedLoad(buf[], [1,2], 0);
		assert(buf == [1, 2, 0, 0]);
	}
	{
		ubyte[4] buf;
		wrappedLoad(buf[], [1,2], 2);
		assert(buf == [0, 0, 1, 2]);
	}
	{
		ubyte[4] buf;
		wrappedLoad(buf[], [1,2], 3);
		assert(buf == [2, 0, 0, 1]);
	}
	{
		ubyte[4] buf;
		wrappedLoad(buf[], [], 3);
		assert(buf == [0, 0, 0, 0]);
	}
	{
		ubyte[0] buf;
		wrappedLoad(buf[], [], 0);
		assert(buf == []);
	}
}

struct DebugState {
	string group;
	string label;
}
struct Resolution {
	uint width;
	uint height;
}

struct InputState {
	ushort[2] controllers;
	bool exit;
	bool pause;
	bool step;
	bool fastForward;
}

struct RecordedInputState {
	InputState state;
	uint frames;
}

void printRegisterAccess(A, V)(A addr, V val) {
	debug(logRegisters) try {
		import std.algorithm.searching : canFind;
		import std.conv : text;
		import std.logger : tracef;
		import core.runtime;
		auto trace = defaultTraceHandler(null);
		const(char)[] fun;
		foreach (idx, t; trace) {
			// find the first non-replatform64 function
			if (!t.canFind("replatform64.")) {
				// if we got to main(), it's probably a write originating from this library
				if (t.canFind("D main")) {
					break;
				}
				fun = t;
				break;
			}
		}
		enum hexPaddingAddress = text(A.sizeof * 2);
		enum hexPaddingValue = text(V.sizeof * 2);
		// didn't find anything
		if (fun == null) {
			tracef("WRITE: $%0" ~ hexPaddingAddress ~ "X, %0" ~ hexPaddingValue ~ "X", addr, val);
		} else {
			tracef("WRITE: $%0" ~ hexPaddingAddress ~ "X, %0" ~ hexPaddingValue ~ "X (%s)", addr, val, fun);
		}
		defaultTraceDeallocator(trace);
	} catch (Exception) {}
}

bool inRange(T)(T value, T lower, T upper) {
	return (lower <= value) && (upper > value);
}

@safe pure unittest {
	assert(0.inRange(0, 1));
	assert(10.inRange(0, 11));
	assert(!10.inRange(0, 10));
	assert(!9.inRange(10, 11));
}

struct FixedPoint2(size_t size, size_t scaling, bool unsigned = false) {
	import std.algorithm : among;
	import std.math : log2;
	import std.meta : AliasSeq;
	import std.traits : isFloatingPoint, isIntegral, Unsigned;
	private alias Integrals = AliasSeq!(byte, short, int, long, ubyte, ushort, uint, ulong);
	private alias UnderlyingType = Integrals[cast(size_t)log2(size / 8.0) + unsigned * 4];
	private enum scaleMultiplier = ulong(1) << scaling;
	private alias supportedOps = AliasSeq!("+", "-", "/", "*", "%", "^^");
	private UnderlyingType value; ///
	///
	this(double value) @safe pure {
		this.value = cast(UnderlyingType)(value * scaleMultiplier);
	}
	///
	T opCast(T)() const @safe pure if(isFloatingPoint!T) {
		return cast(T)(cast(UnderlyingType)value) / cast(double)scaleMultiplier;
	}
	///
	T opCast(T : FixedPoint2!(otherSize, otherScaling), size_t otherSize, size_t otherScaling)() const @safe pure {
		T newValue;
		static if (otherScaling > scaling) {
			newValue.value = cast(typeof(T.value))(cast(typeof(T.value))value << (otherScaling - scaling));
		} else {
			newValue.value = cast(typeof(T.value))(value >> (scaling - otherScaling));
		}
		return newValue;
	}
	///
	FixedPoint2 opBinary(string op, T)(T value) const if (op.among(supportedOps) && (isFloatingPoint!T || isIntegral!T)) {
		FixedPoint2 result;
		static if ((op == "+") || (op == "-") || (op == "%") || (op == "^^")) {
			result.value = cast(UnderlyingType)mixin("((this.value / scaleMultiplier)", op, "value) * scaleMultiplier");
		} else {
			result.value = cast(UnderlyingType)mixin("this.value", op, "value");
		}
		return result;
	}
	///
	FixedPoint2 opBinaryRight(string op, T)(T value) const if (op.among(supportedOps) && (isFloatingPoint!T || isIntegral!T)) {
		return opBinary!(op)(value);
	}
	///
	FixedPoint2 opBinary(string op, size_t otherSize, size_t otherScaling)(FixedPoint2!(otherSize, otherScaling) value) const if (op.among(supportedOps)) {
		return FixedPoint2(mixin("(cast(double)this)", op, "cast(double)value"));
	}
	///
	FixedPoint2 opUnary(string op : "-")() const {
		return FixedPoint2(-cast(double)this);
	}
	///
	int opCmp(size_t n)(FixedPoint2!n value) const @safe pure {
		return cast(UnderlyingType)value - cast(value.UnderlyingType)value.value;
	}
	///
	int opCmp(double value) const @safe pure {
		import std.math.operations : cmp;
		return cmp(cast(double)this, value);
	}
	///
	int opEquals(FixedPoint2 value) const @safe pure {
		return this.value == value.value;
	}
	///
	int opEquals(double value) const @safe pure {
		return cast(double)this == value;
	}
	///
	FixedPoint2 opAssign(double value) @safe pure {
		this.value = cast(UnderlyingType)(value * scaleMultiplier);
		return this;
	}
	///
	FixedPoint2 opOpAssign(string op)(double value) @safe pure  if (op.among(supportedOps)) {
		this.value = opBinary!op(value).value;
		return this;
	}
	///
	FixedPoint2 opOpAssign(string op)(FixedPoint2 value) @safe pure  if (op.among(supportedOps)) {
		this.value = opBinary!op(value).value;
		return this;
	}
	///
	T opCast(T)() const @safe pure if (isIntegral!T) {
		return cast(T)(value >> scaling);
	}
	///
	void toString(S)(ref S sink) const {
		import std.format : formattedWrite;
		sink.formattedWrite!"%s"(this.asDouble);
	}
	static FixedPoint2 fromRaw(UnderlyingType value) @safe pure {
		FixedPoint2 result;
		result.value = value;
		return result;
	}
	UnderlyingType toRaw() const @safe pure {
		return value;
	}
}

@safe pure unittest {
	import std.math.operations : isClose;
	alias FP64 = FixedPoint2!(64, 32);
	alias FP32 = FixedPoint2!(32, 16);
	alias FP16 = FixedPoint2!(16, 8);
	FP32 sample = 2.0;
	assert(sample.value == 0x00020000);

	assert((cast(double)(FP32(2.0) / 3)).isClose(2.0 / 3.0, 1e-3, 1e-9));
	assert(cast(double)(FP32(2.0) * 3) == 6.0);
	assert(cast(double)(FP32(2.0) % 3) == 2.0);
	assert(cast(double)(FP32(2.0) ^^ 3) == 8.0);
	assert(cast(double)(FP32(2.0) + 3) == 5.0);
	assert(cast(double)(FP32(2.0) - 3) == -1.0);

	assert((cast(double)(FP32(2.0) / 3.0)).isClose(2.0 / 3.0, 1e-3, 1e-9));
	assert(cast(double)(FP32(2.0) * 3.0) == 6.0);
	assert(cast(double)(FP32(2.0) % 3.0) == 2.0);
	assert(cast(double)(FP32(2.0) ^^ 3.0) == 8.0);
	assert(cast(double)(FP32(2.0) + 3.0) == 5.0);
	assert(cast(double)(FP32(2.0) - 3.0) == -1.0);

	assert((cast(double)(FP32(2.0) / FP32(3.0))).isClose(2.0 / 3.0, 1e-3, 1e-9));
	assert(cast(double)(FP32(2.0) * FP32(3.0)) == 6.0);
	assert(cast(double)(FP32(2.0) % FP32(3.0)) == 2.0);
	assert(cast(double)(FP32(2.0) ^^ FP32(3.0)) == 8.0);
	assert(cast(double)(FP32(2.0) + FP32(3.0)) == 5.0);
	assert(cast(double)(FP32(2.0) - FP32(3.0)) == -1.0);

	sample *= 1.5;
	assert(cast(double)sample == 3.0);
	assert(cast(int)sample == 3);
	assert(cast(byte)sample == 3);
	assert(sample.value == 0x00030000);

	assert(cast(FP16)sample == FP16(3.0));
	assert(cast(FP64)sample == FP64(3.0));

	FP16 sample2 = 1.5;
	assert(sample2.value == 0x0180);
	assert(cast(double)(FP32(2.0) * sample2) == 3.0);
	assert(cast(double)(FP32(2.0) - FP16(1.5)) == 0.5);
	assert(cast(double)(FP32(2.0) + FP16(1.5)) == 3.5);

	assert(sample2 * 2.0 == 3.0);
	assert(2.0 * sample2 == 3.0);

	sample = 256.0;
	assert(cast(byte)sample == 0);
	assert(cast(short)sample == 256);
	assert(cast(long)sample == 256);

	sample = -32.0;
	assert(cast(byte)sample == -32);
	assert(cast(short)sample == -32);
	assert(cast(long)sample == -32);

	assert(FP16.fromRaw(0x240).value == 0x240);
}

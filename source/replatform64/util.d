module replatform64.util;

import std.algorithm.comparison;
import std.bitmanip;
import std.range;

/// Dumps the game state to a human-readable file
void function(string path) dumpStateToFile = (str) {};

template typeMatches(T) {
	enum typeMatches(alias t) = is(typeof(t) == T);
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

// from D documentation
struct Array2D(E) {
	import std.format : format;
	import std.traits : isMutable;
	private E[] impl;
	size_t stride;
	private size_t width, height;

	this(size_t width, size_t height) inout {
		this(width, height, width);
	}

	this(size_t width, size_t height, size_t stride) inout {
		this(width, height, stride, new inout E[](width * height));
	}

	this(size_t width, size_t height, inout E[] initialData) inout {
		this(width, height, width, initialData);
	}

	this(size_t width, size_t height, size_t stride, inout E[] initialData) inout
		in(initialData.length == stride * height, format!"Base array has invalid length %s, expecting %s"(initialData.length, stride * height))
	{
		impl = initialData;
		this.stride = stride;
		this.width = width;
		this.height = height;
	}
	size_t[2] dimensions() const @safe pure {
		return [opDollar!0, opDollar!1];
	}

	// Index a single element, e.g., arr[0, 1]
	ref inout(E) opIndex(size_t i, size_t j) inout
		in (i <= width, format!"index [%s,%s] is out of bounds for array of dimensions [%s, %s]"(i, j, width, height))
		in (j <= height, format!"index [%s,%s] is out of bounds for array of dimensions [%s, %s]"(i, j, width, height))
	{
		return impl[i + stride * j];
	}

	// Array slicing, e.g., arr[1..2, 1..2], arr[2, 0..$], arr[0..$, 1].
	inout(Array2D) opIndex(size_t[2] r1, size_t[2] r2) inout
		in(r1[0] <= width, format!"slice [%s..%s] extends beyond array of width %s"(r1[0], r1[1], width))
		in(r1[1] <= width, format!"slice [%s..%s] extends beyond array of width %s"(r1[0], r1[1], width))
		in(r2[0] <= height, format!"slice [%s..%s] extends beyond array of height %s"(r2[0], r2[1], height))
		in(r2[1] <= height, format!"slice [%s..%s] extends beyond array of height %s"(r2[0], r2[1], height))
	{
		auto startOffset = r1[0] + r2[0] * stride;
		auto endOffset = r1[1] + (r2[1] - 1) * stride;

		return (inout Array2D)(r1[1] - r1[0], r2[1] - r2[0], stride, this.impl[startOffset .. (endOffset / stride + !!(endOffset % stride)) * stride]);
	}
	auto opIndex(size_t[2] r1, size_t j) inout {
		return opIndex(r1, [j, j + 1]).impl[0 .. stride];
	}
	auto opIndex(size_t i, size_t[2] r2) inout {
		return opIndex([i, i + 1], r2);
	}
	auto opIndex() inout {
		return impl;
	}
	static if (isMutable!E) {
		auto opAssign(E element) {
			impl[] = element;
		}
		void opIndexAssign(E elem) {
			impl[] = elem;
		}
		void opIndexAssign(E[] elem) {
			impl[] = elem;
		}
		void opIndexAssign(E elem, size_t i, size_t j)
			in (i <= width, format!"index [%s,%s] is out of bounds for array of dimensions [%s, %s]"(i, j, width, height))
			in (j <= height, format!"index [%s,%s] is out of bounds for array of dimensions [%s, %s]"(i, j, width, height))
		{
			impl[i + stride * j] = elem;
		}
		void opIndexAssign(E elem, size_t[2] i, size_t[2] j)
			in (i[0] <= width, format!"index [%s..%s,%s..%s] is out of bounds for array of dimensions [%s, %s]"(i[0], i[1], j[0], j[1], width, height))
			in (j[0] <= height, format!"index [%s..%s,%s..%s] is out of bounds for array of dimensions [%s, %s]"(i[0], i[1], j[0], j[1], width, height))
			in (i[1] <= width, format!"index [%s..%s,%s..%s] is out of bounds for array of dimensions [%s, %s]"(i[0], i[1], j[0], j[1], width, height))
			in (j[1] <= height, format!"index [%s..%s,%s..%s] is out of bounds for array of dimensions [%s, %s]"(i[0], i[1], j[0], j[1], width, height))
		{
			foreach (row; j[0] .. j[1]) {
				impl[row * stride + i[0] .. row * stride + i[1]] = elem;
			}
		}
		void opIndexAssign(E elem, size_t i, size_t[2] j) {
			opIndexAssign(elem, [i, i+1], j);
		}
		void opIndexAssign(E elem, size_t[2] i, size_t j) {
			opIndexAssign(elem, i, [j, j+1]);
		}
	}
	Array2D!NewElement opCast(T : Array2D!NewElement, NewElement)() if (NewElement.sizeof == E.sizeof) {
		return Array2D!NewElement(width, height, stride, cast(NewElement[])impl);
	}

	// Support for `x..y` notation in slicing operator for the given dimension.
	size_t[2] opSlice(size_t dim)(size_t start, size_t end) const
	if (dim >= 0 && dim < 2)
	in(start >= 0 && end <= this.opDollar!dim)
	{
		return [start, end];
	}

	// Support `$` in slicing notation, e.g., arr[1..$, 0..$-1].
	size_t opDollar(size_t dim : 0)() const {
		return width;
	}
	size_t opDollar(size_t dim : 1)() const {
		return height;
	}
	void toString(R)(ref R sink) const {
		import std.format : formattedWrite;
		foreach (row; 0 .. height) {
			sink.formattedWrite!"%s\n"(this[0 .. $, row]);
		}
	}
	alias opApply = opApplyImpl!(int delegate(size_t x, size_t y, ref E element));
	int opApplyImpl(DG)(scope DG dg) {
		foreach (iterY; 0 .. height) {
			foreach (iterX, ref elem; this[0 .. $, iterY][]) {
				auto result = dg(iterX, iterY, elem);
				if (result) {
					return result;
				}
			}
		}
		return 0;
	}
}

@safe pure unittest {
	import std.array : array;
	import std.range : iota;
	auto tmp = Array2D!int(5, 6, iota(5*6).array);
	assert(tmp[2, 1] == 7);
	assert(tmp[$ - 1, $ - 1] == 29);
	assert(tmp[0 .. $, 0] == [0, 1, 2, 3, 4]);
	assert(tmp[0 .. $, 5] == [25, 26, 27, 28, 29]);
	assert(tmp[0, 0 .. $][0, 2] == 10);

	tmp = 42;
	assert(tmp[2, 1] == 42);
	tmp[0 .. 2, 0 .. 2] = 31;
	assert(tmp[1, 1] == 31);
	assert(tmp[2, 2] == 42);
	tmp[0, 0 .. 2] = 18;
	assert(tmp[0, 1] == 18);
	assert(tmp[1, 1] == 31);
	tmp[0 .. 2, 0] = 77;
	assert(tmp[1, 0] == 77);
	assert(tmp[1, 1] == 31);

	(cast(Array2D!(ushort[2]))tmp)[2,1] = [1, 2];
	assert(tmp[2, 1] == 0x00020001);
	immutable tmp2 = (cast(immutable Array2D!(ushort[2]))tmp);
	assert(tmp2[2,1] == [1,2]);
}

auto array2D(T)(return T[] array, int width, int height) {
	return Array2D!T(width, height, array);
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

package const(ubyte)[] bgr555ToRGBA8888(const ubyte[] source, uint sourceStride) @safe pure {
	static union PixelConverter {
		ushort data;
		struct {
			mixin(bitfields!(
				ubyte, "r", 5,
				ubyte, "g", 5,
				ubyte, "b", 5,
				bool, "", 1,
			));
		}
	}
	const(uint)[] result;
	result.reserve(source.length / 2);
	foreach (rowRaw; source.chunks(sourceStride)) {
		foreach (pixel; cast(const ushort[])rowRaw) {
			const pixelParsed = PixelConverter(pixel);
			result ~= 0xFF000000 | (pixelParsed.r << 19) | (pixelParsed.g << 11) | (pixelParsed.b << 3);
		}
	}
	return cast(const(ubyte)[])result;
}

module librehome.common;

import std.algorithm.comparison;

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


// from D documentation
struct Array2D(E) {
	import std.format : format;
	import std.traits : isMutable;
	E[] impl;
	int stride;
	int width, height;

	this(int width, int height, E[] initialData = []) {
		impl = initialData;
		this.stride = this.width = width;
		this.height = height;
		impl.length = width * height;
	}

	// Index a single element, e.g., arr[0, 1]
	ref inout(E) opIndex(int i, int j) inout {
		return impl[i + stride * j];
	}

	// Array slicing, e.g., arr[1..2, 1..2], arr[2, 0..$], arr[0..$, 1].
	Array2D opIndex(int[2] r1, int[2] r2) inout
		in(r1[0] <= width, format!"slice [%s..%s] extends beyond array of width %s"(r1[0], r1[1], width))
		in(r1[1] <= width, format!"slice [%s..%s] extends beyond array of width %s"(r1[0], r1[1], width))
		in(r2[0] <= height, format!"slice [%s..%s] extends beyond array of height %s"(r2[0], r2[1], height))
		in(r2[1] <= height, format!"slice [%s..%s] extends beyond array of height %s"(r2[0], r2[1], height))
	{
		Array2D result;

		auto startOffset = r1[0] + r2[0] * stride;
		auto endOffset = r1[1] + (r2[1] - 1) * stride;
		result.impl = this.impl[startOffset .. endOffset];

		result.stride = this.stride;
		result.width = r1[1] - r1[0];
		result.height = r2[1] - r2[0];

		return result;
	}
	auto opIndex(int[2] r1, int j) inout {
		return opIndex(r1, [j, j + 1]).impl;
	}
	auto opIndex(int i, int[2] r2) inout {
		return opIndex([i, i + 1], r2);
	}
	auto opIndex() inout {
		return impl;
	}
	static if (isMutable!E) {
		auto opAssign(E element) {
			impl[] = element;
		}
	}

	// Support for `x..y` notation in slicing operator for the given dimension.
	int[2] opSlice(size_t dim)(int start, int end) const
	if (dim >= 0 && dim < 2)
	in(start >= 0 && end <= this.opDollar!dim)
	{
		return [start, end];
	}

	// Support `$` in slicing notation, e.g., arr[1..$, 0..$-1].
	int opDollar(size_t dim : 0)() const {
		return width;
	}
	int opDollar(size_t dim : 1)() const {
		return height;
	}
}

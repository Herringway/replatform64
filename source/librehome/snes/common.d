module librehome.snes.common;

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

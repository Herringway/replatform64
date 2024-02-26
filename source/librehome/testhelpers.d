module librehome.testhelpers;

package:

static void comparePNG(const ubyte[] frame, string comparePath, uint width, uint height) {
	import std.format : format;
	import std.path : buildPath;
	import arsd.png : PngType, readPng, writePng;
	auto reference = readPng(buildPath("testdata/snes", comparePath));
	const pixels = Array2D!(const(uint))(width, height, cast(const(uint)[])frame);
	foreach (x; 0 .. width) {
		foreach (y; 0 .. height) {
			if (reference.getPixel(x, y).asUint != pixels[x, y]) {
				writePng(comparePath, frame, width, height, PngType.truecolor_with_alpha);
				assert(0, format!"Pixel mismatch at %s, %s in %s (got %08X, expecting %08X)"(x, y, comparePath, pixels[x, y], reference.getPixel(x, y).asUint));
			}
		}
	}
}

void loadMesen2SaveState(const(ubyte)[] file, scope void delegate(const char[] key, const ubyte[] data) @safe pure dg) @safe pure {
	import std.algorithm.searching : countUntil;
	import std.zlib : uncompress;
	static struct MSSHeader {
		align(1):
		char[3] magic;
		uint emuVersion;
		uint formatVersion;
		uint console;
	}
	static struct MSSFBHeader {
		align(1):
		uint fbSize;
		uint width;
		uint height;
		uint scale;
		uint compressedSize;
	}
	static const(ubyte)[] popBytes(ref const(ubyte)[] buf, size_t size) {
		scope(exit) buf = buf[size .. $];
		return buf[0 .. size];
	}
	const header = (cast(const(MSSHeader)[])(popBytes(file, MSSHeader.sizeof)))[0];
	assert(header.magic == "MSS", "Not a save state");
	assert(header.console == 0, "Not SNES");
	assert(header.formatVersion == 4, "Not a compatible format");
	const fbHeader = (cast(const(MSSFBHeader)[])(popBytes(file, MSSFBHeader.sizeof)))[0];
	auto fb = popBytes(file, fbHeader.compressedSize);
	const romNameSize = (cast(const(uint)[])(popBytes(file, uint.sizeof)))[0];
	const romName = cast(const(char)[])popBytes(file, romNameSize);
	const(ubyte)[] decompressed;
	if (popBytes(file, 1)[0] == 1) {
		static const(ubyte)[] trustedDecompress(const ubyte[] data, size_t length) @trusted pure {
			ubyte[] function(const(ubyte)[] data, size_t length, int winbits = 15) @safe pure decompress;
			decompress = cast(typeof(decompress))&uncompress;
			return decompress(data, length);
		}
		const decompressedSize = (cast(const(uint)[])(popBytes(file, uint.sizeof)))[0];
		const compressedSize = (cast(const(uint)[])(popBytes(file, uint.sizeof)))[0];
		decompressed = trustedDecompress(file, decompressedSize);
	} else {
		decompressed = file;
	}
	while (decompressed.length > 0) {
		// read null-terminated string
		const key = (cast(const(char)[])popBytes(decompressed, decompressed.countUntil('\0') + 1))[0 .. $ - 1];
		const dataSize = (cast(const(uint)[])popBytes(decompressed, uint.sizeof))[0];
		auto data = popBytes(decompressed, dataSize);
		dg(key, data);
	}
}

// from D documentation
struct Array2D(E) {
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
	Array2D opIndex(int[2] r1, int[2] r2) {
		Array2D result;

		auto startOffset = r1[0] + r2[0] * stride;
		auto endOffset = r1[1] + (r2[1] - 1) * stride;
		result.impl = this.impl[startOffset .. endOffset];

		result.stride = this.stride;
		result.width = r1[1] - r1[0];
		result.height = r2[1] - r2[0];

		return result;
	}
	auto opIndex(int[2] r1, int j) {
		return opIndex(r1, [j, j + 1]);
	}
	auto opIndex(int i, int[2] r2) {
		return opIndex([i, i + 1], r2);
	}

	// Support for `x..y` notation in slicing operator for the given dimension.
	int[2] opSlice(size_t dim)(int start, int end)
	if (dim >= 0 && dim < 2)
	in(start >= 0 && end <= this.opDollar!dim)
	{
		return [start, end];
	}

	// Support `$` in slicing notation, e.g., arr[1..$, 0..$-1].
	int opDollar(size_t dim : 0)() {
		return width;
	}
	int opDollar(size_t dim : 1)() {
		return height;
	}
}

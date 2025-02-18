module replatform64.testhelpers;

import replatform64.backend.common.interfaces;
import replatform64.dumping;
import replatform64.util;

import tilemagic.colours;

package:

auto comparePNG(T)(const Array2D!T frame, string baseDir, string comparePath) {
	import std.format : format;
	import std.path : buildPath;
	import justimages.png : readPng;
	static struct Result {
		size_t x = size_t.max;
		size_t y = size_t.max;
		ABGR8888 expected;
		ABGR8888 got;
		bool opCast(T: bool)() const {
			return (x != size_t.max) && (y != size_t.max);
		}
	}
	auto reference = readPng(buildPath(baseDir, comparePath));
	foreach (x, y, pixel; frame) {
		const refPixel = reference[x, y];
		if (!pixel.isSimilar(refPixel)) {
			return Result(x, y, refPixel.convert!ABGR8888, pixel.convert!ABGR8888);
		}
	}
	return Result();
}

void loadMesen2SaveState(const(ubyte)[] file, uint system, scope void delegate(const char[] key, const ubyte[] data) @safe pure dg) @safe pure {
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
	assert(header.console == system, "Savestate is for wrong system");
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

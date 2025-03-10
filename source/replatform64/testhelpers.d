module replatform64.testhelpers;

import replatform64.dumping;
import replatform64.util;

import pixelmancy.colours;

import std.file;
import std.format;
import std.path;
import std.stdio;

package:

auto comparePNG(T)(const Array2D!T frame, string baseDir, string comparePath) {
	import std.format : format;
	import std.path : buildPath;
	import pixelmancy.fileformats.png : readPng;
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

bool runTests(alias render, T...)(string platform, string suffix, T extra) {
	uint tests;
	uint testSuccesses;
	foreach (state; dirEntries(buildPath("testdata", platform), "*.mss", SpanMode.shallow)) {
		testSuccesses += !runTest!render(platform, state.baseName.stripExtension, suffix, extra);
		tests++;
	}
	writef!"%s/%s tests succeeded"(testSuccesses, tests);
	if (suffix != "") {
		writef!" (%s)"(suffix);
	}
	writeln();
	return tests == testSuccesses;
}

struct FauxDMA {
	ushort scanline;
	uint register;
	ubyte value;
}
bool runTest(alias render, T...)(string platform, string testName, string suffix, T extra) {
	import std.conv : to;
	import std.string : split;
	auto file = cast(ubyte[])read(buildPath("testdata", platform, testName ~ ".mss"));
	FauxDMA[] dma;
	const dmaPath = buildPath("testdata", platform, testName ~ ".dma");
	if (dmaPath.exists) {
		foreach (line; File(dmaPath, "r").byLine) {
			auto splitLine = line.split(" ");
			dma ~= FauxDMA(splitLine[0].to!ushort, splitLine[1].to!uint(16), splitLine[2].to!ubyte(16));
		}
	}
	const expected = !buildPath("testdata", platform, testName ~ "." ~ suffix ~ "expectedfail").exists;
	const frame = render(file, dma, extra);
	const outputDir = buildPath("failed", platform);
	if (const result = comparePNG(frame, buildPath("testdata", platform), testName ~ ".png")) {
		mkdirRecurse(outputDir);
		writePNG(frame, buildPath(outputDir, testName ~ (suffix != "" ? "-" ~ suffix : "") ~ ".png"));
		writefln!"%s pixel mismatch at %s, %s in %s (got %s, expecting %s)"(["\x1B[32mExpected\x1B[0m", "\x1B[31mUnexpected\x1B[0m"][expected], result.x, result.y, testName, result.got, result.expected);
		return expected;
	} else if (!expected) {
		writefln!"%s success in %s"("\x1B[31mUnexpected\x1B[0m", testName);
	}
	return !expected;
}

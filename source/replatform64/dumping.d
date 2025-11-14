module replatform64.dumping;

import std.conv;
import std.datetime;
import std.file;
import std.format;
import std.logger;
import std.path;
import std.stdio;
import std.traits;

import pixelmancy.fileformats.png;
import pixelmancy.colours : RGBA32;

import replatform64.util;

public import siryul : Skip;

alias StateDumper = void delegate(scope string filename, scope const(ubyte)[] data) @safe;
alias StateDumperFunction = void function(scope string filename, scope const(ubyte)[] data) @safe;
alias CrashHandler = void delegate(StateDumper) @safe;

__gshared CrashHandler crashHandler;
string repositoryURL;

package shared string otherThreadCrashMsg;
package shared Throwable.TraceInfo otherThreadCrashTrace;
package shared bool otherThreadCrashed;

string prepareDumpBase() {
	const dir = "dump".absolutePath;
	mkdirRecurse(dir);
	return dir;
}

string prepareDumpDirectory() {
	const dir = buildNormalizedPath("dump", format!"dump %s"(Clock.currTime.toISOString)).absolutePath;
	mkdirRecurse(dir);
	return dir;
}

string prepareCrashDirectory() {
	const dir = buildNormalizedPath("dump", format!"crash %s"(Clock.currTime.toISOString)).absolutePath;
	mkdirRecurse(dir);
	return dir;
}

noreturn writeDebugDumpOtherThread(string msg, Throwable.TraceInfo traceInfo) nothrow @trusted {
	otherThreadCrashMsg = msg;
	otherThreadCrashTrace = cast(shared)traceInfo;
	otherThreadCrashed = true;
	while(true) {}
}
void writeDebugDump(string msg, Throwable.TraceInfo traceInfo) @safe {
	auto crashDir = buildNormalizedPath("dump", format!"crash %s"(Clock.currTime.toISOString)).absolutePath;
	mkdirRecurse(crashDir);
	void addFile(string filename, scope const(ubyte)[] data) @trusted {
		File(buildPath(crashDir, filename), "w").rawWrite(data);
	}
	static void trustedWriteDebugMessage(StateDumper addFile, string msg, Throwable.TraceInfo traceInfo) @trusted {
		addFile("trace.txt", cast(const(ubyte)[])text(msg, "\n", traceInfo));
	}
	trustedWriteDebugMessage(&addFile, msg, traceInfo);
	dumpStateToFile(buildPath(crashDir, "state.yaml"));
	() @trusted { assert(crashHandler); crashHandler(&addFile); }();
	if (repositoryURL != "") {
		infof("Game crashed! Details written to '%s', please report this bug at %s with as many details as you can include.", crashDir, repositoryURL);
	} else {
		infof("Game crashed! Details written to '%s'.", crashDir);
	}
	debug writeln(msg, "\n", traceInfo);
}

Array2D!Target convert(Target, Source)(const Array2D!Source frame) {
	import pixelmancy.colours.formats : convert;
	auto result = Array2D!Target(frame.dimensions[0], frame.dimensions[1]);
	foreach (x, y, pixel; frame) {
		result[x, y] = pixel.convert!Target();
	}
	return result;
}

const(ubyte)[] dumpPNG(ref Texture texture) @safe {
	final switch (texture.format) {
		static foreach (pixelFormat; EnumMembers!PixelFormat) {
			case pixelFormat:
				return dumpPNG(texture.asArray2D!(ColourFormatOf!pixelFormat));
		}
	}
}

const(ubyte)[] dumpPNG(T)(const Array2D!T pixels) {
	PngHeader h;
	h.width = cast(uint)pixels.width;
	h.height = cast(uint)pixels.height;
	h.type = cast(ubyte)PngType.truecolor_with_alpha;
	h.depth = 8;

	auto png = blankPNG(h);
	addImageDatastreamToPng(cast(const(ubyte)[])(pixels.convert!RGBA32[]), png);

	return writePng(png);
}

void writePNG(T)(const Array2D!T pixels, string filename) {
	File(filename, "w").rawWrite(dumpPNG(pixels));
}

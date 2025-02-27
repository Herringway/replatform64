module replatform64.dumping;

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

alias CrashHandler = void delegate(string);

CrashHandler crashHandler;
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

noreturn writeDebugDumpOtherThread(string msg, Throwable.TraceInfo traceInfo) nothrow {
	otherThreadCrashMsg = msg;
	otherThreadCrashTrace = cast(shared)traceInfo;
	otherThreadCrashed = true;
	while(true) {}
}
void writeDebugDump(string msg, Throwable.TraceInfo traceInfo) {
	auto crashDir = buildNormalizedPath("dump", format!"crash %s"(Clock.currTime.toISOString)).absolutePath;
	mkdirRecurse(crashDir);
	File(buildPath(crashDir, "trace.txt"), "w").write(msg, "\n", traceInfo);
	dumpStateToFile(buildPath(crashDir, "state.yaml"));
	crashHandler(crashDir);
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

void dumpPNG(ref Texture texture, string file) {
	sw: final switch (texture.format) {
		static foreach (pixelFormat; EnumMembers!PixelFormat) {
			case pixelFormat:
				dumpPNG(texture.asArray2D!(ColourFormatOf!pixelFormat), file);
				break sw;
		}
	}
}
void dumpPNG(T)(const Array2D!T pixels, string file) {
	writePng(file, pixels.convert!RGBA32(), PngType.truecolor_with_alpha);
}

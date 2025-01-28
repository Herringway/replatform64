module replatform64.dumping;

import std.datetime;
import std.file;
import std.format;
import std.logger;
import std.path;
import std.stdio;

import arsd.png;

import replatform64.backend.common.interfaces;
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

Array2D!ABGR8888 convert(const Array2D!ARGB8888 frame) {
	auto result = Array2D!ABGR8888(frame.dimensions[0], frame.dimensions[1]);
	foreach (x, y, pixel; frame) {
		result[x, y] = ABGR8888(pixel.red, pixel.green, pixel.blue);
	}
	return result;
}

Array2D!ABGR8888 convert(const Array2D!BGR555 frame) {
	auto result = Array2D!ABGR8888(frame.dimensions[0], frame.dimensions[1]);
	foreach (x, y, pixel; frame) {
		result[x, y] = ABGR8888(cast(ubyte)(pixel.red << 3), cast(ubyte)(pixel.green << 3), cast(ubyte)(pixel.blue << 3));
	}
	return result;
}

static void dumpPNG(T)(const Array2D!T frame, string file) {
	dumpPNG(convert(frame), file);
}
static void dumpPNG(const Array2D!ABGR8888 frame, string file) {
	import arsd.png : PngType, writePng;
	writePng(file, cast(ubyte[])frame[], cast(int)frame.dimensions[0], cast(int)frame.dimensions[1], PngType.truecolor_with_alpha);
}

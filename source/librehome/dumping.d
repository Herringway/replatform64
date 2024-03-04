module librehome.dumping;

import std.datetime;
import std.file;
import std.format;
import std.logger;
import std.path;

import arsd.png;

alias CrashHandler = void delegate(string);

CrashHandler crashHandler;

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
	import std.datetime : Clock;
	import std.file : mkdirRecurse;
	import std.path : absolutePath, buildNormalizedPath, buildPath;
	import std.stdio : File, writeln;
	auto crashDir = buildNormalizedPath("dump", format!"crash %s"(Clock.currTime.toISOString)).absolutePath;
	mkdirRecurse(crashDir);
	File(buildPath(crashDir, "trace.txt"), "w").write(msg, "\n", traceInfo);
	if (crashHandler) {
		crashHandler(crashDir);
	}
	infof("Game crashed! Details written to '%s', please report this bug at https://github.com/Herringway/earthbound/issues with as many details as you can include.", crashDir);
	debug writeln(msg, "\n", traceInfo);
}

void dumpScreen(const ubyte[] screen, string path, int width, int height) {
	writePng(buildPath(path, "screen.png"), screen, width, height, PngType.truecolor_with_alpha);
}

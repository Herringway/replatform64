module librehome.watchdog;

import librehome.backend.common;

import arsd.png;

import core.stdc.stdlib;
import core.thread;
import core.time;
import std.format;
import std.logger;
import std.path;

version(Windows) {
	import core.sys.windows.stacktrace;
	import core.sys.windows.winbase;
	import core.sys.windows.winnt;
}
// Windows hang detection takes five seconds to kick in, Might as well use the same duration here.
private enum hangThreshold = 5.seconds;

private Thread watchThread;
///
shared SimpleWatchDog watchDog;

private shared string otherThreadCrashMsg;
private shared Throwable.TraceInfo otherThreadCrashTrace;
private shared bool otherThreadCrashed;

alias CrashHandler = void delegate(string);

CrashHandler crashHandler;

///
struct SimpleWatchDog {
	private MonoTime lastPetting;
	version(Windows) {
		private DWORD watchThread;
	}
	/// Pet the watchdog, so it knows that the thread is okay
	void pet() shared @trusted {
		if (otherThreadCrashed) {
			writeDebugDump(cast()otherThreadCrashMsg, cast()otherThreadCrashTrace);
			exit(1);
		}
		lastPetting = MonoTime.currTime();
	}
	/// Whether or not the watchdog is alarmed by a lack of pets in the last few seconds.
	bool alarmed() const shared @safe {
		return MonoTime.currTime() - lastPetting > hangThreshold;
	}
	private void printStackTrace() const shared {
		// for now, this functionality is windows-exclusive.
		// it might not be necessary on POSIX systems if we can install a signal handler that throws instead...
		version(Windows) {
			// get thread handle
			HANDLE thread = OpenThread(THREAD_ALL_ACCESS, false, watchThread);
			CONTEXT context;
			context.ContextFlags = CONTEXT_FULL;
			// can't get thread context while it's active
			SuspendThread(thread);
			// get thread context and create stack trace from it
			GetThreadContext(thread, &context);
			scope stackTrace = new StackTrace(0, &context);
			writeDebugDump("Hang detected", stackTrace);
		}
	}
}
/// Main function for the watchdog thread. If a hang is detected, generate a crash dump and exit
noreturn watchGameLogic() {
	while(true) {
		if (watchDog.alarmed) {
			watchDog.printStackTrace();
			break;
		}
		Thread.sleep(1.seconds);
	}
	exit(1);
}
/// Create a watchdog thread for the current thread.
/// Note that although multiple watchdogs can be created, they will share the same thread to watch.
void startWatchDog() {
	version(Windows) {
		watchDog.watchThread = GetCurrentThreadId();
	}
	watchThread = new Thread(&watchGameLogic).start;
	watchThread.isDaemon = true;
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

module replatform64.util;

import std.algorithm.comparison;
import std.bitmanip;
import std.range;

public import tilemagic.util : Array2D;

/// Dumps the game state to a human-readable file
void function(string path) dumpStateToFile = (str) {};

template typeMatches(T) {
	enum typeMatches(alias t) = is(typeof(t) == T);
}

private struct _NoDump {}
enum NoDump = _NoDump();

private struct _DumpableGameState {}
enum DumpableGameState = _DumpableGameState();

mixin template generateStateDumpFunctions() {
	private import std.meta : Filter;
	private enum isIgnoredStateVar(alias sym) = Filter!(typeMatches!(typeof(NoDump)), __traits(getAttributes, sym)).length == 1;
	private enum isStateVar(alias sym) =
		!isIgnoredStateVar!sym &&
		(Filter!(typeMatches!(typeof(DumpableGameState)), __traits(getAttributes, sym)).length == 1) &&
		__traits(compiles, { sym = sym.init; }) &&
		!__traits(isDeprecated, sym);
	shared static this() {
		dumpStateToFile = &dumpStateToYAML;
	}
	void dumpStateToYAML(string outPath) {
		import siryul : toFile, YAML;
		getState().toFile!YAML(outPath);
	}
	auto getState() {
		static struct State {
			static foreach (mem; __traits(allMembers, mixin(__MODULE__))) {
				static if (isStateVar!(__traits(getMember, mixin(__MODULE__), mem))) {
					mixin("typeof(__traits(getMember, mixin(__MODULE__), mem)) ", mem, ";");
				}
			}
		}
		State result;
		static foreach (mem; __traits(allMembers, mixin(__MODULE__))) {
			static if (isStateVar!(__traits(getMember, mixin(__MODULE__), mem))) {
				__traits(getMember, result, mem) = __traits(getMember, mixin(__MODULE__), mem);
			}
		}
		return result;
	}
}

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
struct Resolution {
	uint width;
	uint height;
}

struct InputState {
	ushort[2] controllers;
	bool exit;
	bool pause;
	bool step;
	bool fastForward;
}

struct RecordedInputState {
	InputState state;
	uint frames;
}

void printRegisterAccess(A, V)(A addr, V val) {
	debug(logRegisters) try {
		import std.algorithm.searching : canFind;
		import std.conv : text;
		import std.logger : tracef;
		import core.runtime;
		auto trace = defaultTraceHandler(null);
		const(char)[] fun;
		foreach (idx, t; trace) {
			// find the first non-replatform64 function
			if (!t.canFind("replatform64.")) {
				// if we got to main(), it's probably a write originating from this library
				if (t.canFind("D main")) {
					break;
				}
				fun = t;
				break;
			}
		}
		enum hexPaddingAddress = text(A.sizeof * 2);
		enum hexPaddingValue = text(V.sizeof * 2);
		// didn't find anything
		if (fun == null) {
			tracef("WRITE: $%0" ~ hexPaddingAddress ~ "X, %0" ~ hexPaddingValue ~ "X", addr, val);
		} else {
			tracef("WRITE: $%0" ~ hexPaddingAddress ~ "X, %0" ~ hexPaddingValue ~ "X (%s)", addr, val, fun);
		}
		defaultTraceDeallocator(trace);
	} catch (Exception) {}
}

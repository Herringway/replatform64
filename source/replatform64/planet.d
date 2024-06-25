module replatform64.planet;

import replatform64.backend.common.interfaces;
import replatform64.ui;

import core.stdc.stdlib;
import core.time;
import std.array;
import std.algorithm.iteration;
import std.algorithm.searching;
import std.bitmanip;
import std.concurrency;
import std.range;
import std.string;
import std.traits;
import squiz_box;

struct Progress {
	string title;
	uint completedItems = 0;
	uint totalItems = 1;
}

alias ProgressUpdateFunction = void delegate(scope const Progress);
alias AddFileFunction = void delegate(string, const ubyte[]);
alias ExtractFunction = void function(scope AddFileFunction, scope ProgressUpdateFunction, immutable(ubyte)[]);
alias LoadFunction = void function(const scope char[], const scope ubyte[], scope PlatformBackend);

struct PlanetArchive {
	private UnboxEntry[] loaded;
	private InfoBoxEntry[] files;
	void addFile(scope const(char)[] name, const(ubyte)[] data)
		in(!files.map!(x => x.path).canFind(name), name~" already exists in archive!")
	{
		files ~= infoEntry(BoxEntryInfo(name.idup), only(data));
	}
	void write(OutputRange)(OutputRange range) {
		import std.algorithm.mutation : copy;
		copy(files.boxZip(), range);
	}
	static PlanetArchive read(ubyte[] buffer) {
		return PlanetArchive(buffer.unboxZip.array);
	}
	private struct Entry {
		string name;
		ubyte[] data;
	}
	auto entries() {
		return loaded.map!(x => Entry(x.path, x.readContent));
	}
}

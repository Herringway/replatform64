module replatform64.planet;

import replatform64.backend.common.interfaces;
import replatform64.ui;

import core.stdc.stdlib;
import core.time;
import std.algorithm.iteration;
import std.bitmanip;
import std.concurrency;
import std.string;
import std.traits;
import std.zip;

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
	ZipArchive zip;
	void addFile(scope const(char)[] name, const(ubyte)[] data) {
		if (zip is null) {
			zip = new ZipArchive;
		}
		auto newFile = new ArchiveMember;
		newFile.name = name.idup;
		newFile.expandedData = data.dup;
		newFile.compressionMethod = CompressionMethod.deflate;
		zip.addMember(newFile);
	}
	void write(OutputRange)(OutputRange range) {
		import std.algorithm.mutation : copy;
		copy(cast(ubyte[])zip.build, range);
	}
	static PlanetArchive read(ubyte[] buffer) {
		return PlanetArchive(new ZipArchive(buffer));
	}
	private struct Entry {
		string name;
		ubyte[] data;
	}
	auto entries() {
		return zip.directory.values.map!(x => Entry(x.name, zip.expand(x)));
	}
}

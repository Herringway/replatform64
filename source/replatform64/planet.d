module replatform64.planet;

import replatform64.backend.common.interfaces;
import replatform64.ui;

import core.stdc.stdlib;
import core.time;
import std.bitmanip;
import std.concurrency;
import std.string;
import std.traits;

struct Progress {
	string title;
	uint completedItems = 0;
	uint totalItems = 1;
}

alias ProgressUpdateFunction = void delegate(scope const Progress);
alias ExtractFunction = void function(scope ref PlanetArchive, scope ProgressUpdateFunction, immutable(ubyte)[]);
alias LoadFunction = void function(const PlanetArchive, const scope PlanetArchive.Entry);

struct PlanetArchive {
	static struct Header {
		align(8):
		char[8] magic = "PLANET!?";
		ulong entries;
		ulong dataOffset;
		ulong entryOffset = Header.sizeof;
		ubyte[32] reserved;
	}
	static struct Entry {
		align(8):
		char[256] _name = '\0';
		ulong offset;
		ulong size;
		const(char)[] name() const return @safe pure {
			return _name.fromStringz;
		}
	}
	Header header;
	Entry[] entries;
	const(ubyte)[] data;
	void write(OutputRange)(OutputRange range) const {
		void writeLittleEndian(T)(const T structure) {
			static foreach (i, field; structure.tupleof) {
				static if (isArray!(typeof(field))) {
					range.put(cast(const(ubyte)[])structure.tupleof[i]);
				} else {
					range.append!(typeof(field), Endian.littleEndian)(structure.tupleof[i]);
				}
			}
		}
		writeLittleEndian(header);
		foreach (entry; entries) {
			writeLittleEndian(entry);
		}
		range.put(data);
	}
	static PlanetArchive read(ubyte[] buffer) {
		static T readLittleEndian(T)(ubyte[] data) {
			T structure;
			static foreach (i, field; T.tupleof) {
				static if (isArray!(typeof(field))) {
					structure.tupleof[i] = cast(typeof(field))data[0 .. field.sizeof];
				} else {
					structure.tupleof[i] = data.peek!(typeof(field), Endian.littleEndian)();
				}
				data = data[field.sizeof .. $];
			}
			return structure;
		}
		PlanetArchive archive;
		archive.header = readLittleEndian!Header(buffer);
		archive.entries.reserve(archive.header.entries);
		foreach (i; 0 .. archive.header.entries) {
			archive.entries ~= readLittleEndian!Entry(buffer[archive.header.entryOffset + i * Entry.sizeof .. archive.header.entryOffset + (i + 1) * Entry.sizeof]);
		}
		archive.data = buffer[archive.header.dataOffset .. $];
		return archive;
	}
	void addFile(const(char)[] name, const(ubyte)[] data) {
		const offset = this.data.length;
		header.entries++;
		header.dataOffset = Header.sizeof + header.entries * Entry.sizeof;
		Entry entry;
		entry._name[0 .. name.length] = name;
		entry.offset = offset;
		entry.size = data.length;
		entries ~= entry;
		this.data ~= data;
	}
	const(ubyte)[] getData(const Entry entry) const @safe pure {
		return data[entry.offset .. entry.offset + entry.size];
	}
}

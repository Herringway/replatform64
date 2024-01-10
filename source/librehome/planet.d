module librehome.planet;

import librehome.backend.common.interfaces;
import librehome.ui;

import core.stdc.stdlib;
import core.time;
import std.bitmanip;
import std.concurrency;
import std.traits;

alias ExtractFunction = void function(Tid, immutable(ubyte)[], string);

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
		char[256] name = '\0';
		ulong offset;
		ulong size;
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
		entry.name[0 .. name.length] = name;
		entry.offset = offset;
		entry.size = data.length;
		entries ~= entry;
		this.data ~= data;
	}
}

void extractAssets(ExtractFunction extractor, scope PlatformBackend backend, immutable(ubyte)[] data, string baseDir) {
	auto extractorThread = spawn(extractor, thisTid, data, baseDir);
	bool extractionDone;
	string lastMessage = "Initializing";
	void renderExtractionUI() {
		ImGui.SetNextWindowPos(ImGui.GetMainViewport().GetCenter(), ImGuiCond.Appearing, ImVec2(0.5f, 0.5f));
		ImGui.Begin("Creating planet archive", null, ImGuiWindowFlags.NoMove | ImGuiWindowFlags.NoResize | ImGuiWindowFlags.NoCollapse);
			Spinner("##spinning", 15, 6,  ImGui.GetColorU32(ImGuiCol.ButtonHovered));
			ImGui.SameLine();
			ImGui.Text("Extracting assets. Please wait.");
			ImGui.Text(lastMessage);
		ImGui.End();
	}
	while (!extractionDone) {
		receiveTimeout(0.seconds,
			(bool) { extractionDone = true; },
			(string msg) { lastMessage = msg; }
		);
		if (backend.processEvents() || backend.input.getState().exit) {
			exit(0);
		}
		backend.video.startFrame();
		renderExtractionUI();
		backend.video.finishFrame();
		backend.video.waitNextFrame();
	}
}

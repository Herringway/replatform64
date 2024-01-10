module librehome.snes.audio;

import librehome.backend.common;
import librehome.common;

import spc700;
import nspcplay;

struct SPC700Emulated {
	SNES_SPC snes_spc;
	SPC_Filter filter;
	bool initialized;
	void initialize() {
		snes_spc.initialize();
		filter = SPC_Filter();
	}
	void waitUntilReady() {
		writePort(1, 0xFF);
		while (true) {
			snes_spc.skip(2);
			if (readPort(1) == 0) {
				return;
			}
		}
	}
	void playSong(ubyte[] buffer, ubyte track) {
		initialized = false;
		snes_spc.load_buffer(buffer, 0x500);
		snes_spc.clear_echo();
		filter.clear();
		waitUntilReady();
		writePort(0, track);
		initialized = true;
	}
	void writePort(uint id, ubyte value) {
		snes_spc.write_port_now(id, value);
	}
	ubyte readPort(uint id) {
		return cast(ubyte)snes_spc.read_port_now(id);
	}
	void fillBuffer(short[] buffer) {
		// Play into buffer
		snes_spc.play(buffer);

		// Filter samples
		filter.run(buffer);
	}
}

struct AllSPC {
	NSPCPlayer nspcPlayer;
	Song[] loadedSongs;
	bool initialized;
	void changeSong(ubyte track) {
		initialized = false;
		nspcPlayer.loadSong(loadedSongs[track]);
		nspcPlayer.initialize();
		nspcPlayer.play();
		initialized = true;
	}
	void stop() {
		nspcPlayer.stop();
	}
	void loadSong(const(ubyte)[] data) {
		loadedSongs ~= loadNSPCFile(data);
	}
}
void audioCallback(void* user, ubyte[] stream) {
	audioCallback(*cast(AllSPC*)user, stream);
}
void audioCallback(ref AllSPC spc700, ubyte[] stream) {
	if (spc700.initialized) {
		spc700.nspcPlayer.fillBuffer(cast(short[2][])stream);
	}
}

ubyte[65536] loadNSPCBuffer(scope const ubyte[] file) @safe {
	import std.bitmanip : read;
	ubyte[65536] buffer;
	const remaining = loadAllSubpacks(buffer[], file[NSPCFileHeader.sizeof .. $]);
	return buffer;
}

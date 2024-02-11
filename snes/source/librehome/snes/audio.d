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
	void load(ubyte[] buffer, ushort start) {
		initialized = false;
		snes_spc.load_buffer(buffer, start);
		snes_spc.clear_echo();
		filter.clear();
		waitUntilReady();
		initialized = true;
	}
	void writePort(uint id, ubyte value) {
		snes_spc.write_port_now(id, value);
	}
	ubyte readPort(uint id) {
		return cast(ubyte)snes_spc.read_port_now(id);
	}
	void fillBuffer(short[] buffer) {
		if (!initialized) {
			return;
		}
		// Play into buffer
		snes_spc.play(buffer);

		// Filter samples
		filter.run(buffer);
	}
}

struct NSPC {
	NSPCPlayer player;
	Song[] loadedSongs;
	bool initialized;
	void changeSong(ubyte track) {
		initialized = false;
		player.loadSong(loadedSongs[track]);
		player.initialize();
		player.play();
		initialized = true;
	}
	void stop() {
		player.stop();
	}
	void loadSong(const(ubyte)[] data) {
		loadedSongs ~= loadNSPCFile(data);
	}
	void callback(ubyte[] stream) {
		if (initialized) {
			player.fillBuffer(cast(short[2][])stream);
		}
	}
}
void spc700Callback(void* user, ubyte[] stream) {
	(*cast(SPC700Emulated*)user).fillBuffer(cast(short[])stream);
}

ubyte[65536] loadNSPCBuffer(scope const ubyte[] file) @safe {
	import std.bitmanip : read;
	ubyte[65536] buffer;
	const remaining = loadAllSubpacks(buffer[], file[NSPCFileHeader.sizeof .. $]);
	return buffer;
}

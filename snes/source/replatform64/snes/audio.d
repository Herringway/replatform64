module replatform64.snes.audio;

import replatform64.backend.common;
import replatform64.common;

import spc700;
import nspcplay;

alias HLEWriteCallback = void delegate(ubyte port, ubyte value, AudioBackend backend);
alias HLEReadCallback = ubyte delegate(ubyte port);

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
	void loadNSPC(const(ubyte)[] data) {
		songs ~= loadNSPCBuffer(data);
	}
}

struct NSPC {
	NSPCPlayer player;
	Song[] loadedSongs;
	bool initialized;
	void delegate(scope ref NSPC nspc, ubyte port, ubyte value, AudioBackend backend) writePortCallback;
	ubyte delegate(scope ref NSPC nspc, ubyte port) readPortCallback;
	AudioBackend backend;
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
	void loadWAV(const ubyte[] data) {
		assert(backend, "No backend loaded");
		backend.loadWAV(data);
	}
	static void callback(NSPC* user, ubyte[] stream) {
		if (user.initialized) {
			user.player.fillBuffer(cast(short[2][])stream);
		}
	}
	void writeCallback(ubyte port, ubyte value, AudioBackend backend) {
		if (writePortCallback !is null) {
			writePortCallback(this, port, value, backend);
		}
	}
	ubyte readCallback(ubyte port) {
		if (readPortCallback !is null) {
			return readPortCallback(this, port);
		}
		return 0;
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

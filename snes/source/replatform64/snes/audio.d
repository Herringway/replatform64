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
	ubyte[65536][] songs;
	bool initialized;
	void delegate(scope ref SPC700Emulated spc, ubyte port, ubyte value) writePortCallback;
	ubyte delegate(scope ref SPC700Emulated spc, ubyte port) readPortCallback;
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
	void writePort(ubyte id, ubyte value) {
		snes_spc.write_port_now(id, value);
	}
	void writeCallback(ubyte id, ubyte value, AudioBackend) {
		if (writePortCallback) {
			writePortCallback(this, id, value);
		} else {
			writePort(id, value);
		}
	}
	ubyte readPort(ubyte id) {
		return cast(ubyte)snes_spc.read_port_now(id);
	}
	ubyte readCallback(ubyte id) {
		if (readPortCallback) {
			return readPortCallback(this, id);
		} else {
			return readPort(id);
		}
	}
	static void callback(SPC700Emulated* user, ubyte[] buffer) {
		user.callback(cast(short[])buffer);
	}
	void callback(short[] buffer) {
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
	bool initialized;
	void delegate(scope ref NSPC nspc, ubyte port, ubyte value, AudioBackend backend) writePortCallback;
	ubyte delegate(scope ref NSPC nspc, ubyte port) readPortCallback;
	AudioBackend backend;
	void changeSong(const Song track) {
		initialized = false;
		player.loadSong(track);
		player.initialize();
		player.play();
		initialized = true;
	}
	void stop() {
		player.stop();
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

ubyte[65536] loadNSPCBuffer(scope const ubyte[] file) @safe {
	import std.bitmanip : read;
	ubyte[65536] buffer;
	const remaining = loadAllSubpacks(buffer[], file[NSPCFileHeader.sizeof .. $]);
	return buffer;
}

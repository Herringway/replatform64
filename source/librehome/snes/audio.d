module librehome.snes.audio;

import librehome.backend.common;
import librehome.snes.common;

import spc700;

struct AllSPC {
	SNES_SPC snes_spc;
	SPC_Filter filter;
}
void output(void* data, ubyte[] buffer) nothrow {
	auto spc = cast(AllSPC*)data;
	if (inited) {
		// Play into buffer
		spc.snes_spc.play(cast(short[])buffer);

		// Filter samples
		spc.filter.run(cast(short[])buffer);
	}
}
__gshared bool inited;
__gshared AllSPC spc;
struct SPCPlayer {
	ubyte[0x10000] spcBuffer;
	AudioBackend backend;
	void initialize(AudioBackend backend) {
		this.backend = backend;
		spc.snes_spc.initialize();
		spc.filter = SPC_Filter();
		this.backend.initialize(&spc, &output, 32000, 2);
	}
	void load(ushort addr, scope const(ubyte)[] data) {
		wrappedLoad(spcBuffer[], data, addr);
	}
	void start(ushort entryPoint) {
		spc.snes_spc.load_buffer(spcBuffer[], entryPoint);
		spc.snes_spc.clear_echo();
		spc.filter.clear();
		spc.snes_spc.write_port_now(1, 0xFF);
		while (true) {
			spc.snes_spc.skip(2);
			if (spc.snes_spc.read_port_now(1) == 0) {
				spc.snes_spc.write_port_now(0, 0x94);
				break;
			}
		}
		inited = true;
	}
}

unittest {
	import librehome.backend.sdl2;
	auto newBackend = new SDL2Platform;
	newBackend.initialize();
	SPCPlayer player;
	player.initialize(newBackend.audio);
	player.load(0, (cast(immutable(ubyte)[])import("test.spc"))[0x100 .. 0x10100]);
	player.start(0x500);
	while(true) {}
}

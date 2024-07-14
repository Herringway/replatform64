module replatform64.snes.dma;

import replatform64.snes.hardware;
import replatform64.snes.rendering;

import std.experimental.logger;

void dmaCopy(const(ubyte)* src, ubyte* dst, ubyte* wrapAt, ubyte* wrapTo, int count, int transferSize, int srcAdjust, int dstAdjust) pure {
	if(count == 0) count = 0x10000;
	for(int i = 0; i < count;) {
		for(int j = 0; i < count && j < transferSize; i += 1, j += 1) {
			if (dst >= wrapAt) dst = wrapTo;
			*dst = *src;
			src++;
			dst++;
		}
		src += srcAdjust;
		dst += dstAdjust;
	}
}

unittest {
	import std.meta : aliasSeqOf;
	import std.range : iota;
	ubyte[100] testBuffer;
	immutable ubyte[100] testSource = [aliasSeqOf!(iota(0, 100))];
	dmaCopy(&testSource[0], &testBuffer[0], &testBuffer[2], &testBuffer[0], 4, 2, 0, 0);
	assert(testBuffer[0 .. 2] == [2, 3]);
}

void handleOAMDMA(ref SNESRenderer renderer, ubyte dmap, ubyte bbad, const(void)* a1t, ushort das, ushort oamaddr) pure {
	assert((dmap & 0x80) == 0); // Can't go from B bus to A bus
	assert((dmap & 0x10) == 0); // Can't decrement pointer
	assert((dmap & 0x07) == 0);
	ubyte* dest, wrapAt, wrapTo;
	int transferSize = 1, srcAdjust = 0, dstAdjust = 0;

	wrapTo = cast(ubyte *)(&renderer.oam1[0]);
	dest = wrapTo + (oamaddr << 1);
	wrapAt = wrapTo + 0x220;

	// If the "Fixed Transfer" bit is set, transfer same data repeatedly
	if ((dmap & 0x08) != 0) srcAdjust = -transferSize;
	// Perform actual copy
	dmaCopy(cast(const(ubyte)*)a1t, dest, wrapAt, wrapTo, das, transferSize, srcAdjust, dstAdjust);
}
void handleCGRAMDMA(ref SNESRenderer renderer, ubyte dmap, ubyte bbad, const(void)* a1t, ushort das, ushort cgadd) pure {
	assert((dmap & 0x80) == 0); // Can't go from B bus to A bus
	assert((dmap & 0x10) == 0); // Can't decrement pointer
	assert((dmap & 0x07) == 0);
	ubyte* dest, wrapAt, wrapTo;
	int transferSize = 1, srcAdjust = 0, dstAdjust = 0;
	// Dest is CGRAM
	wrapTo = cast(ubyte *)(&renderer.cgram[0]);
	dest = wrapTo + (cgadd << 1);
	wrapAt = wrapTo + 0x200;

	// If the "Fixed Transfer" bit is set, transfer same data repeatedly
	if ((dmap & 0x08) != 0) srcAdjust = -transferSize;
	// Perform actual copy
	dmaCopy(cast(const(ubyte)*)a1t, dest, wrapAt, wrapTo, das, transferSize, srcAdjust, dstAdjust);
}
void handleVRAMDMA(ref SNESRenderer renderer, ubyte dmap, ubyte bbad, const(void)* a1t, ushort das, ushort vmaddr, ubyte vmain) pure {
	assert((dmap & 0x80) == 0); // Can't go from B bus to A bus
	assert((dmap & 0x10) == 0); // Can't decrement pointer
	ubyte* dest, wrapAt, wrapTo;
	int transferSize = 1, srcAdjust = 0, dstAdjust = 0;
	// Dest is VRAM
	auto hibyte = bbad == 0x19;
	// Ensure we're only doing single byte to $2119
	assert(!hibyte || (dmap & 0x07) == 0);
	// Set transfer size
	// Ensure we're either copying one or two bytes
	assert((dmap & 0x07) <= 1);
	if ((dmap & 0x07) == 1) {
		transferSize = 2;
		dstAdjust = 0;
	} else {
		transferSize = 1;
		dstAdjust = 1; // skip byte when copying
	}
	// Handle VMAIN
	auto addrIncrementAmount = [1, 32, 128, 256][vmain & 0x03];
	// Skip ahead by addrIncrementAmount words, less the word we just
	// dealt with by setting transferSize and dstAdjust.
	dstAdjust += (addrIncrementAmount - 1) * 2;
	// Address mapping is not implemented.
	assert((vmain & 0x0C) == 0);
	// Address increment is only supported for the used cases:
	// - writing word value and increment after writing $2119
	// - writing byte to $2119 and increment after writing $2119
	// - writing byte to $2118 and increment after writing $2118
	assert((vmain & 0x80) || (!hibyte && transferSize == 1));
	wrapTo = cast(ubyte *)(&renderer.vram[0]);
	dest = wrapTo + ((vmaddr << 1) + (hibyte ? 1 : 0));
	wrapAt = wrapTo + 0x10000;
	// If the "Fixed Transfer" bit is set, transfer same data repeatedly
	if ((dmap & 0x08) != 0) srcAdjust = -transferSize;
	// Perform actual copy
	dmaCopy(cast(const(ubyte)*)a1t, dest, wrapAt, wrapTo, das, transferSize, srcAdjust, dstAdjust);
}

unittest {
	import replatform64.backend.nullbackend : NullVideo;
	import std.meta : aliasSeqOf;
	import std.range : iota;
	SNESRenderer renderer;
	renderer.initialize("", new NullVideo, RendererSettings(engine: Renderer.neo));
	immutable ubyte[100] testSource = [aliasSeqOf!(iota(0, 100))];
	handleVRAMDMA(renderer, 0x01, 0x18, &testSource[0], 100, 0, 0x80);
	assert(renderer.vram[0 .. 100] == testSource);
	immutable ubyte[2] testFixedHigh = [0x30, 0];
	handleVRAMDMA(renderer, 0x08, 0x19, &testFixedHigh[0], 0x400, 0x5800, 0x80);
	assert(renderer.vram[0 .. 100] == testSource);
	assert(renderer.vram[0xB001] == 0x30);
}

void handleHDMA(ref SNESRenderer renderer, ubyte hdmaChannelsEnabled, DMAChannel[] dmaChannels) pure {
	import std.algorithm.sorting : sort;
	import std.algorithm.mutation : SwapStrategy;
	renderer.numHDMA = 0;
	auto channels = hdmaChannelsEnabled;
	for(auto i = 0; i < 8; i += 1) {
		if (((channels >> i) & 1) == 0) continue;
		queueHDMA(dmaChannels[i], renderer.hdmaData[renderer.numHDMA .. $], renderer.numHDMA);
	}
	auto writes = renderer.hdmaData[0 .. renderer.numHDMA];
	// Stable sorting is required - when there are back-to-back writes to
	// the same register, they may need to be completed in the correct order.
	// Example: when writing the scroll registers by HDMA, writing (0x80, 0x00)
	// is completely different than writing (0x00, 0x80)
	sort!((x,y) => x.vcounter < y.vcounter, SwapStrategy.stable)(writes);
	if (writes.length > 0) {
		debug(printHDMA) tracef("Transfer: %s", writes);
	}
}

void queueHDMA(const DMAChannel channel, scope HDMAWrite[] buffer, ref ushort numHDMAWrites) pure {
	static void readTable(const(ubyte)* data, ubyte mode, ubyte lines, ubyte lineBase, ubyte baseAddr, bool always, HDMAWrite[] buffer, out size_t count) {
		ubyte numBytes;
		bool shortSized;
		switch (mode) {
			case 0b000:
				numBytes = 1;
				shortSized = false;
				break;
			case 0b001:
				numBytes = 2;
				shortSized = false;
				break;
			case 0b010:
				numBytes = 2;
				shortSized = true;
				break;
			case 0b011:
				numBytes = 4;
				shortSized = true;
				break;
			case 0b100:
				numBytes = 4;
				shortSized = false;
				break;
			case 0b101:
			case 0b110:
			case 0b111:
			default:
				assert(0, "Invalid DMA mode");
		}
		auto lineChunk = data[0 .. numBytes];
		ushort line = 1;
		do {
			foreach (o; 0 .. numBytes) {
				const addr = cast(ubyte)(baseAddr + o / (1 + shortSized));
				buffer[0] = HDMAWrite(cast(ushort)(lineBase + line - 1), addr, lineChunk[o]);
				buffer = buffer[1 .. $];
			}
			if (always && (line < lines)) {
				lineChunk = data[line * numBytes .. (line + 1) * numBytes];
			}
		} while (always && ++line <= lines); //always bit means value is written EVERY line
		count = (line - always) * numBytes;
	}
	const dmap = channel.DMAP;
	const indirect = !!(dmap & 0b01000000);
	const mode = (dmap & 0b00000111);
	const fixedTransfer = !!(dmap&0b00001000);
	const decrement = !!(dmap&0b00010000);
	assert(!fixedTransfer && !decrement, "fixed transfers and decrement are unimplemented");
	ubyte lineBase = 0;
	ubyte dest = channel.BBAD;
	ubyte increment = 1;
	if (!indirect) {
		auto data = cast(const(ubyte)*)channel.A1T;
		while (data[0] != 0) {
			const lines = (data[0] == 0x80) ? 128 : (data[0] & 0x7F);
			const always = !!(data[0] & 0x80);
			size_t offset;
			readTable(data + 1, mode, lines, lineBase, dest, always, buffer[numHDMAWrites .. $], offset);
			numHDMAWrites += offset;
			data += offset + 1;
			lineBase += lines;
		}
	} else {
		auto data = cast(const(HDMAIndirectTableEntry)*)channel.A1T;
		while (data[0].lines != 0) {
			const lines = (data[0].lines == 0x80) ? 128 : (data[0].lines & 0x7F);
			const always = !!(data[0].lines & 0x80);
			auto addr = data[0].address;
			size_t offset;
			// Indirect tables always auto-increment when always bit is set? Should figure out if this is controlled by something
			readTable(addr, mode, lines, lineBase, dest, always, buffer[numHDMAWrites .. $], offset);
			numHDMAWrites += offset;
			lineBase += lines;
			data++;
		}
	}
	debug(printHDMA) tracef("Performing HDMA (mode: %s, indirect: %s, dest: %04X, fixed: %s, dec: %s)", mode, indirect, channel.BBAD + 0x2100, fixedTransfer, decrement);
}

unittest {
	static ushort[448] hdmaBuffer;
	ushort writes;
	HDMAWrite[4 * 8 * 240] buf;
	const hdmaIndirect = [
		HDMAIndirectTableEntry(0xE4, cast(const(ubyte)*)&hdmaBuffer[0]),
		HDMAIndirectTableEntry(0xFC, cast(const(ubyte)*)&hdmaBuffer[100]),
		HDMAIndirectTableEntry(0x00),
	];
	DMAChannel channel;
	{ // basic HDMA test, letterboxing
		HDMAWordTransfer[4] letterboxTest;

		letterboxTest[0].scanlines = 67;
		letterboxTest[0].value = 0x15;
		letterboxTest[1].scanlines = 89;
		letterboxTest[1].value = 0x17;
		letterboxTest[2].scanlines = 1;
		letterboxTest[2].value = 0x15;
		letterboxTest[3].scanlines = 0;

		channel.BBAD = 0x2C;
		channel.DMAP = DMATransferUnit.Word;
		channel.A1T = &letterboxTest[0];
		queueHDMA(channel, buf, writes);
		assert(writes == 6);
		with(buf[0]) {
			assert(vcounter == 0);
			assert(addr == 0x2C);
			assert(value == 0x15);
		}
		with(buf[1]) {
			assert(vcounter == 0);
			assert(addr == 0x2D);
			assert(value == 0x00);
		}
		with(buf[2]) {
			assert(vcounter == 67);
			assert(addr == 0x2C);
			assert(value == 0x17);
		}
		with(buf[3]) {
			assert(vcounter == 67);
			assert(addr == 0x2D);
			assert(value == 0x00);
		}
		with(buf[4]) {
			assert(vcounter == 156);
			assert(addr == 0x2C);
			assert(value == 0x15);
		}
		with(buf[5]) {
			assert(vcounter == 156);
			assert(addr == 0x2D);
			assert(value == 0x00);
		}
	}
	{ //swirls
		buf = buf.init;
		writes = 0;
		static immutable ubyte[] bytes = [0x37, 0xFF, 0x00, 0xFF, 0x00, 0xB0, 0x85, 0x97, 0xFF, 0x00, 0x7D, 0x9D, 0xFF, 0x00, 0x77, 0xA2, 0xFF, 0x00, 0x74, 0xA6, 0xFF, 0x00, 0x71, 0xA9, 0xFF, 0x00, 0x6F, 0xAB, 0xFF, 0x00, 0x6C, 0xAD, 0xFF, 0x00, 0x6A, 0xAF, 0xFF, 0x00, 0x68, 0xB1, 0xFF, 0x00, 0x67, 0xB3, 0xFF, 0x00, 0x65, 0xB5, 0xFF, 0x00, 0x63, 0xB6, 0xFF, 0x00, 0x62, 0xB8, 0xFF, 0x00, 0x60, 0xB9, 0xFF, 0x00, 0x5F, 0xBA, 0xFF, 0x00, 0x5D, 0xBC, 0xFF, 0x00, 0x5C, 0xBD, 0xFF, 0x00, 0x5B, 0x9D, 0x9F, 0xBE, 0x5A, 0x9D, 0xA2, 0xBF, 0x58, 0x9C, 0xA5, 0xC0, 0x57, 0x9C, 0xA7, 0xC1, 0x56, 0x9B, 0xA9, 0xC2, 0x55, 0x9B, 0xAB, 0xC3, 0x54, 0x9A, 0xAD, 0xC4, 0x53, 0x9A, 0xAE, 0xC4, 0x52, 0x9C, 0xB0, 0xC5, 0x52, 0x9F, 0xB1, 0xC6, 0x51, 0xA1, 0xB2, 0xC6, 0x50, 0xA3, 0xB3, 0xC7, 0x4F, 0xA5, 0xB4, 0xC8, 0x4E, 0xA6, 0xB5, 0xC8, 0x4E, 0xA8, 0xB6, 0xC9, 0x4D, 0xA9, 0xB7, 0xC9, 0x4D, 0xAA, 0xB8, 0xCA, 0x4C, 0xAC, 0xB9, 0xCA, 0x4C, 0xAD, 0xB9, 0xCB, 0x4B, 0xAE, 0xBA, 0xCB, 0x4B, 0xAF, 0xBB, 0xCC, 0x4A, 0xB0, 0xBB, 0xCC, 0x4A, 0xB0, 0xBC, 0xCD, 0x4A, 0xB1, 0xBC, 0xCD, 0x49, 0xB2, 0xBD, 0xCE, 0x49, 0xB3, 0xBD, 0xCE, 0x49, 0xB3, 0xBE, 0xCE, 0x49, 0xB4, 0xBE, 0xCF, 0x49, 0xB4, 0xBF, 0xCF, 0x48, 0xB5, 0xBF, 0xCF, 0x48, 0xB5, 0xBF, 0xD0, 0x03, 0x48, 0xB6, 0xC0, 0xD0, 0x02, 0x48, 0xB7, 0xC0, 0xD1, 0x03, 0x48, 0xB7, 0xC1, 0xD1, 0x03, 0x48, 0xB8, 0xC1, 0xD2, 0x04, 0x49, 0xB8, 0xC1, 0xD2, 0x02, 0x4A, 0xB8, 0xC1, 0xD2, 0x01, 0x4A, 0xB7, 0xC0, 0xD2, 0x02, 0x4B, 0xB7, 0xC0, 0xD2, 0x02, 0x4C, 0xB7, 0xC0, 0xD1, 0x02, 0x4D, 0xB6, 0xBF, 0xD1, 0x9F, 0x4E, 0xB6, 0xBF, 0xD1, 0x4E, 0xB5, 0xBE, 0xD1, 0x4F, 0xB5, 0xBE, 0xD0, 0x50, 0xB4, 0xBE, 0xD0, 0x51, 0xB4, 0xBD, 0xD0, 0x51, 0xB3, 0xBD, 0xCF, 0x52, 0xB3, 0xBD, 0xCF, 0x53, 0xB2, 0xBC, 0xCF, 0x54, 0xB1, 0xBC, 0xCE, 0x55, 0xB1, 0xBB, 0xCE, 0x56, 0xB0, 0xBB, 0xCE, 0x57, 0xAF, 0xBA, 0xCD, 0x58, 0xAE, 0xB9, 0xCD, 0x59, 0xAD, 0xB9, 0xCC, 0x5A, 0xAC, 0xBA, 0xCC, 0x5B, 0xAB, 0xBB, 0xCB, 0x5D, 0xAA, 0xBC, 0xCB, 0x5E, 0xA9, 0xBD, 0xCA, 0x5F, 0xA8, 0xBE, 0xC9, 0x61, 0xA7, 0xBF, 0xC9, 0x62, 0xA5, 0xC0, 0xC8, 0x64, 0xA4, 0xC1, 0xC7, 0x66, 0xA3, 0xC2, 0xC7, 0x68, 0xA1, 0xC3, 0xC6, 0x6A, 0x9F, 0xC4, 0xC5, 0x6C, 0x9D, 0xFF, 0x00, 0x6E, 0x9B, 0xFF, 0x00, 0x71, 0x99, 0xFF, 0x00, 0x74, 0x96, 0xFF, 0x00, 0x78, 0x91, 0xFF, 0x00, 0x7E, 0x8B, 0xFF, 0x00, 0x42, 0xFF, 0x00, 0xFF, 0x00, 0x00];
		channel.BBAD = 0x26;
		channel.DMAP = 0x04;
		channel.A1T = &bytes[0];
		queueHDMA(channel, buf, writes);
		assert(writes == 364);
		with (buf[0]) {
			assert(vcounter == 0);
			assert(addr == 0x26);
			assert(value == 0xFF);
		}
		with (buf[1]) {
			assert(vcounter == 0);
			assert(addr == 0x27);
			assert(value == 0x00);
		}
		with (buf[2]) {
			assert(vcounter == 0);
			assert(addr == 0x28);
			assert(value == 0xFF);
		}
		with (buf[3]) {
			assert(vcounter == 0);
			assert(addr == 0x29);
			assert(value == 0x00);
		}
		with (buf[4]) {
			assert(vcounter == 55);
			assert(addr == 0x26);
			assert(value == 0x85);
		}
		with (buf[5]) {
			assert(vcounter == 55);
			assert(addr == 0x27);
			assert(value == 0x97);
		}
		with (buf[8]) {
			assert(vcounter == 56);
			assert(addr == 0x26);
			assert(value == 0x7D);
		}
		with (buf[9]) {
			assert(vcounter == 56);
			assert(addr == 0x27);
			assert(value == 0x9D);
		}
	}
	{ // battle background sample
		buf = buf.init;
		writes = 0;
		hdmaBuffer = [0x0055, 0x0054, 0x0053, 0x0052, 0x0051, 0x0050, 0x004F, 0x004E, 0x004D, 0x004B, 0x004A, 0x0049, 0x0048, 0x0047, 0x0046, 0x0045, 0x0044, 0x0043, 0x0042, 0x0041, 0x0040, 0x0040, 0x003F, 0x003E, 0x003E, 0x003D, 0x003D, 0x003D, 0x003D, 0x003D, 0x003D, 0x003D, 0x003D, 0x003D, 0x003E, 0x003E, 0x003F, 0x003F, 0x0040, 0x0041, 0x0041, 0x0042, 0x0043, 0x0044, 0x0045, 0x0046, 0x0047, 0x0048, 0x004A, 0x004B, 0x004C, 0x004D, 0x004E, 0x004F, 0x0050, 0x0052, 0x0053, 0x0054, 0x0055, 0x0056, 0x0057, 0x0058, 0x0058, 0x0059, 0x005A, 0x005A, 0x005B, 0x005B, 0x005C, 0x005C, 0x005C, 0x005C, 0x005C, 0x005C, 0x005C, 0x005C, 0x005C, 0x005B, 0x005B, 0x005A, 0x005A, 0x0059, 0x0058, 0x0058, 0x0057, 0x0056, 0x0055, 0x0054, 0x0053, 0x0052, 0x0050, 0x004F, 0x004E, 0x004D, 0x004C, 0x004B, 0x004A, 0x0048, 0x0047, 0x0046, 0x0045, 0x0044, 0x0043, 0x0042, 0x0041, 0x0041, 0x0040, 0x003F, 0x003F, 0x003E, 0x003E, 0x003D, 0x003D, 0x003D, 0x003D, 0x003D, 0x003D, 0x003D, 0x003D, 0x003D, 0x003E, 0x003E, 0x003F, 0x0040, 0x0040, 0x0041, 0x0042, 0x0043, 0x0044, 0x0045, 0x0046, 0x0047, 0x0048, 0x0049, 0x004A, 0x004B, 0x004D, 0x004E, 0x004F, 0x0050, 0x0051, 0x0052, 0x0053, 0x0054, 0x0055, 0x0056, 0x0057, 0x0058, 0x0059, 0x005A, 0x005A, 0x005B, 0x005B, 0x005C, 0x005C, 0x005C, 0x005C, 0x005C, 0x005C, 0x005C, 0x005C, 0x005C, 0x005C, 0x005B, 0x005B, 0x005A, 0x0059, 0x0059, 0x0058, 0x0057, 0x0056, 0x0055, 0x0054, 0x0053, 0x0052, 0x0051, 0x0050, 0x004E, 0x004D, 0x004C, 0x004B, 0x004A, 0x0049, 0x0048, 0x0047, 0x0045, 0x0044, 0x0043, 0x0042, 0x0042, 0x0041, 0x0040, 0x003F, 0x003F, 0x003E, 0x003E, 0x003D, 0x003D, 0x003D, 0x003D, 0x003D, 0x003D, 0x003D, 0x003D, 0x003D, 0x003E, 0x003E, 0x003F, 0x003F, 0x0040, 0x0041, 0x0042, 0x0042, 0x0043, 0x0044, 0x0045, 0x0047, 0x0048, 0x0049, 0x004A, 0x004B, 0x004C, 0x004D, 0x004E, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7, 0x00B9, 0x00BA, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x00BF, 0x00C0, 0x00C1, 0x00C2, 0x00C2, 0x00C3, 0x00C4, 0x00C4, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C4, 0x00C4, 0x00C3, 0x00C3, 0x00C2, 0x00C1, 0x00C0, 0x00BF, 0x00BE, 0x00BD, 0x00BC, 0x00BB, 0x00BA, 0x00B9, 0x00B8, 0x00B7, 0x00B6, 0x00B4, 0x00B3, 0x00B2, 0x00B1, 0x00B0, 0x00AF, 0x00AE, 0x00AD, 0x00AC, 0x00AB, 0x00AA, 0x00A9, 0x00A9, 0x00A8, 0x00A7, 0x00A7, 0x00A6, 0x00A6, 0x00A6, 0x00A6, 0x00A6, 0x00A6, 0x00A6, 0x00A6, 0x00A6, 0x00A7, 0x00A7, 0x00A8, 0x00A8, 0x00A9, 0x00AA, 0x00AA, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF, 0x00B0, 0x00B1, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7, 0x00B8, 0x00B9, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x00BF, 0x00C0, 0x00C1, 0x00C1, 0x00C2, 0x00C3, 0x00C3, 0x00C4, 0x00C4, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C4, 0x00C4, 0x00C3, 0x00C3, 0x00C2, 0x00C1, 0x00C1, 0x00C0, 0x00BF, 0x00BE, 0x00BD, 0x00BC, 0x00BB, 0x00B9, 0x00B8, 0x00B7, 0x00B6, 0x00B5, 0x00B4, 0x00B3, 0x00B1, 0x00B0, 0x00AF, 0x00AE, 0x00AD, 0x00AC, 0x00AB, 0x00AA, 0x00AA, 0x00A9, 0x00A8, 0x00A8, 0x00A7, 0x00A7, 0x00A6, 0x00A6, 0x00A6, 0x00A6, 0x00A6, 0x00A6, 0x00A6, 0x00A6, 0x00A6, 0x00A7, 0x00A7, 0x00A8, 0x00A9, 0x00A9, 0x00AA, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF, 0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B6, 0x00B7, 0x00B8, 0x00B9, 0x00BA, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x00BF, 0x00C0, 0x00C1, 0x00C2, 0x00C3, 0x00C3, 0x00C4, 0x00C4, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C5, 0x00C4, 0x00C4, 0x00C3, 0x00C2, 0x00C2, 0x00C1, 0x00C0, 0x00BF, 0x00BE, 0x00BD, 0x00BC, 0x00BB, 0x00BA, 0x00B9, 0x00B7, 0x00B6, 0x00B5, 0x00B4, 0x00B3, 0x00B2, 0x00B1, 0x00B0, 0x00AE, 0x00AD];
		channel.BBAD = 0x0F;
		channel.DMAP = 0x42;
		channel.A1T = &hdmaIndirect[0];
		queueHDMA(channel, buf, writes);
		assert(writes == 448);
		with (buf[0]) {
			assert(vcounter == 0);
			assert(addr == 0x0F);
			assert(value == 0x55);
		}
		with (buf[1]) {
			assert(vcounter == 0);
			assert(addr == 0x0F);
			assert(value == 0x00);
		}
		with (buf[2]) {
			assert(vcounter == 1);
			assert(addr == 0x0F);
			assert(value == 0x54);
		}
		with (buf[199]) {
			assert(vcounter == 99);
			assert(addr == 0x0F);
			assert(value == 0x00);
		}
		with (buf[200]) {
			assert(vcounter == 100);
			assert(addr == 0x0F);
			assert(value == 0x45);
		}
		with (buf[201]) {
			assert(vcounter == 100);
			assert(addr == 0x0F);
			assert(value == 0x00);
		}
	}
}

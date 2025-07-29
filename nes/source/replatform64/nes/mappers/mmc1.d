module replatform64.nes.mappers.mmc1;

import replatform64.nes.hardware.ppu;

import replatform64.ui;

enum MMC1Register {
	control = 0x8000,
	chrBank0 = 0xA000,
	chrBank1 = 0xC000,
	prgBank = 0xE000,
}
enum InternalRegister {
	control,
	chrBank0,
	chrBank1,
	prgBank,
}

enum NameTableMode {
	screenA,
	screenB,
	vertical,
	horizontal,
}

struct MMC1 {
	enum name = "MMC1";
	ubyte shiftValue;
	ubyte shiftWrites;
	NameTableMode nameTableArrangement;
	ubyte prgROMBankMode;
	ubyte chrROMBankMode;
	ubyte chrBank1;
	ubyte chrBank2;
	ubyte prgBank;
	void writeRegister(ushort address, ubyte value, ref PPU ppu) {
		// this uses 5-bit shift registers, with only one bit written at a time
		// address only matters on the fifth bit written
		const bool r = !!(value & (1 << 7));
		const bool d = !!(value & (1 << 0));
		shiftValue = (shiftValue >> 1) | (d << 4);
		if (++shiftWrites == 5) {
			writeRealRegister(cast(InternalRegister)((address & 0x7FFF) >> 13), shiftValue, ppu);
			shiftValue = 0;
			shiftWrites = 0;
		}
	}
	void writeRealRegister(InternalRegister register, ubyte value, ref PPU ppu) {
		final switch (register) {
			case InternalRegister.control:
				nameTableArrangement = cast(NameTableMode)(value & 0b00011);
				ppu.mirrorMode = [MirrorType.screenA, MirrorType.screenB, MirrorType.vertical, MirrorType.horizontal][nameTableArrangement];
				prgROMBankMode = (value & 0b01100) >> 2;
				chrROMBankMode = (value & 0b10000) >> 4;
				break;
			case InternalRegister.chrBank0:
				chrBank1 = value;
				break;
			case InternalRegister.chrBank1:
				chrBank2 = value;
				break;
			case InternalRegister.prgBank:
				prgBank = value;
				break;
		}
	}
	void debugUI(UIState state) {
		ImGui.SeparatorText("Bank Config");
		InputEditable("CHR Bank 1", chrBank1);
		InputEditable("CHR Bank 2", chrBank2);
		InputEditable("PRG Bank", prgBank);
		ImGui.SeparatorText("Name Table");
		InputEditable("Arrangement", nameTableArrangement);
		ImGui.SeparatorText("Shift Register State");
		InputEditable("Current value", shiftValue);
		InputEditable("Write count", shiftWrites);
	}
}

unittest {
	import replatform64.nes.hardware.ppu;
	PPU ppu;
	with(MMC1()) {
		writeRegister(0x8000, 1, ppu);
		writeRegister(0x8000, 0, ppu);
		writeRegister(0x8000, 0, ppu);
		writeRegister(0x8000, 1, ppu);
		writeRegister(0x8000, 1, ppu);
		assert(nameTableArrangement == NameTableMode.screenB);
		assert(ppu.mirrorMode == MirrorType.screenB);
		assert(prgROMBankMode == 2);
		assert(chrROMBankMode == 1);
	}
	with(MMC1()) {
		writeRegister(0xE000, 1, ppu);
		writeRegister(0xE000, 0, ppu);
		writeRegister(0xE000, 0, ppu);
		writeRegister(0xE000, 1, ppu);
		writeRegister(0x8000, 1, ppu);
		assert(nameTableArrangement == NameTableMode.screenB);
		assert(ppu.mirrorMode == MirrorType.screenB);
		assert(prgROMBankMode == 2);
		assert(chrROMBankMode == 1);
	}
	with(MMC1()) {
		writeRegister(0xE000, 1, ppu);
		writeRegister(0xE000, 0, ppu);
		writeRegister(0xE000, 0, ppu);
		writeRegister(0xE000, 1, ppu);
		writeRegister(0xE000, 1, ppu);
		assert(prgBank == 0b11001);
	}
	with(MMC1()) {
		writeRegister(0xA000, 1, ppu);
		writeRegister(0xA000, 0, ppu);
		writeRegister(0xA000, 0, ppu);
		writeRegister(0xA000, 1, ppu);
		writeRegister(0xA000, 1, ppu);
		assert(chrBank1 == 0b11001);
	}
	with(MMC1()) {
		writeRegister(0xC000, 1, ppu);
		writeRegister(0xC000, 0, ppu);
		writeRegister(0xC000, 0, ppu);
		writeRegister(0xC000, 1, ppu);
		writeRegister(0xC000, 1, ppu);
		assert(chrBank2 == 0b11001);
	}
}

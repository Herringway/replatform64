module replatform64.snes.platform;

import replatform64.assets;
import replatform64.backend.common;
import replatform64.commonplatform;
import replatform64.dumping;
import replatform64.registers;
import replatform64.snes.audio;
import replatform64.snes.dma;
import replatform64.snes.hardware;
import replatform64.snes.rendering;
import replatform64.ui;
import replatform64.util;

import std.algorithm.comparison;
import std.file;
import std.format;
import std.functional;
import std.logger;
import std.range;
import std.path;
import std.stdio;

struct Settings {
	RendererSettings renderer;
	bool debugging;
}

struct SNES {
	void function() entryPoint;
	void function() interruptHandlerVBlank;
	deprecated("Use interruptHandlerVBlank instead") alias interruptHandler = interruptHandlerVBlank;
	string title;
	SNESRenderer renderer;
	string matchingInternalID;
	APU apu;
	private Settings settings;
	private immutable(ubyte)[] originalData;
	private PlatformCommon platform;
	private ushort[2] pads;
	DMAChannel[8] dmaChannels; ///
	ubyte HDMAEN;
	ubyte HVBJOY;
	ubyte NMITIMEN;
	ubyte STAT78;
	private DebugFunction audioDebug;
	enum screenHeight = 224;
	enum screenWidth = 256;

	mixin PlatformCommonForwarders;

	void initialize(Backend backendType = Backend.autoSelect) {
		renderer.selectRenderer(backendType == Backend.none ? RendererSettings(engine: Renderer.neo) : settings.renderer);
		commonInitialization(renderer.getResolution(), { entryPoint(); }, backendType);
		renderer.initialize(title, platform.backend.video);
		platform.registerMemoryRange("VRAM", renderer.vram);
		platform.registerMemoryRange("OAM1", cast(ubyte[])renderer.oam1);
		platform.registerMemoryRange("OAM2", renderer.oam2);
	}
	void initializeAudio(APU apu) {
		this.apu = apu;
		apu.initialize(platform.backend.audio);
		platform.installAudioCallback(cast(void*)apu, &APU.audioCallback);
		if (apu.aram !is null) {
			platform.registerMemoryRange("ARAM", apu.aram);
		}
	}
	immutable(ubyte)[] romData() {
		if (!originalData && (gameID ~ ".sfc").exists) {
			originalData = (cast(ubyte[])read(gameID~".sfc")).idup;
			const result = detect(originalData, matchingInternalID);
			info("Loaded ", title, " ROM", result.header ? " (with header)" : "");
			if (result.header) {
				originalData = originalData[0x200 .. $];
			}
		}
		return originalData;
	}
	void handleHDMA() {
		.handleHDMA(renderer, HDMAEN, dmaChannels);
	}
	void handleOAMDMA(ubyte dmap, ubyte bbad, const(void)* a1t, ushort das, ushort oamaddr) pure {
		.handleOAMDMA(renderer.oamFull, dmap, bbad, a1t, das, oamaddr);
	}
	void handleCGRAMDMA(ubyte dmap, ubyte bbad, const(void)* a1t, ushort das, ushort cgadd) pure {
		.handleCGRAMDMA(cast(ubyte[])renderer.cgram, dmap, bbad, a1t, das, cgadd);
	}
	void handleVRAMDMA(ubyte dmap, ubyte bbad, const(void)* a1t, ushort das, ushort vmaddr, ubyte vmain) pure {
		.handleVRAMDMA(renderer.vram, dmap, bbad, a1t, das, vmaddr, vmain);
	}
	void handleOAMDMA(ubyte dmap, ubyte bbad, const(ubyte)[] a1t, ushort das, ushort oamaddr) @safe pure {
		.handleOAMDMA(renderer.oamFull, dmap, bbad, a1t, das, oamaddr);
	}
	void handleCGRAMDMA(ubyte dmap, ubyte bbad, const(ubyte)[] a1t, ushort das, ushort cgadd) @safe pure {
		.handleCGRAMDMA(cast(ubyte[])renderer.cgram, dmap, bbad, a1t, das, cgadd);
	}
	void handleVRAMDMA(ubyte dmap, ubyte bbad, const(ubyte)[] a1t, ushort das, ushort vmaddr, ubyte vmain) @safe pure {
		.handleVRAMDMA(renderer.vram, dmap, bbad, a1t, das, vmaddr, vmain);
	}
	private void copyInputState(InputState state) @safe pure {
		pads = 0;
		foreach (idx, ref pad; pads) {
			if (platform.inputState.controllers[idx] & ControllerMask.y) { pad |= Pad.y; }
			if (platform.inputState.controllers[idx] & ControllerMask.b) { pad |= Pad.b; }
			if (platform.inputState.controllers[idx] & ControllerMask.x) { pad |= Pad.x; }
			if (platform.inputState.controllers[idx] & ControllerMask.a) { pad |= Pad.a; }
			if (platform.inputState.controllers[idx] & ControllerMask.r) { pad |= Pad.r; }
			if (platform.inputState.controllers[idx] & ControllerMask.l) { pad |= Pad.l; }
			if (platform.inputState.controllers[idx] & ControllerMask.start) { pad |= Pad.start; }
			if (platform.inputState.controllers[idx] & ControllerMask.select) { pad |= Pad.select; }
			if (platform.inputState.controllers[idx] & ControllerMask.up) { pad |= Pad.up; }
			if (platform.inputState.controllers[idx] & ControllerMask.down) { pad |= Pad.down; }
			if (platform.inputState.controllers[idx] & ControllerMask.left) { pad |= Pad.left; }
			if (platform.inputState.controllers[idx] & ControllerMask.right) { pad |= Pad.right; }
			if (platform.inputState.controllers[idx] & ControllerMask.extra1) { pad |= Pad.extra1; }
			if (platform.inputState.controllers[idx] & ControllerMask.extra2) { pad |= Pad.extra2; }
			if (platform.inputState.controllers[idx] & ControllerMask.extra3) { pad |= Pad.extra3; }
			if (platform.inputState.controllers[idx] & ControllerMask.extra4) { pad |= Pad.extra4; }
		}
	}
	ushort getControllerState(ubyte playerID) const @safe pure {
		return pads[playerID];
	}
	ubyte readRegister(ushort addr) {
		if ((addr >= Register.INIDISP) && (addr <= Register.STAT78)) {
			return renderer.readRegister(addr);
		} else if ((addr >= Register.APUIO0) && (addr <= Register.APUIO3)) {
			return apu.readRegister(addr);
		} else {
			assert(0, "Unsupported read");
		}
	}
	void writeRegisterPlatform(ushort addr, ubyte value) {
		if ((addr >= Register.INIDISP) && (addr <= Register.STAT78)) {
			renderer.writeRegister(addr, value);
		} else if ((addr >= Register.APUIO0) && (addr <= Register.APUIO3)) {
			apu.writeRegister(addr, value);
		} else {
			assert(0, "Unsupported write");
		}
	}
	void dumpExtraDebugData(string crashDir) {
		dumpVRAMToDir(crashDir);
	}
	void dumpVRAMToDir(string dir) {
		File(buildPath(dir, "gfxstate.regs"), "wb").rawWrite(renderer.registers);
		File(buildPath(dir, "gfxstate.vram"), "wb").rawWrite(renderer.vram);
		File(buildPath(dir, "gfxstate.cgram"), "wb").rawWrite(renderer.cgram);
		File(buildPath(dir, "gfxstate.oam"), "wb").rawWrite(renderer.oam1);
		File(buildPath(dir, "gfxstate.oam2"), "wb").rawWrite(renderer.oam2);
		File(buildPath(dir, "gfxstate.hdma"), "wb").rawWrite(renderer.allHDMAData());
	}
	private void commonDebugMenu(const UIState state) {
		static bool platformDebugWindowOpen;
		bool doDumpPPU;
		if (ImGui.BeginMainMenuBar()) {
			if (ImGui.BeginMenu("RAM")) {
				ImGui.MenuItem("Dump VRAM", null, &doDumpPPU);
				ImGui.EndMenu();
			}
			ImGui.EndMainMenuBar();
		}
		if (doDumpPPU) {
			dumpPPU();
			doDumpPPU = false;
		}
	}
	private void commonDebugState(const UIState state) {
		if (ImGui.BeginTabBar("platformdebug")) {
			if (ImGui.BeginTabItem("PPU")) {
				renderer.debugUI(state, platform.backend.video);
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("APU")) {
				apu.debugUI(state, platform.backend.video);
				ImGui.EndTabItem();
			}
			ImGui.EndTabBar();
		}
	}
	void dumpPPU() {
		const dir = prepareDumpDirectory();
		File(buildPath(dir, "gfxstate.regs"), "wb").rawWrite(renderer.registers);
		File(buildPath(dir, "gfxstate.vram"), "wb").rawWrite(renderer.vram);
		File(buildPath(dir, "gfxstate.cgram"), "wb").rawWrite(renderer.cgram);
		File(buildPath(dir, "gfxstate.oam"), "wb").rawWrite(renderer.oam1);
		File(buildPath(dir, "gfxstate.oam2"), "wb").rawWrite(renderer.oam2);
		File(buildPath(dir, "gfxstate.hdma"), "wb").rawWrite(renderer.allHDMAData());
	}
}

private auto detect(const scope ubyte[] data, scope string identifier) @safe pure {
	struct Result {
		bool header;
		bool matched;
	}
	foreach (headered, base; zip(only(false, true), only(0xFFB0, 0x101B0))) {
		const checksum = (cast(const ushort[])data[base + 46 .. base + 48])[0];
		const checksumComplement = (cast(const ushort[])data[base + 44 .. base + 46])[0];
		if ((checksum ^ checksumComplement) == 0xFFFF) {
			if (cast(const(char[]))data[base + 16 .. base + 37] == identifier) {
				return Result(headered, true);
			}
		}
	}
	return Result(false, false);
}

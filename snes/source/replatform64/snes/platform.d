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
	HLEWriteCallback spc700HLEWrite;
	HLEReadCallback spc700HLERead;
	private Settings settings;
	private immutable(ubyte)[] originalData;
	private bool useHLEAudio;
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
		crashHandler = &dumpSNESDebugData;
		platform.registerMemoryRange("VRAM", renderer.vram);
		platform.registerMemoryRange("OAM1", cast(ubyte[])renderer.oam1);
		platform.registerMemoryRange("OAM2", renderer.oam2);
	}
	void initializeAudio(T)(T* user, void function(T* user, ubyte[] buffer) callback, HLEWriteCallback writeCallback, HLEReadCallback readCallback) {
		platform.installAudioCallback(user, cast(void function(void*, ubyte[]))callback);
		spc700HLEWrite = writeCallback;
		spc700HLERead = readCallback;
		static if (__traits(compiles, user.backend = platform.backend.audio)) {
			user.backend = platform.backend.audio;
		}
		static if (__traits(compiles, audioDebug = &user.debugging)) {
			audioDebug = &user.debugging;
		}
		useHLEAudio = true;
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
	void handleOAMDMA(ubyte dmap, ubyte bbad, const(void)* a1t, ushort das, ushort oamaddr) {
		.handleOAMDMA(renderer, dmap, bbad, a1t, das, oamaddr);
	}
	void handleCGRAMDMA(ubyte dmap, ubyte bbad, const(void)* a1t, ushort das, ushort cgadd) {
		.handleCGRAMDMA(renderer, dmap, bbad, a1t, das, cgadd);
	}
	void handleVRAMDMA(ubyte dmap, ubyte bbad, const(void)* a1t, ushort das, ushort vmaddr, ubyte vmain) {
		.handleVRAMDMA(renderer, dmap, bbad, a1t, das, vmaddr, vmain);
	}
	void setFixedColourData(ubyte val) {
		COLDATA = val;
	}

	void setBGOffsetX(ubyte layer, ushort x) {
		switch (layer) {
			case 1:
				BG1HOFS = x;
				break;
			case 2:
				BG2HOFS = x;
				break;
			case 3:
				BG3HOFS = x;
				break;
			case 4:
				BG4HOFS = x;
				break;
			default: assert(0);
		}
	}
	void setBGOffsetY(ubyte layer, ushort y) {
		switch (layer) {
			case 1:
				BG1VOFS = y;
				break;
			case 2:
				BG2VOFS = y;
				break;
			case 3:
				BG3VOFS = y;
				break;
			case 4:
				BG4VOFS = y;
				break;
			default: assert(0);
		}
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
	mixin DoubleWriteRegisterRedirect!("BG1HOFS", "renderer", Register.BG1HOFS);
	mixin DoubleWriteRegisterRedirect!("BG2HOFS", "renderer", Register.BG2HOFS);
	mixin DoubleWriteRegisterRedirect!("BG3HOFS", "renderer", Register.BG3HOFS);
	mixin DoubleWriteRegisterRedirect!("BG4HOFS", "renderer", Register.BG4HOFS);
	mixin DoubleWriteRegisterRedirect!("BG1VOFS", "renderer", Register.BG1VOFS);
	mixin DoubleWriteRegisterRedirect!("BG2VOFS", "renderer", Register.BG2VOFS);
	mixin DoubleWriteRegisterRedirect!("BG3VOFS", "renderer", Register.BG3VOFS);
	mixin DoubleWriteRegisterRedirect!("BG4VOFS", "renderer", Register.BG4VOFS);
	mixin RegisterRedirect!("BG1SC", "renderer", Register.BG1SC);
	mixin RegisterRedirect!("BG2SC", "renderer", Register.BG2SC);
	mixin RegisterRedirect!("BG3SC", "renderer", Register.BG3SC);
	mixin RegisterRedirect!("BG4SC", "renderer", Register.BG4SC);
	mixin RegisterRedirect!("BG12NBA", "renderer", Register.BG12NBA);
	mixin RegisterRedirect!("BG34NBA", "renderer", Register.BG34NBA);
	mixin RegisterRedirect!("INIDISP", "renderer", Register.INIDISP);
	mixin RegisterRedirect!("OBSEL", "renderer", Register.OBSEL);
	mixin RegisterRedirect!("BGMODE", "renderer", Register.BGMODE);
	mixin RegisterRedirect!("MOSAIC", "renderer", Register.MOSAIC);
	mixin RegisterRedirect!("W12SEL", "renderer", Register.W12SEL);
	mixin RegisterRedirect!("W34SEL", "renderer", Register.W34SEL);
	mixin RegisterRedirect!("WOBJSEL", "renderer", Register.WOBJSEL);
	mixin RegisterRedirect!("WH0", "renderer", Register.WH0);
	mixin RegisterRedirect!("WH1", "renderer", Register.WH1);
	mixin RegisterRedirect!("WH2", "renderer", Register.WH2);
	mixin RegisterRedirect!("WH3", "renderer", Register.WH3);
	mixin RegisterRedirect!("WBGLOG", "renderer", Register.WBGLOG);
	mixin RegisterRedirect!("WOBJLOG", "renderer", Register.WOBJLOG);
	mixin RegisterRedirect!("TM", "renderer", Register.TM);
	mixin RegisterRedirect!("TD", "renderer", Register.TD);
	mixin RegisterRedirect!("TMW", "renderer", Register.TMW);
	mixin RegisterRedirect!("TSW", "renderer", Register.TSW);
	mixin RegisterRedirect!("CGWSEL", "renderer", Register.CGWSEL);
	mixin RegisterRedirect!("CGADSUB", "renderer", Register.CGADSUB);
	mixin RegisterRedirect!("COLDATA", "renderer", Register.COLDATA);
	void dumpSNESDebugData(string crashDir) {
		dumpScreen(cast(ubyte[])renderer.getRGBA8888(), crashDir, renderer.width, renderer.height);
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
		if (audioDebug) {
			audioDebug(state);
		}
	}
	private void commonDebugState(const UIState state) {
		//ImGui.Text("Layers");
		//foreach (idx, layer; ["BG1", "BG2", "BG3", "BG4", "OBJ"]) {
		//	const mask = (1 << idx);
		//	bool layerEnabled = !(layersDisabled & mask);
		//	ImGui.SameLine();
		//	if (ImGui.Checkbox(layer, &layerEnabled)) {
		//		layersDisabled = cast(ubyte)((layersDisabled & ~mask) | (!layerEnabled * mask));
		//	}
		//}
		renderer.debugUI(state, platform.backend.video);
		//if (ImGui.TreeNode("Registers")) {
		//	InputEditableR("INIDISP", INIDISP);
		//	InputEditableR("OBSEL", OBSEL);
		//	InputEditableR("OAMADDR", OAMADDR);
		//	InputEditableR("BGMODE", BGMODE);
		//	InputEditableR("MOSAIC", MOSAIC);
		//	InputEditableR("BGxSC", BG1SC, BG2SC, BG3SC, BG4SC);
		//	InputEditableR("BGxNBA", BG12NBA, BG34NBA);
		//	InputEditableR("BG1xOFS", BG1HOFS, BG1VOFS);
		//	InputEditableR("BG2xOFS", BG2HOFS, BG2VOFS);
		//	InputEditableR("BG3xOFS", BG3HOFS, BG3VOFS);
		//	InputEditableR("BG4xOFS", BG4HOFS, BG4VOFS);
		//	InputEditableR("M7SEL", M7SEL);
		//	InputEditableR("M7A", M7A);
		//	InputEditableR("M7B", M7B);
		//	InputEditableR("M7C", M7C);
		//	InputEditableR("M7D", M7D);
		//	InputEditableR("M7X", M7X);
		//	InputEditableR("M7Y", M7Y);
		//	InputEditableR("WxSEL", W12SEL, W34SEL);
		//	InputEditableR("WOBJSEL", WOBJSEL);
		//	InputEditableR("WHx", WH0, WH1, WH2, WH3);
		//	InputEditableR("WBGLOG", WBGLOG);
		//	InputEditableR("WOBJLOG", WOBJLOG);
		//	InputEditableR("TM", TM);
		//	InputEditableR("TS", TS);
		//	InputEditableR("TMW", TMW);
		//	InputEditableR("TSW", TSW);
		//	InputEditableR("CGWSEL", CGWSEL);
		//	InputEditableR("CGADSUB", CGADSUB);
		//	//InputEditableR("FIXED_COLOUR_DATA", renderer.FIXED_COLOUR_DATA_R, renderer.FIXED_COLOUR_DATA_G, renderer.FIXED_COLOUR_DATA_B);
		//	InputEditableR("SETINI", SETINI);
		//	ImGui.TreePop();
		//}
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
	void APUIO(ubyte port, ubyte val) {
		spc700HLEWrite(port, val, platform.backend.audio);
	}
	ubyte APUIO(ubyte port) {
		return spc700HLERead(port);
	}
	void APUIO0(ubyte val) {
		APUIO(0, val);
	}
	void APUIO1(ubyte val) {
		APUIO(1, val);
	}
	void APUIO2(ubyte val) {
		APUIO(2, val);
	}
	void APUIO3(ubyte val) {
		APUIO(3, val);
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
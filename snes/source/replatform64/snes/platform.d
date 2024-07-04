module replatform64.snes.platform;

import replatform64.assets;
import replatform64.backend.common;
import replatform64.commonplatform;
import replatform64.dumping;
import replatform64.registers;
import replatform64.snes.audio;
import replatform64.snes.hardware;
import replatform64.snes.rendering;
import replatform64.snes.sfcdma;
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
	void function() interruptHandler;
	string title;
	SNESRenderer renderer;
	DebugFunction debugMenuRenderer;
	DebugFunction gameStateMenu;
	CrashHandler gameStateDumper;
	string matchingInternalID;
	HLEWriteCallback spc700HLEWrite;
	HLEReadCallback spc700HLERead;
	private Settings settings;
	private immutable(ubyte)[] originalData;
	private bool useHLEAudio;
	private PlatformCommon platform;
	DMAChannel[8] dmaChannels; ///
	ubyte HDMAEN;
	ubyte HVBJOY;
	ubyte NMITIMEN;
	ubyte STAT78;
	private DebugFunction audioDebug;
	auto ref gameID() {
		return platform.gameID;
	}
	T loadSettings(T)() {
		auto allSettings = platform.loadSettings!(Settings, T)();
		settings = allSettings.system;
		return allSettings.game;
	}
	void saveSettings(T)(T gameSettings) {
		platform.saveSettings(settings, gameSettings);
	}
	void initialize(Backend backendType = Backend.autoSelect) {
		platform.initialize({ entryPoint(); }, backendType);
		renderer.initialize(title, platform.backend.video, backendType == Backend.none ? RendererSettings(engine: Renderer.neo) : settings.renderer);
		platform.nativeResolution = renderer.getResolution();
		crashHandler = &dumpSNESDebugData;
		platform.debugMenu = debugMenuRenderer;
		platform.platformDebugMenu = &commonSNESDebugging;
		platform.debugState = gameStateMenu;
		platform.platformDebugState = &commonSNESDebuggingState;
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
	void run() {
		if (settings.debugging) {
			platform.enableDebuggingFeatures();
		}
		platform.showUI();
		while(true) {
			if (platform.runFrame({ interruptHandler(); }, { renderer.draw(); })) {
				break;
			}
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
	void wait() {
		platform.wait({ interruptHandler(); });
	}
	void runHook(string id) {
		platform.runHook(id);
	}
	void registerHook(string id, HookFunction hook, HookSettings settings = HookSettings.init) {
		platform.registerHook(id, hook.toDelegate(), settings);
	}
	void registerHook(string id, HookDelegate hook, HookSettings settings = HookSettings.init) {
		platform.registerHook(id, hook, settings);
	}
	void handleAssets(Modules...)(ExtractFunction extractor = null, LoadFunction loader = null, bool toFilesystem = false) {
		platform.handleAssets!Modules(romData, extractor, loader, toFilesystem);
	}
	void loadWAV(const(ubyte)[] data) {
		platform.backend.audio.loadWAV(data);
	}
	ref T sram(T)(uint slot) {
		return platform.sram!T(slot);
	}
	void commitSRAM() {
		platform.commitSRAM();
	}
	void deleteSlot(uint slot) {
		platform.deleteSlot(slot);
	}
	void playbackDemo(const RecordedInputState[] demo) @safe pure {
		platform.playbackDemo(demo);
	}
	// SNES-specific functions
	void handleHDMA() {
		import std.algorithm.sorting : sort;
		import std.algorithm.mutation : SwapStrategy;
		renderer.numHDMA = 0;
		const channels = HDMAEN;
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
	void handleOAMDMA(ubyte dmap, ubyte bbad, const(void)* a1t, ushort das, ushort oamaddr) {
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
	void handleCGRAMDMA(ubyte dmap, ubyte bbad, const(void)* a1t, ushort das, ushort cgadd) {
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
	void handleVRAMDMA(ubyte dmap, ubyte bbad, const(void)* a1t, ushort das, ushort vmaddr, ubyte vmain) {
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
	ushort getControllerState(ubyte playerID) const @safe pure {
		ushort result = 0;
		if (platform.inputState.controllers[playerID] & ControllerMask.y) { result |= Pad.y; }
		if (platform.inputState.controllers[playerID] & ControllerMask.b) { result |= Pad.b; }
		if (platform.inputState.controllers[playerID] & ControllerMask.x) { result |= Pad.x; }
		if (platform.inputState.controllers[playerID] & ControllerMask.a) { result |= Pad.a; }
		if (platform.inputState.controllers[playerID] & ControllerMask.r) { result |= Pad.r; }
		if (platform.inputState.controllers[playerID] & ControllerMask.l) { result |= Pad.l; }
		if (platform.inputState.controllers[playerID] & ControllerMask.start) { result |= Pad.start; }
		if (platform.inputState.controllers[playerID] & ControllerMask.select) { result |= Pad.select; }
		if (platform.inputState.controllers[playerID] & ControllerMask.up) { result |= Pad.up; }
		if (platform.inputState.controllers[playerID] & ControllerMask.down) { result |= Pad.down; }
		if (platform.inputState.controllers[playerID] & ControllerMask.left) { result |= Pad.left; }
		if (platform.inputState.controllers[playerID] & ControllerMask.right) { result |= Pad.right; }
		if (platform.inputState.controllers[playerID] & ControllerMask.extra1) { result |= Pad.extra1; }
		if (platform.inputState.controllers[playerID] & ControllerMask.extra2) { result |= Pad.extra2; }
		if (platform.inputState.controllers[playerID] & ControllerMask.extra3) { result |= Pad.extra3; }
		if (platform.inputState.controllers[playerID] & ControllerMask.extra4) { result |= Pad.extra4; }
		return result;
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
		if (gameStateDumper) {
			gameStateDumper(crashDir);
		}
	}
	void dumpVRAMToDir(string dir) {
		File(buildPath(dir, "gfxstate.regs"), "wb").rawWrite(renderer.registers);
		File(buildPath(dir, "gfxstate.vram"), "wb").rawWrite(renderer.vram);
		File(buildPath(dir, "gfxstate.cgram"), "wb").rawWrite(renderer.cgram);
		File(buildPath(dir, "gfxstate.oam"), "wb").rawWrite(renderer.oam1);
		File(buildPath(dir, "gfxstate.oam2"), "wb").rawWrite(renderer.oam2);
		File(buildPath(dir, "gfxstate.hdma"), "wb").rawWrite(renderer.allHDMAData());
	}
	private void commonSNESDebugging(const UIState state) {
		static bool vramEditorActive;
		static MemoryEditor memoryEditorVRAM = defaultMemoryEditorSettings("VRAM.bin");
		static bool oam1EditorActive;
		static MemoryEditor memoryEditorOAM1 = defaultMemoryEditorSettings("OAM1.bin");
		static bool oam2EditorActive;
		static MemoryEditor memoryEditorOAM2 = defaultMemoryEditorSettings("OAM2.bin");
		static bool platformDebugWindowOpen;
		bool doDumpPPU;
		if (ImGui.BeginMainMenuBar()) {
			if (ImGui.BeginMenu("RAM")) {
				ImGui.MenuItem("Dump VRAM", null, &doDumpPPU);
				ImGui.MenuItem("VRAM", null, &vramEditorActive);
				ImGui.MenuItem("OAM1", null, &oam1EditorActive);
				ImGui.MenuItem("OAM2", null, &oam2EditorActive);
				ImGui.EndMenu();
			}
			ImGui.EndMainMenuBar();
		}
		if (vramEditorActive) {
			vramEditorActive = memoryEditorVRAM.DrawWindow("VRAM", renderer.vram);
		}
		if (oam1EditorActive) {
			oam1EditorActive = memoryEditorOAM1.DrawWindow("OAM1", renderer.oam1);
		}
		if (oam2EditorActive) {
			oam2EditorActive = memoryEditorOAM2.DrawWindow("OAM2", renderer.oam2);
		}
		if (doDumpPPU) {
			dumpPPU();
			doDumpPPU = false;
		}
		if (audioDebug) {
			audioDebug(state);
		}
	}
	private void commonSNESDebuggingState(const UIState state) {
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

unittest {
	SNES snes;
	import std.meta : aliasSeqOf;
	import std.range : iota;
	immutable ubyte[100] testSource = [aliasSeqOf!(iota(0, 100))];
	snes.handleVRAMDMA(0x01, 0x18, &testSource[0], 100, 0, 0x80);
	assert(snes.renderer.vram[0 .. 100] == testSource);
	immutable ubyte[2] testFixedHigh = [0x30, 0];
	snes.handleVRAMDMA(0x08, 0x19, &testFixedHigh[0], 0x400, 0x5800, 0x80);
	assert(snes.renderer.vram[0 .. 100] == testSource);
	assert(snes.renderer.vram[0xB001] == 0x30);
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
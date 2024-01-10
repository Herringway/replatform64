module librehome.snes.platform;
import librehome.backend.common;
import librehome.backend.sdl2;
import librehome.common;
import librehome.dumping;
import librehome.framestat;
import librehome.planet;
import librehome.snes.audio;
import librehome.snes.hardware;
import librehome.snes.rendering;
import librehome.snes.sfcdma;
import librehome.ui;
import librehome.watchdog;

import core.thread;
import std.algorithm.comparison;
import std.algorithm.mutation;
import std.datetime;
import std.file;
import std.format;
import std.functional;
import std.logger;
import std.range;
import std.path;
import std.stdio;

import siryul;

struct Settings {
	static struct PlatformSettings {
		RendererSettings renderer;
	}
	PlatformSettings snes;
	VideoSettings video;
	InputSettings input;
	bool debugging;
}
enum settingsFile = "settings.yaml";

struct SNES {
	void function() entryPoint;
	void function() interruptHandler;
	string title;
	string gameID;
	SNESRenderer renderer;
	PlatformBackend backend;
	InputState lastInputState;
	DebugFunction debugMenuRenderer;
	DebugFunction gameStateMenu;
	CrashHandler gameStateDumper;
	string matchingInternalID;
	private Settings settings;
	private immutable(ubyte)[] originalData;
	private AllSPC spc700;
	private ubyte[][uint] sramSlotBuffer;
	T loadSettings(T)() {
		static struct FullSettings {
			Settings system;
			T game;
		}
		if (!settingsFile.exists) {
			FullSettings defaults;
			defaults.system.input = getDefaultInputSettings();
			defaults.toFile!YAML(settingsFile);
		}
		auto allSettings = fromFile!(FullSettings, YAML)(settingsFile);
		settings = allSettings.system;
		return allSettings.game;
	}
	void saveSettings(T)(T gameSettings) {
		static struct FullSettings {
			Settings system;
			T game;
		}
		FullSettings(settings, gameSettings).toFile!YAML(settingsFile);
	}
	void initialize() {
		backend = new SDL2Platform;
		backend.initialize();
		backend.audio.initialize(&spc700, &audioCallback, 32000, 2, 512);
		backend.input.initialize(settings.input);
		renderer.initialize(title, settings.video, backend.video, settings.snes.renderer, settings.debugging);
		backend.video.hideUI();
		crashHandler = &dumpSNESDebugData;
	}
	int run() {
		auto game = new Fiber(entryPoint);
		startWatchDog();
		bool paused;
		backend.video.setDebuggingFunctions(debugMenuRenderer, &commonSNESDebugging, gameStateMenu, &commonSNESDebuggingState);
		backend.video.showUI();
		while(true) {
			// pet the dog each frame so it knows we're ok
			watchDog.pet();
			frameStatTracker.startFrame();
			if (backend.processEvents()) {
				break;
			}
			lastInputState = backend.input.getState();
			frameStatTracker.checkpoint(FrameStatistic.events);
			if (lastInputState.exit) {
				break;
			}

			if (!paused || lastInputState.step) {
				lastInputState.step = false;
				Throwable t = game.call(Fiber.Rethrow.no);
				if(t) {
					writeDebugDump(t.msg, t.info);
					return 1;
				}
				interruptHandler();
			}
			frameStatTracker.checkpoint(FrameStatistic.gameLogic);
			renderer.draw();
			frameStatTracker.checkpoint(FrameStatistic.ppu);

			if (!lastInputState.fastForward) {
				renderer.waitNextFrame();
			}

			if (lastInputState.pause) {
				paused = !paused;
				lastInputState.pause = false;
			}
			frameStatTracker.endFrame();
		}
		return 0;
	}
	void wait() {
		Fiber.yield();
	}
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
		const intensity = val & 0x1F;
		if (val & 0x80) {
			renderer.FIXED_COLOUR_DATA_B = intensity;
		}
		if (val & 0x40) {
			renderer.FIXED_COLOUR_DATA_G = intensity;
		}
		if (val & 0x20) {
			renderer.FIXED_COLOUR_DATA_R = intensity;
		}
	}

	void setBGOffsetX(ubyte layer, ushort x) {
		switch (layer) {
			case 1:
				renderer.BG1HOFS = x;
				break;
			case 2:
				renderer.BG2HOFS = x;
				break;
			case 3:
				renderer.BG3HOFS = x;
				break;
			case 4:
				renderer.BG4HOFS = x;
				break;
			default: assert(0);
		}
	}
	void setBGOffsetY(ubyte layer, ushort y) {
		switch (layer) {
			case 1:
				renderer.BG1VOFS = y;
				break;
			case 2:
				renderer.BG2VOFS = y;
				break;
			case 3:
				renderer.BG3VOFS = y;
				break;
			case 4:
				renderer.BG4VOFS = y;
				break;
			default: assert(0);
		}
	}
	ushort getControllerState(ubyte playerID) @safe pure {
		ushort result = 0;
		if (lastInputState.controllers[playerID] & ControllerMask.y) { result |= Pad.y; }
		if (lastInputState.controllers[playerID] & ControllerMask.b) { result |= Pad.b; }
		if (lastInputState.controllers[playerID] & ControllerMask.x) { result |= Pad.x; }
		if (lastInputState.controllers[playerID] & ControllerMask.a) { result |= Pad.a; }
		if (lastInputState.controllers[playerID] & ControllerMask.r) { result |= Pad.r; }
		if (lastInputState.controllers[playerID] & ControllerMask.l) { result |= Pad.l; }
		if (lastInputState.controllers[playerID] & ControllerMask.start) { result |= Pad.start; }
		if (lastInputState.controllers[playerID] & ControllerMask.select) { result |= Pad.select; }
		if (lastInputState.controllers[playerID] & ControllerMask.up) { result |= Pad.up; }
		if (lastInputState.controllers[playerID] & ControllerMask.down) { result |= Pad.down; }
		if (lastInputState.controllers[playerID] & ControllerMask.left) { result |= Pad.left; }
		if (lastInputState.controllers[playerID] & ControllerMask.right) { result |= Pad.right; }
		if (lastInputState.controllers[playerID] & ControllerMask.extra1) { result |= Pad.extra1; }
		if (lastInputState.controllers[playerID] & ControllerMask.extra2) { result |= Pad.extra2; }
		if (lastInputState.controllers[playerID] & ControllerMask.extra3) { result |= Pad.extra3; }
		if (lastInputState.controllers[playerID] & ControllerMask.extra4) { result |= Pad.extra4; }
		return result;
	}
	DMAChannel[8] dmaChannels; ///
	ubyte HDMAEN;
	ubyte HVBJOY;
	ubyte NMITIMEN;
	ubyte STAT78;
	void BG1SC(ubyte val) {
		renderer.BG1SC = val;
	}
	void BG2SC(ubyte val) {
		renderer.BG2SC = val;
	}
	void BG3SC(ubyte val) {
		renderer.BG3SC = val;
	}
	void BG4SC(ubyte val) {
		renderer.BG4SC = val;
	}
	void BG12NBA(ubyte val) {
		renderer.BG12NBA = val;
	}
	void BG34NBA(ubyte val) {
		renderer.BG34NBA = val;
	}
	void INIDISP(ubyte val) {
		renderer.INIDISP = val;
	}
	void OBSEL(ubyte val) {
		renderer.OBSEL = val;
	}
	void BGMODE(ubyte val) {
		renderer.BGMODE = val;
	}
	void MOSAIC(ubyte val) {
		renderer.MOSAIC = val;
	}
	void W12SEL(ubyte val) {
		renderer.W12SEL = val;
	}
	void W34SEL(ubyte val) {
		renderer.W34SEL = val;
	}
	void WOBJSEL(ubyte val) {
		renderer.WOBJSEL = val;
	}
	void WH0(ubyte val) {
		renderer.WH0 = val;
	}
	void WH1(ubyte val) {
		renderer.WH1 = val;
	}
	void WH2(ubyte val) {
		renderer.WH2 = val;
	}
	void WH3(ubyte val) {
		renderer.WH3 = val;
	}
	void WBGLOG(ubyte val) {
		renderer.WBGLOG = val;
	}
	void WOBJLOG(ubyte val) {
		renderer.WOBJLOG = val;
	}
	void TM(ubyte val) {
		renderer.TM = val;
	}
	alias TS = TD;
	void TD(ubyte val) {
		renderer.TS = val;
	}
	void TMW(ubyte val) {
		renderer.TMW = val;
	}
	void TSW(ubyte val) {
		renderer.TSW = val;
	}
	void CGWSEL(ubyte val) {
		renderer.CGWSEL = val;
	}
	void CGADSUB(ubyte val) {
		renderer.CGADSUB = val;
	}
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
	immutable(ubyte)[] romData() {
		if (!originalData) {
			originalData = (cast(ubyte[])read(gameID~".sfc")).idup;
			const result = detect(originalData, matchingInternalID);
			info("Loaded ", title, " ROM", result.header ? " (with header)" : "");
			if (result.header) {
				originalData = originalData[0x200 .. $];
			}
		}
		return originalData;
	}
	bool assetsExist() {
		return (gameID~".planet").exists;
	}
	PlanetArchive assets() {
		if ((gameID~".planet").exists) {
			return PlanetArchive.read(cast(ubyte[])read(gameID~".planet"));
		}
		throw new Exception("Not found");
	}
	void saveAssets(PlanetArchive archive) {
		archive.write(File(gameID~".planet", "w").lockingBinaryWriter);
	}
	void runHook(string id) {
		if (auto matchingHooks = id in hooks) {
			for (int i = 0; i < matchingHooks.length; i++) {
				(*matchingHooks)[i].func();
				if ((*matchingHooks)[i].settings.type == HookType.once) {
					*matchingHooks = (*matchingHooks).remove(i);
				}
			}
		}
	}
	void registerHook(string id, HookFunction hook, HookSettings settings = HookSettings.init) {
		registerHook(id, hook.toDelegate(), settings);
	}
	HookState[][string] hooks;
	void registerHook(string id, HookDelegate hook, HookSettings settings = HookSettings.init) {
		hooks.require(id, []) ~= HookState(hook, settings);
	}
	private void commonSNESDebugging(const UIState state) {
		static MemoryEditor defaultMemoryEditorSettings(string filename) {
			MemoryEditor editor;
			editor.Dumpable = true;
			editor.DumpFile = filename;
			return editor;
		}
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
		if (ImGui.TreeNode("Sprites")) {
			foreach (id, entry; renderer.oam1) {
				const uint upperX = !!(renderer.oam2[id/4] & (1 << ((id % 4) * 2)));
				const size = !!(renderer.oam2[id/4] & (1 << ((id % 4) * 2 + 1)));
				if (entry.yCoord < 0xE0) {
					if (ImGui.TreeNode(format!"Sprite %s"(id))) {
						ImGui.BeginDisabled();
						ImGui.Text(format!"Tile Offset: %s"(entry.startingTile));
						ImGui.Text(format!"Coords: (%s, %s)"(entry.xCoord + (upperX << 8), entry.yCoord));
						ImGui.Text(format!"Palette: %s"(entry.palette));
						bool boolean = entry.flipVertical;
						ImGui.Checkbox("Vertical flip", &boolean);
						boolean = entry.flipHorizontal;
						ImGui.Checkbox("Horizontal flip", &boolean);
						ImGui.Text(format!"Priority: %s"(entry.priority));
						ImGui.Text(format!"Priority: %s"(entry.nameTable));
						boolean = size;
						ImGui.Checkbox("Use alt size", &boolean);
						ImGui.EndDisabled();
						ImGui.TreePop();
					}
				}
			}
			ImGui.TreePop();
		}
		if (ImGui.TreeNode("Layers")) {
			const screenRegisters = [renderer.BG1SC, renderer.BG2SC, renderer.BG3SC, renderer.BG4SC];
			const screenRegisters2 = [renderer.BG12NBA & 0xF, renderer.BG12NBA >> 4, renderer.BG34NBA & 0xF, renderer.BG34NBA >> 4];
			static foreach (layer, label; ["BG1", "BG2", "BG3", "BG4"]) {{
				if (ImGui.TreeNode(label)) {
					ImGui.Text(format!"Tilemap address: $%04X"((screenRegisters[layer] & 0xFC) << 9));
					ImGui.Text(format!"Tile base address: $%04X"(screenRegisters2[layer] << 13));
					ImGui.Text(format!"Size: %s"(["32x32", "64x32", "32x64", "64x64"][screenRegisters[layer] & 3]));
					ImGui.Text(format!"Tile size: %s"(["8x8", "16x16"][!!(renderer.BGMODE >> (4 + layer))]));
					//disabledCheckbox("Mosaic Enabled", !!((renderer.MOSAIC >> layer) & 1));
					ImGui.TreePop();
				}
			}}
			ImGui.TreePop();
		}
		if (ImGui.TreeNode("VRAM")) {
			static int paletteID = 0;
			if (ImGui.InputInt("Palette", &paletteID)) {
				paletteID = clamp(paletteID, 0, 16);
			}
			const texWidth = 16 * 8;
			const texHeight = 0x8000 / 16 / 16 * 8;
			static ubyte[2 * texWidth * texHeight] data;
			auto pixels = cast(ushort[])(data[]);
			ushort[16] palette = renderer.cgram[paletteID * 16 .. (paletteID + 1) * 16];
			palette[] &= 0x7FFF;
			foreach (idx, tile; (cast(ushort[])renderer.vram).chunks(16).enumerate) {
				const base = (idx % 16) * 8 + (idx / 16) * texWidth * 8;
				foreach (p; 0 .. 8 * 8) {
					const px = p % 8;
					const py = p / 8;
					const plane01 = tile[py] & pixelPlaneMasks[px];
					const plane23 = tile[py + 8] & pixelPlaneMasks[px];
					const s = 7 - px;
					const pixel = ((plane01 & 0xFF) >> s) | (((plane01 >> 8) >> s) << 1) | (((plane23 & 0xFF) >> s) << 2) | (((plane23 >> 8) >> s) << 3);
					pixels[base + px + py * texWidth] = palette[pixel];
				}
			}
			//ImGui.Image(createTexture(data[], texWidth, texHeight, ushort.sizeof * texWidth, nativeFormat), ImVec2(texWidth * 3, texHeight * 3));
			ImGui.TreePop();
		}
		if (ImGui.TreeNode("Registers")) {
			InputEditableR("INIDISP", renderer.INIDISP);
			InputEditableR("OBSEL", renderer.OBSEL);
			InputEditableR("OAMADDR", renderer.OAMADDR);
			InputEditableR("BGMODE", renderer.BGMODE);
			InputEditableR("MOSAIC", renderer.MOSAIC);
			InputEditableR("BGxSC", renderer.BG1SC, renderer.BG2SC, renderer.BG3SC, renderer.BG4SC);
			InputEditableR("BGxNBA", renderer.BG12NBA, renderer.BG34NBA);
			InputEditableR("BG1xOFS", renderer.BG1HOFS, renderer.BG1VOFS);
			InputEditableR("BG2xOFS", renderer.BG2HOFS, renderer.BG2VOFS);
			InputEditableR("BG3xOFS", renderer.BG3HOFS, renderer.BG3VOFS);
			InputEditableR("BG4xOFS", renderer.BG4HOFS, renderer.BG4VOFS);
			InputEditableR("M7SEL", renderer.M7SEL);
			InputEditableR("M7A", renderer.M7A);
			InputEditableR("M7B", renderer.M7B);
			InputEditableR("M7C", renderer.M7C);
			InputEditableR("M7D", renderer.M7D);
			InputEditableR("M7X", renderer.M7X);
			InputEditableR("M7Y", renderer.M7Y);
			InputEditableR("WxSEL", renderer.W12SEL, renderer.W34SEL);
			InputEditableR("WOBJSEL", renderer.WOBJSEL);
			InputEditableR("WHx", renderer.WH0, renderer.WH1, renderer.WH2, renderer.WH3);
			InputEditableR("WBGLOG", renderer.WBGLOG);
			InputEditableR("WOBJLOG", renderer.WOBJLOG);
			InputEditableR("TM", renderer.TM);
			InputEditableR("TS", renderer.TS);
			InputEditableR("TMW", renderer.TMW);
			InputEditableR("TSW", renderer.TSW);
			InputEditableR("CGWSEL", renderer.CGWSEL);
			InputEditableR("CGADSUB", renderer.CGADSUB);
			InputEditableR("FIXED_COLOUR_DATA", renderer.FIXED_COLOUR_DATA_R, renderer.FIXED_COLOUR_DATA_G, renderer.FIXED_COLOUR_DATA_B);
			InputEditableR("SETINI", renderer.SETINI);
			ImGui.TreePop();
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
	void loadNSPC(const(ubyte)[] data) {
		spc700.loadSong(data);
	}
	void loadSFXWav(const(ubyte)[] data) {
		backend.audio.loadWAV(data);
	}
	void APUIO0(ubyte val) {
		if (val == 0) {
			spc700.stop();
		} else {
			spc700.changeSong(cast(ubyte)(val - 1));
		}
	}
	void APUIO1(ubyte val) {	}
	void APUIO2(ubyte val) {}
	void APUIO3(ubyte val) {
		backend.audio.playWAV(val);
	}
	void extractAssets(ExtractFunction func) {
		.extractAssets(func, backend, romData, ".");
	}
	private void prepareSRAM(uint slot, size_t size) {
		sramSlotBuffer.require(slot, () {
			auto buffer = new ubyte[](size);
			const name = saveFileName(slot);
			if (name.exists) {
				infof("Reading SRAM file %s", name);
				File(name, "r").rawRead(buffer);
			}
			return buffer;
		}());
	}

	ref T sram(T)(uint slot) {
		prepareSRAM(slot, T.sizeof);
		return (cast(T[])sramSlotBuffer[slot][0 .. T.sizeof])[0];
	}
	void commitSRAM() {
		foreach (slot, data; sramSlotBuffer) {
			const name = saveFileName(slot);
			infof("Writing %s", name);
			File(name, "wb").rawWrite(data);
		}
	}
	void deleteSlot(uint slot) {
		remove(saveFileName(slot));
	}
	private string saveFileName(uint slot) {
		return format!"%s.%s.sav"(title, slot);
	}
}

enum HookType {
	once,
	repeat
}

alias HookDelegate = void delegate();
alias HookFunction = void function();
struct HookState {
	HookDelegate func;
	HookSettings settings;
}
struct HookSettings {
	HookType type;
}

struct DummySNES {
	void function() interruptHandler;
	ubyte INIDISP;
	ubyte HDMAEN;
	ubyte MOSAIC;
	ubyte WH0;
	ubyte WH1;
	ubyte WH2;
	ubyte WH3;
	ubyte TM;
	ubyte TD;
	alias TS = TD;
	ubyte TMW;
	ubyte TSW;
	ubyte WOBJLOG;
	ubyte WBGLOG;
	ubyte WOBJSEL;
	ubyte OBSEL;
	ubyte W12SEL;
	ubyte W34SEL;
	ubyte BG1SC;
	ubyte BG2SC;
	ubyte BG3SC;
	ubyte BG4SC;
	ubyte BG12NBA;
	ubyte BG34NBA;
	ubyte STAT78;
	ubyte APUIO0;
	ubyte APUIO1;
	ubyte APUIO2;
	ubyte APUIO3;
	ubyte HVBJOY;
	ubyte NMITIMEN;
	ubyte BGMODE;
	ubyte CGWSEL;
	ubyte CGADSUB;
	DMAChannel[8] dmaChannels; ///

	void wait() { interruptHandler(); }
	void runHook(string) {}
	void registerHook(string id, void function() hook, HookSettings settings = HookSettings.init) {}
	void registerHook(string id, void delegate() hook, HookSettings settings = HookSettings.init) {}
	void loadSFXWav(const ubyte[]) {}
	void loadNSPC(const ubyte[]) {}
	void saveAssets(PlanetArchive) {}
	ushort getControllerState(ubyte) @safe pure { return 0; }
	void setBGOffsetX(ubyte, ushort) {}
	void setBGOffsetY(ubyte, ushort) {}
	void handleOAMDMA(ubyte, ubyte, const(void)*, ushort, ushort) {}
	void handleCGRAMDMA(ubyte, ubyte, const(void)*, ushort, ushort) {}
	void handleVRAMDMA(ubyte, ubyte, const(void)*, ushort, ushort, ubyte) {}
	void handleHDMA() {}
	void setFixedColourData(ubyte) {}
	ref T sram(T)(uint) { return *(new T); }
	void deleteSlot(uint) {}
	void commitSRAM() {}
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
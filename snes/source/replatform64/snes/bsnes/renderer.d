module replatform64.snes.bsnes.renderer;

import replatform64.backend.common.interfaces;
import replatform64.snes.hardware;
import replatform64.snes.renderer;
import replatform64.ui;
import replatform64.util;

import std.algorithm.comparison;
import std.format;
import std.logger;
import std.range;

import bindbc.common;
import bindbc.loader;

import pixelmancy.colours;
import pixelmancy.tiles;

public enum ImgW = 512;
public enum ImgH = 448;

public struct SnesDrawFrameData {
	alias ColourFormat = RGB555;
align:
	ubyte INIDISP;
	ubyte OBSEL;
	ushort OAMADDR;
	ubyte BGMODE;
	ubyte MOSAIC;
	ubyte BG1SC;
	ubyte BG2SC;
	ubyte BG3SC;
	ubyte BG4SC;
	ubyte BG12NBA;
	ubyte BG34NBA;
	ushort BG1HOFS;
	ushort BG1VOFS;
	ushort BG2HOFS;
	ushort BG2VOFS;
	ushort BG3HOFS;
	ushort BG3VOFS;
	ushort BG4HOFS;
	ushort BG4VOFS;
	ubyte M7SEL;
	ushort M7A;
	ushort M7B;
	ushort M7C;
	ushort M7D;
	ushort M7X;
	ushort M7Y;
	ubyte W12SEL;
	ubyte W34SEL;
	ubyte WOBJSEL;
	ubyte WH0;
	ubyte WH1;
	ubyte WH2;
	ubyte WH3;
	ubyte WBGLOG;
	ubyte WOBJLOG;
	ubyte TM;
	ubyte TS;
	ubyte TMW;
	ubyte TSW;
	ubyte CGWSEL;
	ubyte CGADSUB;
	ubyte FIXED_COLOUR_DATA_R;
	ubyte FIXED_COLOUR_DATA_G;
	ubyte FIXED_COLOUR_DATA_B;
	ubyte SETINI;

	ushort[0x8000] vram;
	ushort[0x100] cgram;
	union {
		struct {
			OAMEntry[128] oam1;
			ubyte[32] oam2;
		}
		ubyte[oam1.sizeof + oam2.sizeof] oamFull;
	}

	ushort numHdmaWrites;
	HDMAWrite[4*8*240] hdmaData;
	const(ubyte[]) getRegistersConst() const {
		const ubyte* first = cast(const ubyte*)(&INIDISP);
		const ubyte* last = cast(const ubyte*)(&SETINI);
		return first[0..(last-first+1)];
	}
	void writeRegister(ushort addr, ubyte val) @safe pure {
		switch (addr) {
			case 0x2100:
				INIDISP = val;
				break;
			case 0x2101:
				OBSEL = val;
				break;
			case 0x2102:
				//OAMADDL = val;
				break;
			case 0x2103:
				//OAMADDH = val;
				break;
			case 0x2104:
				//OAMDATA = val;
				break;
			case 0x2105:
				BGMODE = val;
				break;
			case 0x2106:
				MOSAIC = val;
				break;
			case 0x2107:
				BG1SC = val;
				break;
			case 0x2108:
				BG2SC = val;
				break;
			case 0x2109:
				BG3SC = val;
				break;
			case 0x210A:
				BG4SC = val;
				break;
			case 0x210B:
				BG12NBA = val;
				break;
			case 0x210C:
				BG34NBA = val;
				break;
			case 0x210D:
				BG1HOFS = (val << 8) | (BG1HOFS >> 8);
				break;
			case 0x210E:
				BG1VOFS = (val << 8) | (BG1VOFS >> 8);
				break;
			case 0x210F:
				BG2HOFS = (val << 8) | (BG2HOFS >> 8);
				break;
			case 0x2110:
				BG2VOFS = (val << 8) | (BG2VOFS >> 8);
				break;
			case 0x2111:
				BG3HOFS = (val << 8) | (BG3HOFS >> 8);
				break;
			case 0x2112:
				BG3VOFS = (val << 8) | (BG3VOFS >> 8);
				break;
			case 0x2113:
				BG4HOFS = (val << 8) | (BG4HOFS >> 8);
				break;
			case 0x2114:
				BG4VOFS = (val << 8) | (BG4VOFS >> 8);
				break;
			case 0x2115:
				//VMAIN = val;
				break;
			case 0x2116:
				//VMADDL = val;
				break;
			case 0x2123:
				W12SEL = val;
				break;
			case 0x2124:
				W34SEL = val;
				break;
			case 0x2125:
				WOBJSEL = val;
				break;
			case 0x2126:
				WH0 = val;
				break;
			case 0x2127:
				WH1 = val;
				break;
			case 0x2128:
				WH2 = val;
				break;
			case 0x2129:
				WH3 = val;
				break;
			case 0x212A:
				WBGLOG = val;
				break;
			case 0x212B:
				WOBJLOG = val;
				break;
			case 0x212C:
				TM = val;
				break;
			case 0x212D:
				TS = val;
				break;
			case 0x212E:
				TMW = val;
				break;
			case 0x212F:
				TSW = val;
				break;
			case 0x2130:
				CGWSEL = val;
				break;
			case 0x2131:
				CGADSUB = val;
				break;
			case 0x2132:
				if (val & 0x80) {
					FIXED_COLOUR_DATA_B = val;
				}
				if (val & 0x40) {
					FIXED_COLOUR_DATA_G = val;
				}
				if (val & 0x20) {
					FIXED_COLOUR_DATA_R = val;
				}
				break;
			default:
				debug infof("Write to unknown register %04X", addr);
				break;
		}
	}
	ubyte readRegister(ushort addr) @safe pure {
		return 0;
	}
	void debugUI(const UIState state, VideoBackend video) {
		if (ImGui.BeginTabBar("rendererpreview")) {
			if (ImGui.BeginTabItem("Global state")) {
				ImGui.Text("BG mode: %d", BGMODE & 7);
				ImGui.Text("Brightness: %d", INIDISP & 15);
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Sprites")) {
				drawSprites!ColourFormat(oam1.length, video, 64, 64, (canvas, index) {
					canvas[] = ColourFormat(31, 0, 31); // placeholder until we have some real drawing code
				}, (index) {
					const entry = oam1[index];
					const uint upperX = !!(oam2[index / 4] & (1 << ((index % 4) * 2)));
					const size = !!(oam2[index / 4] & (1 << ((index % 4) * 2 + 1)));
					ImGui.BeginDisabled();
					ImGui.Text(format!"Tile Offset: %s"(entry.startingTile));
					ImGui.Text(format!"Coords: (%s, %s)"(entry.xCoord + (upperX << 8), entry.yCoord));
					ImGui.Text(format!"Palette: %s"(entry.palette));
					bool boolean = entry.flipVertical;
					ImGui.Checkbox("Vertical flip", &boolean);
					boolean = entry.flipHorizontal;
					ImGui.Checkbox("Horizontal flip", &boolean);
					ImGui.Text(format!"Priority: %s"(entry.priority));
					boolean = size;
					ImGui.Checkbox("Use alt size", &boolean);
					ImGui.EndDisabled();
				});
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Palettes")) {
				showPalette(cast(ColourFormat[])(cgram[]), 16);
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Layers")) {
				const screenRegisters = [BG1SC, BG2SC, BG3SC, BG4SC];
				const screenRegisters2 = [BG12NBA & 0xF, BG12NBA >> 4, BG34NBA & 0xF, BG34NBA >> 4];
				static foreach (layer, label; ["BG1", "BG2", "BG3", "BG4"]) {{
					if (ImGui.TreeNode(label)) {
						ImGui.Text(format!"Tilemap address: $%04X"((screenRegisters[layer] & 0xFC) << 8));
						ImGui.Text(format!"Tile base address: $%04X"(screenRegisters2[layer] << 12));
						ImGui.Text(format!"Size: %s"(["32x32", "64x32", "32x64", "64x64"][screenRegisters[layer] & 3]));
						ImGui.Text(format!"Tile size: %s"(["8x8", "16x16"][!!(BGMODE >> (4 + layer))]));
						if (layer == 2) {
							ImGui.BeginDisabled();
							bool boolean = !!((BGMODE >> 3) & 1);
							ImGui.Checkbox("Priority", &boolean);
							ImGui.EndDisabled();
						}
						//disabledCheckbox("Mosaic Enabled", !!((MOSAIC >> layer) & 1));
						ImGui.TreePop();
					}
				}}
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("VRAM")) {
				static void* surface;
				drawZoomableTiles(cast(Intertwined4BPP[])vram, cast(ColourFormat[16][])cgram, video, surface);
				ImGui.EndTabItem();
			}
			ImGui.EndTabBar();
		}
	}
	public void drawFrame(Array2D!ColourFormat texture) const {
		assert(texture.stride == 512);
		texture[] = getFrameData();
	}
	ColourFormat[] getFrameData() const {
		ColourFormat* rawdata = cast(ColourFormat*)libsfcppu_drawFrame(&this);
		return rawdata[ImgW * 16 .. ImgW * (ImgH + 16)];
	}
}

mixin(makeDynloadFns("LibSFCPPU", makeLibPaths(["libsfcppu"]), ["replatform64.snes.bsnes.renderer"]));

mixin(joinFnBinds!(false)((){
	FnBind[] ret = [
		{q{bool}, q{libsfcppu_init}, q{}},
		{q{ushort*}, q{libsfcppu_drawFrame}, q{const(SnesDrawFrameData)* d}},
	];
	return ret;
}()));

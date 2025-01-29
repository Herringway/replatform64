module replatform64.ui;


public import imgui.hexeditor;
public import imgui.spinner;

// can't just publicly import this due to it publicly importing core.stdc.* symbols...
static import d_imgui.imgui_h;
private import std.algorithm.comparison;
static foreach (idx, T; __traits(allMembers, d_imgui.imgui_h)) {
	static if (__traits(compiles, __traits(parent, __traits(getMember, d_imgui.imgui_h, T))) && __traits(isModule, __traits(parent, __traits(getMember, d_imgui.imgui_h, T)))) {
		static if ((__traits(parent, __traits(getMember, d_imgui.imgui_h, T)).stringof != "string") && !T.among("memcpy", "memset", "sizeof", "memcmp", "strlen", "strcmp", "NULL")) {
			mixin("public alias ", __traits(allMembers, d_imgui.imgui_h)[idx], " = d_imgui.imgui_h.", __traits(allMembers, d_imgui.imgui_h)[idx], ";");
		}
	}
}

public import ImGui = d_imgui;

public import replatform64.ui.common;

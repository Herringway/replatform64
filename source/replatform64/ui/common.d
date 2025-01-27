module replatform64.ui.common;

import std.traits;

import replatform64.backend.common.interfaces;
import replatform64.ui;
import replatform64.util;

alias DebugFunction = void delegate(const UIState);

struct UIState {
	WindowState window;
	float scaleFactor;
}

void InputEditable(alias var, ImGuiInputTextFlags flags = ImGuiInputTextFlags.None)() {
	static if (hasUDA!(var, DebugState)) {
		enum label = getUDAs!(var, DebugState)[0].label;
	}
	InputEditable!flags(label, var);
}

void InputEditable(E, ImGuiInputTextFlags flags = ImGuiInputTextFlags.None, T)(string label, ref T value) {
	E e = cast(E)value;
	InputEditable!flags(label, e);
	value = cast(T)e;
}
void InputEditable(ImGuiInputTextFlags flags = ImGuiInputTextFlags.None, V...)(string label, ref V values) {
	if (auto result = InputEditableR!flags(label, values)) {
		values = result.values;
	}
}
void InputEditableReadOnly(E, ImGuiInputTextFlags flags = ImGuiInputTextFlags.None, T)(string label, const T value) {
	E e = cast(E)value;
	InputEditableReadonly!flags(label, e);
	value = cast(T)e;
}
void InputEditableReadOnly(ImGuiInputTextFlags flags = ImGuiInputTextFlags.None, V...)(string label, const V values) {
	InputEditableReadonlyR!flags(label, values);
}
IMGUIValueChanged!V InputEditableR(ImGuiInputTextFlags flags = ImGuiInputTextFlags.None, V...)(string label, V value) {
	IMGUIValueChanged!V result;
	result.values = value;
	ImGui.BeginGroup();
	ImGui.PushID(label);
	ImGui.PushMultiItemsWidths(V.length, ImGui.CalcItemWidth());
	static foreach (i, T; V) {{
		ImGui.PushID(i);
		static if (is(T == float)) {
			if (ImGui.InputFloat("##v", &value[i], flags)) {
				result.values[i] = value[i];
				result.changed = true;
			}
		} else static if (is(T == enum)) { //enum type
			import std.conv : text;
			import std.traits : EnumMembers;
			if (ImGui.BeginCombo("##v", value[i].text)) {
				static foreach (e; EnumMembers!T) {
					if (ImGui.Selectable(e.text, e == value[i])) {
						result.values[i] = e;
						result.changed = true;
					}
				}
				ImGui.EndCombo();
			}
		} else static if (is(T : const(char)[])) { // strings
			if (value[i][0] == char.init) {
				value[i][] = 0;
			}
			if (ImGui.InputText("##v", value[i][])) {
				result.values[i] = value[i];
				result.changed = true;
			}
		} else { //integer type
			int tmp = value[i];
			if (ImGui.InputInt("##v", &tmp, flags)) {
				result.values[i] = cast(T)tmp;
				result.changed = true;
			}
		}
		ImGui.SameLine();
		ImGui.PopID();
		ImGui.PopItemWidth();
	}}
	ImGui.PopID();
	ImGui.Text(label);
	ImGui.EndGroup();
	return result;
}

bool InputSlider(T)(string label, ref T value, T min = T.min, T max = T.max, ImGuiSliderFlags flags = ImGuiSliderFlags.None) {
	static if (is(T == float)) {
		return ImGui.SliderFloat(label, &value, min, max, flags: flags);
	} else static if (is(T : int)) {
		int val = value;
		const ret = ImGui.SliderInt(label, &val, min, max, flags: flags);
		if (ret) {
			value = cast(T)val;
		}
		return ret;
	}
}

void InputEditableReadonlyR(ImGuiInputTextFlags flags = ImGuiInputTextFlags.None, V...)(string label, V value) {
	ImGui.BeginGroup();
	ImGui.PushID(label);
	ImGui.PushMultiItemsWidths(V.length, ImGui.CalcItemWidth());
	static foreach (i, T; V) {{
		ImGui.PushID(i);
		static if (is(T == float)) {
			ImGui.InputFloat("##v", &value[i], flags);
		} else static if (is(T == enum)) { //enum type
			import std.conv : text;
			import std.traits : EnumMembers;
			if (ImGui.BeginCombo("##v", value[i].text)) {
				static foreach (e; EnumMembers!T) {
					ImGui.Selectable(e.text, e == value[i]);
				}
				ImGui.EndCombo();
			}
		} else static if (is(T : const(char)[])) { // strings
			if (value[i][0] == char.init) {
				value[i][] = 0;
			}
			ImGui.InputText("##v", value[i][]);
		} else { //integer type
			int tmp = value[i];
			ImGui.InputInt("##v", &tmp, flags);
		}
		ImGui.SameLine();
		ImGui.PopID();
		ImGui.PopItemWidth();
	}}
	ImGui.PopID();
	ImGui.Text(label);
	ImGui.EndGroup();
}

struct IMGUIValueChanged(T...) {
	T values;
	private bool changed;
	alias values this;
	bool opCast(T: bool)() const @safe pure {
		return changed;
	}
}

bool imguiAteKeyboard() {
	const io = &ImGui.GetIO();
	return io.WantCaptureKeyboard;
}

MemoryEditor defaultMemoryEditorSettings(string filename) {
	MemoryEditor editor;
	editor.Dumpable = true;
	editor.DumpFile = filename;
	return editor;
}

void registerBit(string label, ref ubyte register, ubyte offset) {
	bool boolean = !!(register & (1 << offset));
	if (ImGui.Checkbox(label, &boolean)) {
		register = cast(ubyte)((register & ~(1 << offset)) | (boolean << offset));
	}
}
void registerBitSel(size_t bits = 1, size_t opts = 1 << bits)(string label, ref ubyte register, ubyte offset, string[opts] labels) {
	const mask = (((1 << bits) - 1) << offset);
	size_t idx = (register & mask) >> offset;
	if (ImGui.BeginCombo(label, labels[idx])) {
		foreach (i, itemLabel; labels) {
			if (ImGui.Selectable(itemLabel, i == idx)) {
				register = cast(ubyte)((register & ~mask) | (i << offset));
			}
		}
		ImGui.EndCombo();
	}
}

void showPalette(T)(T[] palettes, uint entries) {
	static if (is(T : RGB555)) {
		enum maxChannel = 31.0;
	} else {
		enum maxChannel = 255.0;
	}
	import std.format : format;
	import std.range : chunks, enumerate;
	foreach (idx, ref palette; palettes[].chunks(entries).enumerate) {
		ImGui.SeparatorText(format!"Palette %d"(idx));
		foreach (i, ref colour; palette) {
			ImGui.PushID(cast(int)i);
			const c = ImVec4(colour.red / maxChannel, colour.green / maxChannel, colour.blue / maxChannel, 1.0);
			ImGui.Text("$%06X", colour.value);
			ImGui.SameLine();
			if (ImGui.ColorButton("##colour", c, ImGuiColorEditFlags.None, ImVec2(40, 40))) {
				// TODO: colour picker
			}
			if (i + 1 < palette.length) {
				ImGui.SameLine();
			}
			ImGui.PopID();
		}
	}
}

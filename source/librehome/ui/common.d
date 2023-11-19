module librehome.ui.common;

import d_imgui.imgui_h;
import ImGui = d_imgui;

struct UIState {
	uint width;
	uint height;
	uint x;
	uint y;
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

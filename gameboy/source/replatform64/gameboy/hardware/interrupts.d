module replatform64.gameboy.hardware.interrupts;

import replatform64.gameboy.hardware.registers;
import replatform64.dumping;
import replatform64.ui;

alias InterruptFunction = void function();

struct Interrupts {
	@Skip InterruptFunction vblank = {};
	@Skip InterruptFunction stat = {};
	@Skip InterruptFunction timer = {};
	@Skip InterruptFunction serial = {};
	@Skip InterruptFunction joypad = {};
	private bool ime;
	private ubyte ie;
	private ubyte if_;
	void writeRegister(ushort addr, ubyte value) {
		if (addr == Register.IE) {
			ie = value;
		} else if (addr == Register.IF) {
			if_ = value;
			if (ime) {
				checkRunInterrupt!vblank(InterruptFlag.vblank);
				checkRunInterrupt!stat(InterruptFlag.lcd);
				checkRunInterrupt!timer(InterruptFlag.timer);
				checkRunInterrupt!serial(InterruptFlag.serial);
				checkRunInterrupt!joypad(InterruptFlag.joypad);
			}
		} else {
			assert(0, "Invalid register");
		}
	}
	ubyte readRegister(ushort addr) const @safe pure {
		if (addr == Register.IE) {
			return ie;
		} else if (addr == Register.IF) {
			return if_;
		} else {
			assert(0, "Invalid register");
		}
	}
	void setInterrupts(bool value) @safe pure {
		ime = value;
	}
	private void checkRunInterrupt(alias interrupt)(InterruptFlag flag) {
		if ((ie & flag) == (if_ & flag) && ((ie & flag) == flag)) {
			ime = false;
			scope(exit) ime = true;
			assert(interrupt);
			interrupt();
			if_ &= ~flag;
		}
	}
	void debugUI(UIState state) {
		if (ImGui.TreeNode("IE", "IE: %02X", ie)) {
			registerBit("VBlank", ie, 0);
			ImGui.SetItemTooltip("VBlank interrupts enabled");
			registerBit("Stat", ie, 1);
			ImGui.SetItemTooltip("STAT interrupts enabled");
			registerBit("Timer", ie, 2);
			ImGui.SetItemTooltip("Timer interrupts enabled");
			registerBit("Serial", ie, 3);
			ImGui.SetItemTooltip("Serial interrupts enabled");
			registerBit("Joypad", ie, 4);
			ImGui.SetItemTooltip("Joypad interrupts enabled");
			ImGui.TreePop();
		}
		if (ImGui.TreeNode("IF", "IF: %02X", if_)) {
			registerBit("VBlank", if_, 0);
			ImGui.SetItemTooltip("VBlank interrupt requested");
			registerBit("Stat", if_, 1);
			ImGui.SetItemTooltip("STAT interrupt requested");
			registerBit("Timer", if_, 2);
			ImGui.SetItemTooltip("Timer interrupt requested");
			registerBit("Serial", if_, 3);
			ImGui.SetItemTooltip("Serial interrupt requested");
			registerBit("Joypad", if_, 4);
			ImGui.SetItemTooltip("Joypad interrupt requested");
			ImGui.TreePop();
		}
		bool temp;
		ImGui.BeginDisabled();
		temp = ime;
		ImGui.Checkbox("Interrupts enabled", &temp);
		temp = vblank !is null;
		ImGui.Checkbox("VBlank interrupt set up", &temp);
		temp = stat !is null;
		ImGui.Checkbox("STAT interrupt set up", &temp);
		temp = timer !is null;
		ImGui.Checkbox("Timer interrupt set up", &temp);
		temp = serial !is null;
		ImGui.Checkbox("Serial interrupt set up", &temp);
		temp = joypad !is null;
		ImGui.Checkbox("Joypad interrupt set up", &temp);
		ImGui.EndDisabled();
	}
}

unittest {
	import std.exception : assertThrown;
	static int runCount;
	static void runMe() { runCount++; }
	static void dontRunMe() { assert(0, "This shouldn't run!"); }
	with(Interrupts()) { // run interrupts if set up
		setInterrupts(true);
		vblank = &runMe;
		writeRegister(Register.IE, InterruptFlag.vblank);
		writeRegister(Register.IF, InterruptFlag.vblank);
		assert((readRegister(Register.IF) & InterruptFlag.vblank) == 0);
		assert(runCount == 1);
		runCount = 0;
	}
	with(Interrupts()) { // make sure it doesn't run interrupts that aren't set
		setInterrupts(true);
		writeRegister(Register.IE, InterruptFlag.vblank);
		writeRegister(Register.IF, InterruptFlag.vblank);
		assert(runCount == 0);
	}
	with(Interrupts()) { // don't run interrupts if all are disabled
		setInterrupts(false);
		vblank = &dontRunMe;
		writeRegister(Register.IE, InterruptFlag.vblank);
		writeRegister(Register.IF, InterruptFlag.vblank);
		assert((readRegister(Register.IF) & InterruptFlag.vblank) != 0);
	}
	with(Interrupts()) { // don't run disabled interrupts
		setInterrupts(true);
		vblank = &dontRunMe;
		writeRegister(Register.IF, InterruptFlag.vblank);
		assert((readRegister(Register.IF) & InterruptFlag.vblank) != 0);
	}
}

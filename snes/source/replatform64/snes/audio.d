module replatform64.snes.audio;

import replatform64.backend.common;
import replatform64.ui;
import replatform64.util;

import spc700;
import nspcplay;

import std.algorithm.iteration;
import std.array;
import std.conv;
import std.range;

alias HLEWriteCallback = void delegate(ubyte port, ubyte value, AudioBackend backend);
alias HLEReadCallback = ubyte delegate(ubyte port);

struct SPC700Emulated {
	SNES_SPC snes_spc;
	SPC_Filter filter;
	ubyte[65536][] songs;
	bool initialized;
	void delegate(scope ref SPC700Emulated spc, ubyte port, ubyte value) writePortCallback;
	ubyte delegate(scope ref SPC700Emulated spc, ubyte port) readPortCallback;
	void initialize() {
		snes_spc.initialize();
		filter = SPC_Filter();
	}
	void waitUntilReady() {
		writePort(1, 0xFF);
		while (true) {
			snes_spc.skip(2);
			if (readPort(1) == 0) {
				return;
			}
		}
	}
	void load(ubyte[] buffer, ushort start) {
		initialized = false;
		snes_spc.load_buffer(buffer, start);
		snes_spc.clear_echo();
		filter.clear();
		waitUntilReady();
		initialized = true;
	}
	void writePort(ubyte id, ubyte value) {
		snes_spc.write_port_now(id, value);
	}
	void writeCallback(ubyte id, ubyte value, AudioBackend) {
		if (writePortCallback) {
			writePortCallback(this, id, value);
		} else {
			writePort(id, value);
		}
	}
	ubyte readPort(ubyte id) {
		return cast(ubyte)snes_spc.read_port_now(id);
	}
	ubyte readCallback(ubyte id) {
		if (readPortCallback) {
			return readPortCallback(this, id);
		} else {
			return readPort(id);
		}
	}
	static void callback(SPC700Emulated* user, ubyte[] buffer) {
		user.callback(cast(short[])buffer);
	}
	void callback(short[] buffer) {
		if (!initialized) {
			return;
		}
		// Play into buffer
		snes_spc.play(buffer);

		// Filter samples
		filter.run(buffer);
	}
	ubyte[] aram() => snes_spc.m.ram.ram[];
	void debugging(const UIState uiState) {
		if (ImGui.BeginTable("Voices", 8)) {
			foreach (header; ["VOLL", "VOLR", "PITCH", "SRCN", "ADSR", "GAIN", "ENVX", "OUTX"]) {
				ImGui.TableSetupColumn(header);
			}
			ImGui.TableHeadersRow();
			foreach (i, voice; snes_spc.dsp.m.voices) {
				ImGui.TableNextColumn();
				ImGui.Text("%02X", voice.regs[0]);
				ImGui.TableNextColumn();
				ImGui.Text("%02X", voice.regs[1]);
				ImGui.TableNextColumn();
				ImGui.Text("%04X", (cast(ushort[])(voice.regs[2 .. 4]))[0]);
				ImGui.TableNextColumn();
				ImGui.Text("%02X", voice.regs[4]);
				ImGui.TableNextColumn();
				ImGui.Text("%04X", (cast(ushort[])(voice.regs[5 .. 7]))[0]);
				ImGui.TableNextColumn();
				ImGui.Text("%02X", voice.regs[7]);
				ImGui.TableNextColumn();
				ImGui.Text("%02X", voice.regs[8]);
				ImGui.TableNextColumn();
				ImGui.Text("%02X", voice.regs[9]);
			}
			ImGui.EndTable();
		}
	}
}

struct NSPC {
	NSPCPlayer player;
	bool initialized;
	void delegate(scope ref NSPC nspc, ubyte port, ubyte value, AudioBackend backend) writePortCallback;
	ubyte delegate(scope ref NSPC nspc, ubyte port) readPortCallback;
	AudioBackend backend;
	void changeSong(const Song track) {
		initialized = false;
		player.loadSong(track);
		player.initialize();
		player.play();
		initialized = true;
	}
	void stop() {
		player.stop();
	}
	static void callback(NSPC* user, ubyte[] stream) {
		if (user.initialized) {
			user.player.fillBuffer(cast(short[2][])stream);
		}
	}
	void writeCallback(ubyte port, ubyte value, AudioBackend backend) {
		if (writePortCallback !is null) {
			writePortCallback(this, port, value, backend);
		}
	}
	ubyte readCallback(ubyte port) {
		if (readPortCallback !is null) {
			return readPortCallback(this, port);
		}
		return 0;
	}
	ubyte[] aram() => null;
	void debugging(const UIState uiState) {
		if ((player.currentSong !is null) && ImGui.BeginTabBar("SongStateTabs")) {
			if (ImGui.BeginTabItem("Song")) {
				InputEditable("Tempo", player.state.tempo.current);
				InputEditable("Volume", player.state.volume.current);
				InputSlider("Transpose", player.state.transpose);
				InputSlider("Fade ticks", player.state.fadeTicks);
				InputSlider("Percussion base", player.state.percussionBase, 0, cast(ubyte)player.currentSong.instruments.length);
				InputSlider("Repeat count", player.state.repeatCount);
				InputSlider("Phrase counter", player.state.phraseCounter, 0, cast(ubyte)player.currentSong.order.length);
				ImGui.EndTabItem();
			}
			if (ImGui.BeginTabItem("Channels")) {
				if (ImGui.BeginTable("Channels_", 9)) {
					int counter;
					void addTableItem(string field)(string label) {
						ImGui.TableNextColumn();
						ImGui.TextUnformatted(label);
						foreach (ref channel; player.state.channels[0 .. 8]) {
							alias FieldType = typeof(__traits(getMember, channel, field));
							ImGui.TableNextColumn();
							ImGui.PushID(counter++);
							static if (is(FieldType == bool)) {
								ImGui.Checkbox("", &__traits(getMember, channel, field));
							} else static if (is(FieldType : int)) {
								int value = __traits(getMember, channel, field);
								if (ImGui.InputInt("", &value)) {
									__traits(getMember, channel, field) = cast(FieldType)value;
								}
							}
							ImGui.PopID();
						}
					}
					enum headers = iota(8).map!(x => x.text).array;
					ImGui.TableSetupColumn("");
					foreach (header; headers) {
						ImGui.TableSetupColumn(header);
					}
					ImGui.TableHeadersRow();
					addTableItem!"enabled"("Enabled");
					addTableItem!"instrument"("Instrument");
					addTableItem!"sampleID"("Sample");
					addTableItem!"noteLength"("Note length");
					addTableItem!"finetune"("Fine tune");
					addTableItem!"transpose"("Transpose");
					addTableItem!"totalVolume"("Volume");
					addTableItem!"leftVolume"("Volume (L)");
					addTableItem!"rightVolume"("Volume (R)");
					addTableItem!"portType"("Portamento type");
					addTableItem!"portStart"("Portamento start");
					addTableItem!"portLength"("Portamento length");
					addTableItem!"portRange"("Portamento range");
					addTableItem!"vibratoStart"("Vibrato start");
					addTableItem!"vibratoSpeed"("Vibrato speed");
					addTableItem!"vibratoMaxRange"("Vibrato max");
					addTableItem!"vibratoFadeIn"("Vibrato fade in");
					addTableItem!"tremoloStart"("Tremolo start");
					addTableItem!"tremoloSpeed"("Tremolo speed");
					addTableItem!"tremoloRange"("Tremolo range");
					ImGui.EndTable();
				}
				ImGui.EndTabItem();
			}
			ImGui.EndTabBar();
		}
	}
}

ubyte[65536] loadNSPCBuffer(scope const ubyte[] file) @safe {
	import std.bitmanip : read;
	ubyte[65536] buffer;
	const remaining = loadAllSubpacks(buffer[], file[NSPCFileHeader.sizeof .. $]);
	return buffer;
}

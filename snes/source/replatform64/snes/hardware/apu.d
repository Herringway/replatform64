module replatform64.snes.hardware.apu;

import replatform64.backend.common;
import replatform64.snes.hardware;
import replatform64.ui;
import replatform64.util;

import spc700;
import nspcplay;

import std.algorithm.iteration;
import std.array;
import std.conv;
import std.range;

abstract class APU {
	void initialize(AudioBackend) @safe;
	void loadSong(scope const(ubyte)[] data) @safe;
	void writeRegister(ushort addr, ubyte value) @safe;
	ubyte readRegister(ushort addr) @safe;
	void debugUI(const UIState state, VideoBackend backend) @safe;
	void audioCallback(scope ubyte[] buffer) @safe;
	ubyte[] aram() @safe;
	static void audioCallback(scope void* apu, scope ubyte[] buffer) @trusted {
		(cast(APU)apu).audioCallback(buffer);
	}
}

abstract class SPC700Emulated : APU {
	SNES_SPC snes_spc;
	SPC_Filter filter;
	ubyte[65536][] songs;
	bool initialized;
	override void initialize(AudioBackend) @safe {
		snes_spc.initialize();
		filter = SPC_Filter();
	}
	override void loadSong(scope const(ubyte)[] data) @safe {
		ubyte[65536] buffer;
		loadAllSubpacks(buffer[], data[NSPCFileHeader.sizeof .. $]);
		songs ~= buffer;
	}
	void waitUntilReady() @safe {
		writeRegister(Register.APUIO1, 0xFF);
		while (true) {
			snes_spc.skip(2);
			if (readRegister(Register.APUIO1) == 0) {
				return;
			}
		}
	}
	void changeSong(size_t index, ushort start) @safe {
		initialized = false;
		snes_spc.load_buffer(songs[index], start);
		snes_spc.clear_echo();
		filter.clear();
		waitUntilReady();
		initialized = true;
	}
	override void writeRegister(ushort address, ubyte value) {
		snes_spc.write_port_now(cast(ubyte)(address - Register.APUIO0), value);
	}
	override ubyte readRegister(ushort address) {
		return cast(ubyte)snes_spc.read_port_now(cast(ubyte)(address - Register.APUIO0));
	}
	override void audioCallback(scope ubyte[] buffer) @safe {
		if (!initialized) {
			return;
		}
		// Play into buffer
		snes_spc.play(cast(short[])buffer);

		// Filter samples
		filter.run(cast(short[])buffer);
	}
	override ubyte[] aram() => snes_spc.m.ram[];
	override void debugUI(const UIState uiState, VideoBackend backend) @trusted {
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

abstract class NSPCBase : APU {
	NSPCPlayer player;
	bool initialized;
	AudioBackend backend;
	Song[] loadedSongs;
	override void initialize(AudioBackend backend) @safe {
		this.backend = backend;
	}
	void changeSong(size_t track) @safe {
		initialized = false;
		player.loadSong(loadedSongs[track]);
		player.initialize();
		player.play();
		initialized = true;
	}
	override void loadSong(scope const(ubyte)[] data) @safe {
		loadedSongs ~= loadNSPCFile(data);
	}
	void stop() @safe {
		player.stop();
	}
	override void audioCallback(scope ubyte[] stream) @safe {
		if (initialized) {
			player.fillBuffer(cast(short[2][])stream);
		}
	}
	override ubyte[] aram() => null;
	override void debugUI(const UIState uiState, VideoBackend backend) @trusted {
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

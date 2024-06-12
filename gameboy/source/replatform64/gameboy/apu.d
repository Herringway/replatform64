module replatform64.gameboy.apu;

import std.logger;
import std.string;

/*
Copyright (c) 2017 Alex Baines <alex@abaines.me.uk>
Copyright (c) 2019 Mahyar Koshkouei <mk@deltabeard.com>
Copyright (c) 2023 Cameron Ross

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
 */

import std.algorithm.comparison : max, min;

enum DMG_CLOCK_FREQ_U = 4194304;

enum AUDIO_ADDR_COMPENSATION= 0xFF10;

enum VOL_INIT_MAX = short.max / 8;
enum VOL_INIT_MIN = short.min / 8;

/* Handles time keeping for sound generation.
 * FREQ_INC_REF must be > 0
 * to avoid a division by zero error.
 * Using a square of 2 simplifies calculations. */
enum FREQ_INC_REF = 16;

enum MAX_CHAN_VOLUME = 15;

struct chan_len_ctr {
	ubyte load;
	bool enabled;
	uint counter;
	uint inc;
}

struct chan_vol_env {
	ubyte step;
	bool up;
	uint counter;
	uint inc;
}

struct chan_freq_sweep {
	ushort freq;
	ubyte rate;
	ubyte shift;
	bool up;
	uint counter;
	uint inc;
}

private struct Channel {
	bool enabled;
	bool powered;
	bool on_left;
	bool on_right;
	bool muted;

	ubyte volume;
	ubyte volume_init;

	ushort freq;
	uint freq_counter;
	uint freq_inc;

	short val;

	chan_len_ctr len;
	chan_vol_env env;
	chan_freq_sweep sweep;

	static struct SquareChannel {
		ubyte duty;
		ubyte duty_counter;
	}
	static struct NoiseChannel {
		ushort lfsr_reg;
		ubyte lfsr_wide;
		ubyte lfsr_div;
	}
	static struct WaveChannel {
		ubyte sample;
	}
	SquareChannel square;
	NoiseChannel noise;
	WaveChannel wave;
}
struct APU {
	/// Memory holding audio registers between 0xFF10 and 0xFF3F inclusive.
	private ubyte[0xFF3F - 0xFF10 + 1] audio_mem;
	Channel[4] chans;

	private int vol_l, vol_r;
	uint sampleRate = 32000;

	private void set_note_freq(ref Channel c, const uint freq) nothrow @safe pure {
		/* Lowest expected value of freq is 64. */
		c.freq_inc = freq * FREQ_INC_REF;
	}

	private void chan_enable(const ubyte i, const bool enable) nothrow @safe pure {
		ubyte val;

		chans[i].enabled = enable;
		val = (audio_mem[0xFF26 - AUDIO_ADDR_COMPENSATION] & 0x80) | (chans[3].enabled << 3) | (chans[2].enabled << 2) | (chans[1].enabled << 1) | (chans[0].enabled << 0);

		audio_mem[0xFF26 - AUDIO_ADDR_COMPENSATION] = val;
		//audio_mem[0xFF26 - AUDIO_ADDR_COMPENSATION] |= 0x80 | ((ubyte)enable) << i;
	}

	private void update_env(ref Channel c) nothrow @safe pure {
		c.env.counter += c.env.inc;

		while (c.env.counter > sampleRate * FREQ_INC_REF) {
			if (c.env.step) {
				c.volume += c.env.up ? 1 : -1;
				if (c.volume == 0 || c.volume == MAX_CHAN_VOLUME) {
					c.env.inc = 0;
				}
				c.volume = cast(ubyte)max(0, min(MAX_CHAN_VOLUME, c.volume));
			}
			c.env.counter -= sampleRate * FREQ_INC_REF;
		}
	}

	private void update_len(size_t channel) nothrow @safe pure {
		if (!chans[channel].len.enabled) {
			return;
		}

		chans[channel].len.counter += chans[channel].len.inc;
		if (chans[channel].len.counter > sampleRate * FREQ_INC_REF) {
			chan_enable(cast(ubyte)channel, 0);
			chans[channel].len.counter = 0;
		}
	}

	private bool update_freq(ref Channel c, ref uint pos) nothrow @safe pure {
		//import std.logger; debug infof("%s", pos);
		uint inc = c.freq_inc - pos;
		c.freq_counter += inc;

		if (c.freq_counter > sampleRate * FREQ_INC_REF) {
			//import std.logger; debug infof("new frame?");
			pos = c.freq_inc - (c.freq_counter - sampleRate * FREQ_INC_REF);
			c.freq_counter = 0;
			return true;
		} else {
			pos = c.freq_inc;
			return false;
		}
	}

	private void update_sweep(ref Channel c) nothrow @safe pure {
		c.sweep.counter += c.sweep.inc;

		while (c.sweep.counter > sampleRate * FREQ_INC_REF) {
			if (c.sweep.shift) {
				ushort inc = (c.sweep.freq >> c.sweep.shift);
				if (!c.sweep.up) {
					inc *= -1;
				}

				c.freq += inc;
				if (c.freq > 2047) {
					c.enabled = 0;
				} else {
					set_note_freq(c,
						DMG_CLOCK_FREQ_U / ((2048 - c.freq)<< 5));
					c.freq_inc *= 8;
				}
			} else if (c.sweep.rate) {
				c.enabled = 0;
			}
			c.sweep.counter -= sampleRate * FREQ_INC_REF;
		}
	}

	private void update_square(short[2][] samples, const bool ch2) nothrow @safe pure {
		uint freq;
		Channel* c = &chans[ch2];

		if (!c.powered || !c.enabled) {
			return;
		}

		freq = DMG_CLOCK_FREQ_U / ((2048 - c.freq) << 5);
		set_note_freq(*c, freq);
		c.freq_inc *= 8;

		for (ushort i = 0; i < samples.length; i++) {
			update_len(ch2);

			if (!c.enabled) {
				continue;
			}

			update_env(*c);
			if (!ch2) {
				update_sweep(*c);
			}

			uint pos = 0;
			uint prev_pos = 0;
			int sample = 0;

			while (update_freq(*c, pos)) {
				c.square.duty_counter = (c.square.duty_counter + 1) & 7;
				sample += ((pos - prev_pos) / c.freq_inc) * c.val;
				c.val = (c.square.duty & (1 << c.square.duty_counter)) ?
					VOL_INIT_MAX / MAX_CHAN_VOLUME :
					VOL_INIT_MIN / MAX_CHAN_VOLUME;
				prev_pos = pos;
			}

			if (c.muted) {
				continue;
			}

			sample += c.val;
			sample *= c.volume;
			sample /= 4;

			samples[i][0] += sample * c.on_left * vol_l;
			samples[i][1] += sample * c.on_right * vol_r;
		}
	}

	private ubyte wave_sample(const uint pos, const uint volume) nothrow @safe pure {
		ubyte sample;

		sample = audio_mem[(0xFF30 + pos / 2) - AUDIO_ADDR_COMPENSATION];
		if (pos & 1) {
			sample &= 0xF;
		} else {
			sample >>= 4;
		}
		return volume ? (sample >> (volume - 1)) : 0;
	}

	private void update_wave(short[2][] samples) nothrow @safe pure {
		uint freq;
		Channel *c = &chans[2];

		if (!c.powered || !c.enabled) {
			return;
		}

		freq = (DMG_CLOCK_FREQ_U / 64) / (2048 - c.freq);
		set_note_freq(*c, freq);

		c.freq_inc *= 32;

		for (ushort i = 0; i < samples.length; i++) {
			update_len(2);

			if (!c.enabled) {
				continue;
			}

			uint pos = 0;
			uint prev_pos = 0;
			int sample = 0;

			c.wave.sample = wave_sample(c.val, c.volume);

			while (update_freq(*c, pos)) {
				c.val = (c.val + 1) & 31;
				sample += ((pos - prev_pos) / c.freq_inc) * (cast(int)c.wave.sample - 8) * (short.max/64);
				c.wave.sample = wave_sample(c.val, c.volume);
				prev_pos = pos;
			}

			sample += (cast(int)c.wave.sample - 8) * (int)(short.max/64);

			if (c.volume == 0) {
				continue;
			}

			{
				/* First element is unused. */
				short[] div = [ short.max, 1, 2, 4 ];
				sample = sample / (div[c.volume]);
			}

			if (c.muted) {
				continue;
			}

			sample /= 4;

			samples[i][0] += sample * c.on_left * vol_l;
			samples[i][1] += sample * c.on_right * vol_r;
		}
	}

	private void update_noise(short[2][] samples) nothrow @safe pure {
		Channel *c = &chans[3];

		if (!c.powered) {
			return;
		}

		{
			const uint[] lfsr_div_lut = [
				8, 16, 32, 48, 64, 80, 96, 112
			];
			uint freq;

			freq = DMG_CLOCK_FREQ_U / (lfsr_div_lut[c.noise.lfsr_div] << c.freq);
			set_note_freq(*c, freq);
		}

		if (c.freq >= 14) {
			c.enabled = 0;
		}

		for (ushort i = 0; i < samples.length; i++) {
			update_len(3);

			if (!c.enabled) {
				continue;
			}

			update_env(*c);

			uint pos = 0;
			uint prev_pos = 0;
			int sample = 0;

			while (update_freq(*c, pos)) {
				c.noise.lfsr_reg = cast(ushort)((c.noise.lfsr_reg << 1) | (c.val >= VOL_INIT_MAX/MAX_CHAN_VOLUME));

				if (c.noise.lfsr_wide) {
					c.val = !(((c.noise.lfsr_reg >> 14) & 1) ^ ((c.noise.lfsr_reg >> 13) & 1)) ?
						VOL_INIT_MAX / MAX_CHAN_VOLUME :
						VOL_INIT_MIN / MAX_CHAN_VOLUME;
				} else {
					c.val = !(((c.noise.lfsr_reg >> 6) & 1) ^ ((c.noise.lfsr_reg >> 5) & 1)) ?
						VOL_INIT_MAX / MAX_CHAN_VOLUME :
						VOL_INIT_MIN / MAX_CHAN_VOLUME;
				}

				sample += ((pos - prev_pos) / c.freq_inc) * c.val;
				prev_pos = pos;
			}

			if (c.muted) {
				continue;
			}

			sample += c.val;
			sample *= c.volume;
			sample /= 4;

			samples[i][0] += sample * c.on_left * vol_l;
			samples[i][1] += sample * c.on_right * vol_r;
		}
	}

	private void chan_trigger(ubyte i) nothrow @safe pure {
		Channel *c = &chans[i];

		chan_enable(i, 1);
		c.volume = c.volume_init;

		// volume envelope
		{
			ubyte val = audio_mem[(0xFF12 + (i * 5)) - AUDIO_ADDR_COMPENSATION];

			c.env.step = val & 0x07;
			c.env.up = val & 0x08 ? 1 : 0;
			c.env.inc = c.env.step ?
				(FREQ_INC_REF * 64uL) / (cast(uint)c.env.step) :
				(8uL * FREQ_INC_REF);
			c.env.counter = 0;
		}

		// freq sweep
		if (i == 0) {
			ubyte val = audio_mem[0xFF10 - AUDIO_ADDR_COMPENSATION];

			c.sweep.freq = c.freq;
			c.sweep.rate = (val >> 4) & 0x07;
			c.sweep.up = !(val & 0x08);
			c.sweep.shift = (val & 0x07);
			c.sweep.inc = c.sweep.rate ? ((128 * FREQ_INC_REF) / c.sweep.rate) : 0;
			c.sweep.counter = sampleRate * FREQ_INC_REF;
		}

		int len_max = 64;

		if (i == 2) { // wave
			len_max = 256;
			c.val = 0;
		} else if (i == 3) { // noise
			c.noise.lfsr_reg = 0xFFFF;
			c.val = VOL_INIT_MIN / MAX_CHAN_VOLUME;
		}

		c.len.inc = (256 * FREQ_INC_REF) / (len_max - c.len.load);
		c.len.counter = 0;
	}

	/**
	* Read audio register.
	 * Params:
	 *  addr = Address of audio register. Must be 0xFF10 <= addr <= 0xFF3F. This is not checked in this function.
	 * Returns: Byte at address.
	 */
	ubyte readRegister(const ushort addr) nothrow @safe pure {
		static immutable ubyte[] ortab = [
			0x80, 0x3f, 0x00, 0xff, 0xbf,
			0xff, 0x3f, 0x00, 0xff, 0xbf,
			0x7f, 0xff, 0x9f, 0xff, 0xbf,
			0xff, 0xff, 0x00, 0x00, 0xbf,
			0x00, 0x00, 0x70,
			0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
			0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
			0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
		];

		return audio_mem[addr - AUDIO_ADDR_COMPENSATION] | ortab[addr - AUDIO_ADDR_COMPENSATION];
	}

	/**
	 * Write audio register.
	 * Params:
	 *  addr = Address of audio register. Must be 0xFF10 <= addr <= 0xFF3F. This is not checked in this function.
	 *  val = Byte to write at address.
	 */
	void writeRegister(const ushort addr, const ubyte val) nothrow @safe pure {
		/* Find sound channel corresponding to register address. */
		ubyte i;

		debug {
			try {
				import core.runtime;
				auto trace = defaultTraceHandler(null);
				const(char)[] fun;
				foreach (idx, t; trace) {
					if (idx == 0) {
						fun = t;
						break;
					}
				}
				tracef("WRITE: %04X, %02X (%s)", addr, val, fun);
				defaultTraceDeallocator(trace);
			} catch (Exception) {}
		}

		if (addr == 0xFF26) {
			audio_mem[addr - AUDIO_ADDR_COMPENSATION] = val & 0x80;
			// On APU power off, clear all registers apart from wave RAM.
			if ((val & 0x80) == 0) {
				audio_mem[0 .. 0xFF26 - AUDIO_ADDR_COMPENSATION] = 0;
				chans[0].enabled = false;
				chans[1].enabled = false;
				chans[2].enabled = false;
				chans[3].enabled = false;
			}

			return;
		}

		/* Ignore register writes if APU powered off. */
		if (audio_mem[0xFF26 - AUDIO_ADDR_COMPENSATION] == 0x00) {
			return;
		}

		audio_mem[addr - AUDIO_ADDR_COMPENSATION] = val;
		i = cast(ubyte)((addr - AUDIO_ADDR_COMPENSATION) / 5);

		switch (addr) {
			case 0xFF12:
			case 0xFF17:
			case 0xFF21:
				chans[i].volume_init = val >> 4;
				chans[i].powered = (val >> 3) != 0;

				// "zombie mode" stuff, needed for Prehistorik Man and probably
				// others
				if (chans[i].powered && chans[i].enabled) {
					if ((chans[i].env.step == 0 && chans[i].env.inc != 0)) {
						if (val & 0x08) {
							chans[i].volume++;
						} else {
							chans[i].volume += 2;
						}
					} else {
						chans[i].volume = cast(ubyte)(16 - chans[i].volume);
					}

					chans[i].volume &= 0x0F;
					chans[i].env.step = val & 0x07;
				}
				break;
			case 0xFF1C:
				chans[i].volume = chans[i].volume_init = (val >> 5) & 0x03;
				break;
			case 0xFF11:
			case 0xFF16:
			case 0xFF20:
				static immutable ubyte[] duty_lookup = [ 0x10, 0x30, 0x3C, 0xCF ];
				chans[i].len.load = val & 0x3f;
				chans[i].square.duty = duty_lookup[val >> 6];
				break;
			case 0xFF1B:
				chans[i].len.load = val;
				break;
			case 0xFF13:
			case 0xFF18:
			case 0xFF1D:
				chans[i].freq &= 0xFF00;
				chans[i].freq |= val;
				break;
			case 0xFF1A:
				chans[i].powered = (val & 0x80) != 0;
				chan_enable(i, !!(val & 0x80));
				break;
			case 0xFF14:
			case 0xFF19:
			case 0xFF1E:
				chans[i].freq &= 0x00FF;
				chans[i].freq |= ((val & 0x07) << 8);
				goto case;
			case 0xFF23:
				chans[i].len.enabled = val & 0x40 ? 1 : 0;
				if (val & 0x80)
					chan_trigger(i);
				break;
			case 0xFF22:
				chans[3].freq = val >> 4;
				chans[3].noise.lfsr_wide = !(val & 0x08);
				chans[3].noise.lfsr_div = val & 0x07;
				break;
			case 0xFF24:
				vol_l = ((val >> 4) & 0x07);
				vol_r = (val & 0x07);
				break;
			case 0xFF25:
				for (ubyte j = 0; j < 4; j++) {
					chans[j].on_left = (val >> (4 + j)) & 1;
					chans[j].on_right = (val >> j) & 1;
				}
				break;
			default: break;
		}
	}

	void initialize(ushort sampleRate) @safe pure {
		this.sampleRate = sampleRate;
		/* Initialise channels and samples. */
		chans = chans.init;
		chans[0].val = chans[1].val = -1;

		/* Initialise IO registers. */
		{
			static immutable ubyte[] regs_init = [ 0x80, 0xBF, 0xF3, 0xFF, 0x3F, 0xFF, 0x3F, 0x00, 0xFF, 0x3F, 0x7F, 0xFF, 0x9F, 0xFF, 0x3F, 0xFF, 0xFF, 0x00, 0x00, 0x3F, 0x77, 0xF3, 0xF1 ];

			foreach(i, val; regs_init) {
				writeRegister(cast(ushort)(0xFF10 + i), val);
			}
		}

		/* Initialise Wave Pattern RAM. */
		{
			static immutable ubyte[] wave_init = [ 0xac, 0xdd, 0xda, 0x48, 0x36, 0x02, 0xcf, 0x16, 0x2c, 0x04, 0xe5, 0x2c, 0xac, 0xdd, 0xda, 0x48 ];

			foreach (i, val; wave_init) {
				writeRegister(cast(ushort)(0xFF30 + i), val);
			}
		}
	}
}

/**
 * SDL2 style audio callback function.
 */
void audioCallback(void *userdata, ubyte[] stream) {
	auto apu = cast(APU*)userdata;
	short[2][] samples = cast(short[2][])stream;

	stream[] = 0;
	apu.update_square(samples, 0);
	apu.update_square(samples, 1);
	apu.update_wave(samples);
	apu.update_noise(samples);
}

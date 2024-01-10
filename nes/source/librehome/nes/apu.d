module librehome.nes.apu;

import core.stdc.stdint;
import core.stdc.string;
import core.stdc.stdlib;
import core.stdc.math;

enum defaultFrequency = 48000;
enum frameRate = 60;

enum AUDIO_BUFFER_LENGTH = 4096;

immutable ubyte[32] lengthTable = [
	10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14,
	12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30
];

immutable ubyte[8][4] dutyTable = [
	[0, 1, 0, 0, 0, 0, 0, 0],
	[0, 1, 1, 0, 0, 0, 0, 0],
	[0, 1, 1, 1, 1, 0, 0, 0],
	[1, 0, 0, 1, 1, 1, 1, 1]
];

immutable ubyte[32] triangleTable = [
	15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0,
	0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
];

immutable ushort[16] noiseTable = [
	4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068
];

/// Pulse waveform generator.
struct Pulse {
	this(ubyte channel) @safe {
		enabled = false;
		this.channel = channel;
		lengthEnabled = false;
		lengthValue = 0;
		timerPeriod = 0;
		timerValue = 0;
		dutyMode = 0;
		dutyValue = 0;
		sweepReload = false;
		sweepEnabled = false;
		sweepNegate = false;
		sweepShift = 0;
		sweepPeriod = 0;
		sweepValue = 0;
		envelopeEnabled = false;
		envelopeLoop = false;
		envelopeStart = false;
		envelopePeriod = 0;
		envelopeValue = 0;
		envelopeVolume = 0;
		constantVolume = 0;
	}

	void writeControl(ubyte value) @safe {
		dutyMode = (value >> 6) & 3;
		lengthEnabled = ((value >> 5) & 1) == 0;
		envelopeLoop = ((value >> 5) & 1) == 1;
		envelopeEnabled = ((value >> 4) & 1) == 0;
		envelopePeriod = value & 15;
		constantVolume = value & 15;
		envelopeStart = true;
	}

	void writeSweep(ubyte value) @safe {
		sweepEnabled = ((value >> 7) & 1) == 1;
		sweepPeriod = ((value >> 4) & 7) + 1;
		sweepNegate = ((value >> 3) & 1) == 1;
		sweepShift = value & 7;
		sweepReload = true;
	}

	void writeTimerLow(ubyte value) @safe {
		timerPeriod = (timerPeriod & 0xff00) | cast(ushort)value;
	}

	void writeTimerHigh(ubyte value) @safe {
		lengthValue = lengthTable[value >> 3];
		timerPeriod = (timerPeriod & 0xff) | (cast(ushort)(value & 7) << 8);
		envelopeStart = true;
		dutyValue = 0;
	}

	void stepTimer() @safe {
		if (timerValue == 0) {
			timerValue = timerPeriod;
			dutyValue = (dutyValue + 1) % 8;
		} else {
			timerValue--;
		}
	}

	void stepEnvelope() @safe pure {
		if (envelopeStart) {
			envelopeVolume = 15;
			envelopeValue = envelopePeriod;
			envelopeStart = false;
		} else if (envelopeValue > 0) {
			envelopeValue--;
		} else {
			if (envelopeVolume > 0) {
				envelopeVolume--;
			} else if (envelopeLoop) {
				envelopeVolume = 15;
			}
			envelopeValue = envelopePeriod;
		}
	}

	void stepSweep() @safe {
		if (sweepReload) {
			if (sweepEnabled && sweepValue == 0) {
				sweep();
			}
			sweepValue = sweepPeriod;
			sweepReload = false;
		} else if (sweepValue > 0) {
			sweepValue--;
		} else {
			if (sweepEnabled) {
				sweep();
			}
			sweepValue = sweepPeriod;
		}
	}

	void stepLength() @safe {
		if (lengthEnabled && lengthValue > 0) {
			lengthValue--;
		}
	}

	void sweep() @safe {
		ushort delta = timerPeriod >> sweepShift;
		if (sweepNegate) {
			timerPeriod -= delta;
			if (channel == 1) {
				timerPeriod--;
			}
		} else {
			timerPeriod += delta;
		}
	}

	ubyte output() @safe {
		if (!enabled) {
			return 0;
		}
		if (lengthValue == 0) {
			return 0;
		}
		if (dutyTable[dutyMode][dutyValue] == 0) {
			return 0;
		}
		if (timerPeriod < 8 || timerPeriod > 0x7ff) {
			return 0;
		}
		if (envelopeEnabled) {
			return envelopeVolume;
		} else {
			return constantVolume;
		}
	}

private:
	bool enabled;
	ubyte channel;
	bool lengthEnabled;
	ubyte lengthValue;
	ushort timerPeriod;
	ushort timerValue;
	ubyte dutyMode;
	ubyte dutyValue;
	bool sweepReload;
	bool sweepEnabled;
	bool sweepNegate;
	ubyte sweepShift;
	ubyte sweepPeriod;
	ubyte sweepValue;
	bool envelopeEnabled;
	bool envelopeLoop;
	bool envelopeStart;
	ubyte envelopePeriod;
	ubyte envelopeValue;
	ubyte envelopeVolume;
	ubyte constantVolume;
};

/// Triangle waveform generator.
struct Triangle {
	void writeControl(ubyte value) @safe {
		lengthEnabled = ((value >> 7) & 1) == 0;
		counterPeriod = value & 0x7f;
	}

	void writeTimerLow(ubyte value) @safe {
		timerPeriod = (timerPeriod & 0xff00) | cast(ushort)value;
	}

	void writeTimerHigh(ubyte value) @safe {
		lengthValue = lengthTable[value >> 3];
		timerPeriod = (timerPeriod & 0x00ff) | (cast(ushort)(value & 7) << 8);
		timerValue = timerPeriod;
		counterReload = true;
	}

	void stepTimer() @safe {
		if (timerValue == 0) {
			timerValue = timerPeriod;
			if (lengthValue > 0 && counterValue > 0) {
				dutyValue = (dutyValue + 1) % 32;
			}
		} else {
			timerValue--;
		}
	}

	void stepLength() @safe {
		if (lengthEnabled && lengthValue > 0) {
			lengthValue--;
		}
	}

	void stepCounter() @safe {
		if (counterReload) {
			counterValue = counterPeriod;
		} else if (counterValue > 0) {
			counterValue--;
		}
		if (lengthEnabled) {
			counterReload = false;
		}
	}

	ubyte output() @safe {
		if (!enabled) {
			return 0;
		}
		if (lengthValue == 0) {
			return 0;
		}
		if (counterValue == 0) {
			return 0;
		}
		return triangleTable[dutyValue];
	}

private:
	bool enabled = false;
	bool lengthEnabled = false;
	ubyte lengthValue = 0;
	ushort timerPeriod = 0;
	ushort timerValue;
	ubyte dutyValue = 0;
	ubyte counterPeriod = 0;
	ubyte counterValue = 0;
	bool counterReload = false;
}

struct Noise {
	void writeControl(ubyte value) @safe {
		lengthEnabled = ((value >> 5) & 1) == 0;
		envelopeLoop = ((value >> 5) & 1) == 1;
		envelopeEnabled = ((value >> 4) & 1) == 0;
		envelopePeriod = value & 15;
		constantVolume = value & 15;
		envelopeStart = true;
	}

	void writePeriod(ubyte value) @safe {
		mode = (value & 0x80) == 0x80;
		timerPeriod = noiseTable[value & 0x0f];
	}

	void writeLength(ubyte value) @safe {
		lengthValue = lengthTable[value >> 3];
		envelopeStart = true;
	}

	void stepTimer() @safe {
		if (timerValue == 0) {
			timerValue = timerPeriod;
			ubyte shift;
			if (mode) {
				shift = 6;
			} else {
				shift = 1;
			}
			ushort b1 = shiftRegister & 1;
			ushort b2 = (shiftRegister >> shift) & 1;
			shiftRegister >>= 1;
			shiftRegister |= (b1 ^ b2) << 14;
		} else {
			timerValue--;
		}
	}

	void stepEnvelope() @safe {
		if (envelopeStart) {
			envelopeVolume = 15;
			envelopeValue = envelopePeriod;
			envelopeStart = false;
		} else if (envelopeValue > 0) {
			envelopeValue--;
		} else {
			if (envelopeVolume > 0) {
				envelopeVolume--;
			} else if (envelopeLoop) {
				envelopeVolume = 15;
			}
			envelopeValue = envelopePeriod;
		}
	}

	void stepLength() @safe {
		if (lengthEnabled && lengthValue > 0) {
			lengthValue--;
		}
	}

	ubyte output() @safe {
		if (!enabled) {
			return 0;
		}
		if (lengthValue == 0) {
			return 0;
		}
		if ((shiftRegister & 1) == 1) {
			return 0;
		}
		if (envelopeEnabled) {
			return envelopeVolume;
		} else {
			return constantVolume;
		}
	}

private:
	bool enabled = false;
	bool mode = false;
	ushort shiftRegister = 1;
	bool lengthEnabled = false;
	ubyte lengthValue = 0;
	ushort timerPeriod = 0;
	ushort timerValue = 0;
	bool envelopeEnabled = false;
	bool envelopeLoop = false;
	bool envelopeStart = false;
	ubyte envelopePeriod = 0;
	ubyte envelopeValue = 0;
	ubyte envelopeVolume = 0;
	ubyte constantVolume = 0;
}
/// Audio processing unit emulator.
struct APU {
	bool delegate(ref APU) @safe playFrame;
	/// Step the APU by one frame.
	void stepFrame() @safe {
		if (playFrame !is null) {
			playFrame(this);
		}
		// Step the frame counter 4 times per frame, for 240Hz
		for (int i = 0; i < 4; i++) {
			frameValue = (frameValue + 1) % 5;
			switch (frameValue) {
				case 1:
				case 3:
					stepEnvelope();
					break;
				case 0:
				case 2:
					stepEnvelope();
					stepSweep();
					stepLength();
					break;
				default: break;
			}

			// Calculate the number of samples needed per 1/4 frame
			int frequency = defaultFrequency;

			// Example: we need 735 samples per frame for 44.1KHz sound sampling
			int samplesToWrite = frequency / (frameRate * 4);
			if (i == 3) {
				// Handle the remainder on the final tick of the frame counter
				samplesToWrite = (frequency / frameRate) - 3 * (frequency / (frameRate * 4));
			}

			// Step the timer ~3729 times per quarter frame for most channels
			int j = 0;
			for (int stepIndex = 0; stepIndex < 3729; stepIndex++) {
				if (j < samplesToWrite && (stepIndex / 3729.0) > (j / cast(double)samplesToWrite)) {
					ubyte sample = getOutput();
					audioBuffer[audioBufferLength + j] = sample;
					j++;
				}

				pulse1.stepTimer();
				pulse2.stepTimer();
				noise.stepTimer();
				triangle.stepTimer();
				triangle.stepTimer();
			}
			audioBufferLength += samplesToWrite;
		}
	}

	void output(ubyte[] buffer) @safe {
		if (audioBufferLength == 0) {
			stepFrame();
		}
		const len = (buffer.length > audioBufferLength) ? audioBufferLength : buffer.length;
		buffer[0 .. len] = audioBuffer[0 .. len];
		if (len > audioBufferLength) {
			buffer[0 .. audioBufferLength] = audioBuffer[0 .. audioBufferLength];
			audioBufferLength = 0;
		} else {
			buffer[0 .. len] = audioBuffer[0 .. len];
			audioBufferLength -= len;
			audioBuffer[0 .. audioBufferLength] = audioBuffer[len .. len + audioBufferLength];
		}
	}

	void writeRegister(ushort address, ubyte value) @safe {
		switch (address) {
		case 0x4000:
			pulse1.writeControl(value);
			break;
		case 0x4001:
			pulse1.writeSweep(value);
			break;
		case 0x4002:
			pulse1.writeTimerLow(value);
			break;
		case 0x4003:
			pulse1.writeTimerHigh(value);
			break;
		case 0x4004:
			pulse2.writeControl(value);
			break;
		case 0x4005:
			pulse2.writeSweep(value);
			break;
		case 0x4006:
			pulse2.writeTimerLow(value);
			break;
		case 0x4007:
			pulse2.writeTimerHigh(value);
			break;
		case 0x4008:
			triangle.writeControl(value);
			break;
		case 0x400a:
			triangle.writeTimerLow(value);
			break;
		case 0x400b:
			triangle.writeTimerHigh(value);
			break;
		case 0x400c:
			noise.writeControl(value);
			break;
		case 0x400d:
		case 0x400e:
			noise.writePeriod(value);
			break;
		case 0x400f:
			noise.writeLength(value);
			break;
		case 0x4015:
			writeControl(value);
			break;
		case 0x4017:
			stepEnvelope();
			stepSweep();
			stepLength();
			break;
		default:
			break;
		}
	}

private:
	ubyte[AUDIO_BUFFER_LENGTH] audioBuffer;
	int audioBufferLength;

	int frameValue; /// The value of the frame counter.

	Pulse pulse1 = Pulse(1);
	Pulse pulse2 = Pulse(2);
	Triangle triangle;
	Noise noise;

	ubyte getOutput() @safe {
		double pulseOut = 0.00752 * (pulse1.output() + pulse2.output());
		double tndOut = 0.00851 * triangle.output() + 0.00494 * noise.output();

		return cast(ubyte)(floor(255.0 * (pulseOut + tndOut)));
	}
	void stepEnvelope() @safe {
		pulse1.stepEnvelope();
		pulse2.stepEnvelope();
		triangle.stepCounter();
		noise.stepEnvelope();
	}
	void stepSweep() @safe {
		pulse1.stepSweep();
		pulse2.stepSweep();
	}
	void stepLength() @safe {
		pulse1.stepLength();
		pulse2.stepLength();
		triangle.stepLength();
		noise.stepLength();
	}
	void writeControl(ubyte value) @safe {
		pulse1.enabled = (value & 1) == 1;
		pulse2.enabled = (value & 2) == 2;
		triangle.enabled = (value & 4) == 4;
		noise.enabled = (value & 8) == 8;
		if (!pulse1.enabled) {
			pulse1.lengthValue = 0;
		}
		if (!pulse2.enabled) {
			pulse2.lengthValue = 0;
		}
		if (!triangle.enabled) {
			triangle.lengthValue = 0;
		}
		if (!noise.enabled) {
			noise.lengthValue = 0;
		}
	}
}

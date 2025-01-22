module replatform64.backend.sdl3.audio;

import replatform64.backend.common;
import replatform64.backend.sdl3.common;
import replatform64.dumping;

import std.logger;
import std.string;

import bindbc.sdl;
import sdl_mixer;

struct AudioCallbackInfo {
	void* user;
	AudioCallback callback;
}

class SDL3Audio : AudioBackend {
	private uint sampleRate;
	private uint channels;
	private uint samples;
	AudioCallbackInfo* callbackInfo;
	void initialize(uint sampleRate, uint channels, uint samples) @trusted {
		this.sampleRate = sampleRate;
		this.channels = channels;
		this.samples = samples;
		enforceSDL(SDL_Init(SDL_INIT_AUDIO), "Error initializing SDL Audio");
		infof("SDL audio subsystem initialized (%s)", SDL_GetCurrentAudioDriver().fromStringz);
	}
	void installCallback(void* user, AudioCallback fun) @trusted {
		const spec = SDL_AudioSpec(format: SDL_AUDIO_S16, channels: channels, freq: sampleRate);
		callbackInfo = new AudioCallbackInfo(user, fun);
	    auto stream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, &callbackWrapper, callbackInfo);
	    SDL_ResumeAudioDevice(SDL_GetAudioStreamDevice(stream));
	}
	void deinitialize() @safe {}
	void loadWAV(const ubyte[] data) @safe {}
	void playWAV(size_t id, int channel) @safe {}
}

private extern(C) void callbackWrapper(void* extra, SDL_AudioStream* stream, int additional, int total) nothrow {
	auto callbackInfo = cast(AudioCallbackInfo*)extra;
	import std.exception : assumeWontThrow;
	import core.stdc.stdlib : exit;
	ubyte[] buffer;
	static ubyte[10000] staticBuf;
	try {
		if (additional > 0) {
			buffer = staticBuf[0 .. additional];
			assert(callbackInfo);
			assert(callbackInfo.user);
			assert(callbackInfo.callback);
			callbackInfo.callback(callbackInfo.user, buffer);
		}
	} catch (Throwable e) {
		writeDebugDumpOtherThread(e.msg, e.info);
	}
	if (buffer.length) {
		SDL_PutAudioStreamData(stream, &buffer[0], additional);
	}
}

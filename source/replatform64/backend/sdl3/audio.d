module replatform64.backend.sdl3.audio;

import replatform64.backend.common;
import replatform64.backend.sdl3.common;
import replatform64.dumping;

import std.algorithm.comparison;
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
	private AudioCallbackInfo* callbackInfo;
	private SDL_AudioStream*[] streams;
	private const(ubyte)[][] loadedWAVs;
	private const(ubyte)[][] playingWAVs;
	private SDL_AudioStream* mainStream;
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
		auto dev = SDL_OpenAudioDevice(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec);
		mainStream = SDL_CreateAudioStream(&spec, &spec);
		enforceSDL(!!mainStream, "Could not open audio device");
		enforceSDL(SDL_SetAudioStreamGetCallback(mainStream, &callbackWrapper, callbackInfo), "Could not set callback");
		enforceSDL(SDL_BindAudioStream(dev, mainStream), "Could not bind audio stream");
	}
	void deinitialize() @safe {}
	void loadWAV(const ubyte[] data) @trusted {
		ubyte* buf;
		uint length;
		SDL_AudioSpec spec;
		enforceSDL(SDL_LoadWAV_IO(SDL_IOFromMem(cast(void*)&data[0], data.length), true, &spec, &buf, &length), "Couldn't load WAV");
		loadedWAVs ~= buf[0 .. length];
	}
	void playWAV(size_t id, int channel) @trusted {
		const spec = SDL_AudioSpec(format: SDL_AUDIO_S16, channels: channels, freq: sampleRate);
		if (channel + 1 > streams.length) {
			playingWAVs.length = channel + 1;
			streams.length = channel + 1;
		}
		playingWAVs[channel] = loadedWAVs[id];
		if (streams[channel] == null) {
			streams[channel] = SDL_CreateAudioStream(&spec, &spec);
			enforceSDL(SDL_BindAudioStream(SDL_GetAudioStreamDevice(mainStream), streams[channel]), "Could not bind audio stream");
		} else {
			// clear callback just in case one was already active
			enforceSDL(SDL_SetAudioStreamGetCallback(streams[channel], null, null), "Could not clear callback");
		}
		enforceSDL(SDL_SetAudioStreamGetCallback(streams[channel], &wavPlayer, &playingWAVs[channel]), "Could not set callback");
	}
}

private extern(C) void wavPlayer(void* user, SDL_AudioStream* stream, int additional, int total) nothrow {
	auto wav = cast(const(ubyte)[]*)user;
	auto data = (*wav)[0 .. min($, additional)];
	*wav = (*wav)[data.length .. $];
	SDL_PutAudioStreamData(stream, &data[0], cast(int)data.length);
	if (wav.length == 0) {
		SDL_FlushAudioStream(stream);
		SDL_SetAudioStreamGetCallback(stream, null, null);
	}
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

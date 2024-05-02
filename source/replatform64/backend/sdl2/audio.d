module replatform64.backend.sdl2.audio;

import replatform64.backend.common;
import replatform64.backend.sdl2.common;
import replatform64.dumping;

import std.logger;
import std.string;

import bindbc.sdl;
import sdl_mixer;


version(Windows) {
	enum libName = "SDL2_mixer.dll";
} else version (OSX) {
	enum libName = "libSDL2_mixer.dylib";
} else version (Posix) {
	enum libName = "libSDL2_mixer.so";
}

class SDL2Audio : AudioBackend {
	private uint sampleRate;
	private uint channels;
	private uint samples;
	void initialize(uint sampleRate, uint channels, uint samples) @trusted {
		this.sampleRate = sampleRate;
		this.channels = channels;
		this.samples = samples;
		enforceSDL(SDL_Init(SDL_INIT_AUDIO) == 0, "Error initializing SDL Audio");
		infof("SDL audio subsystem initialized (%s)", SDL_GetCurrentAudioDriver().fromStringz);
	}
	void installCallback(void* user, AudioCallback fun) @trusted {
		SDL_AudioSpec want, have;
		want.freq = sampleRate;
		want.format = AUDIO_S16;
		want.channels = cast(ubyte)channels;
		want.samples = cast(ushort)samples;
		callback = fun;
		want.callback = &callbackWrapper;
		want.userdata = user;
		const dev = SDL_OpenAudioDevice(null, 0, &want, &have, 0);
		enforceSDL(dev != 0, "Error opening audio device");
		SDL_PauseAudioDevice(dev, 0);
	}
	void deinitialize() @safe {}
	void loadWAV(const ubyte[] data) @safe {}
	void playWAV(size_t id, int channel) @safe {}
}

class SDL2AudioMixer : AudioBackend {
	Mix_Chunk*[] loadedWAVs;
	void initialize(uint sampleRate, uint channels, uint samples) @trusted {
		assert(SDL_GetError !is null, "SDL is not loaded!");
		enforceSDLLoaded!("SDL_Mixer", Mix_Linked_Version, libName)(loadSDLMixer());
		enforceSDL(Mix_OpenAudio(sampleRate, AUDIO_S16, channels, samples / channels) != -1, "Could not open audio");
		int finalSampleRate;
		int finalChannels;
		ushort finalFormat;
		Mix_QuerySpec(&finalSampleRate, &finalFormat, &finalChannels);

		infof("SDL audio subsystem initialized (%s, %s channels, %sHz)", SDL_GetCurrentAudioDriver().fromStringz, finalChannels, finalSampleRate);
	}
	void installCallback(void* user, AudioCallback fun) @trusted {
		callback = fun;
		Mix_HookMusic(&callbackWrapper, user);
	}
	void deinitialize() @safe {}
	void loadWAV(const ubyte[] data) @trusted {
		loadedWAVs ~= Mix_LoadWAV_RW(SDL_RWFromMem(cast(void*)&data[0], cast(int)data.length), 0);
	}
	void playWAV(size_t id, int channel) @trusted {
		if (id == 0) {
			if(Mix_FadeOutChannel(channel, 0) == -1) {
				SDLError("Could not fade out");
			}
		} else {
			if(Mix_PlayChannel(channel, loadedWAVs[id - 1], 0) == -1) {
				SDLError("Could not play sound effect");
			}
		}
	}
}

private __gshared AudioCallback callback;

private extern(C) void callbackWrapper(void* extra, ubyte* buf, int length) nothrow {
	import std.exception : assumeWontThrow;
	import core.stdc.stdlib : exit;
	try {
		assert(callback);
		callback(extra, buf[0 .. length]);
	} catch (Throwable e) {
		writeDebugDumpOtherThread(e.msg, e.info);
	}
}

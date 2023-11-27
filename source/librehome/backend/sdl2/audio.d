module librehome.backend.sdl2.audio;

import librehome.backend.common;
import librehome.backend.sdl2.common;

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
	void initialize(void* user, AudioCallback fun, uint sampleRate, uint channels, uint samples) @trusted {
		enforceSDL(SDL_Init(SDL_INIT_AUDIO) == 0, "Error initializing SDL Audio");
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
		infof("SDL audio subsystem initialized (%s)", SDL_GetCurrentAudioDriver().fromStringz);
	}
	void deinitialize() @safe {}
}

class SDL2AudioMixer : AudioBackend {
	void initialize(void* user, AudioCallback fun, uint sampleRate, uint channels, uint samples) @trusted {
		assert(SDL_GetError !is null, "SDL is not loaded!");
	    enforceSDLLoaded!("SDL_Mixer", Mix_Linked_Version, libName)(loadSDLMixer());
		enforceSDL(Mix_OpenAudio(sampleRate, AUDIO_S16, channels, samples) != -1, "Could not open audio");
		callback = fun;
		Mix_HookMusic(&callbackWrapper, user);
		int finalSampleRate;
		int finalChannels;
		ushort finalFormat;
		Mix_QuerySpec(&finalSampleRate, &finalFormat, &finalChannels);

		infof("SDL audio subsystem initialized (%s)", SDL_GetCurrentAudioDriver().fromStringz);
	}
	void deinitialize() @safe {}
}

private __gshared AudioCallback callback;

private extern(C) void callbackWrapper(void* extra, ubyte* buf, int length) nothrow {
	assert(callback);
	callback(extra, buf[0 .. length]);
}

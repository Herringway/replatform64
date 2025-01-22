module replatform64.backend.sdl3.platform;

import replatform64.backend.common;
import replatform64.backend.sdl3.audio;
import replatform64.backend.sdl3.common;
import replatform64.backend.sdl3.input;
import replatform64.backend.sdl3.video;

import bindbc.sdl;

version(Windows) {
	enum libName = "SDL3.dll";
} else version (OSX) {
	enum libName = "libSDL3.dylib";
} else version (Posix) {
	enum libName = "libSDL3.so";
}

class SDL3Platform : PlatformBackend {
	override void initialize() @trusted {
		enforceSDLLoaded!("SDL", SDL_GetVersion, libName)(loadSDL());
		video = new SDL3Video;
		audio = new SDL3Audio;
		input = new SDL3Input;
	}
	override void deinitialize() @trusted {
		SDL_Quit();
	}
	override bool processEvents() @trusted {
		SDL_Event event;
		while(SDL_PollEvent(&event)) {
			(cast(SDL3Video)video).handleUIEvent(&event);
			if ((cast(SDL3Input)input).processEvent(event)) {
				return true;
			}
			switch (event.type) {
				case SDL_EVENT_QUIT:
					return true;
				default: break;
			}
		}
		return false;
	}
}

module librehome.backend.sdl2.platform;

import librehome.backend.common;
import librehome.backend.sdl2.audio;
import librehome.backend.sdl2.common;
import librehome.backend.sdl2.input;
import librehome.backend.sdl2.video;

import bindbc.sdl;

version(Windows) {
	enum libName = "SDL2.dll";
} else version (OSX) {
	enum libName = "libSDL2.dylib";
} else version (Posix) {
	enum libName = "libSDL2.so";
}

class SDL2Platform : PlatformBackend {
	override void initialize() @trusted {
    	enforceSDLLoaded!("SDL", SDL_GetVersion, libName)(loadSDL());
    	video = new SDL2Video;
    	audio = new SDL2Audio;
    	input = new SDL2Input;
	}
	override void deinitialize() @trusted {
		SDL_Quit();
	}
	override bool processEvents() @trusted {
		SDL_Event event;
		while(SDL_PollEvent(&event)) {
			(cast(SDL2Video)video).handleUIEvent(&event);
			if ((cast(SDL2Input)input).processEvent(event)) {
				return true;
			}
			switch (event.type) {
				case SDL_QUIT:
					return true;
				default: break;
			}
		}
		return false;
	}
}

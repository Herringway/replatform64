module librehome.backend.common.loading;

import librehome.backend.common.interfaces;
import librehome.backend.nullbackend;
import librehome.backend.sdl2;

PlatformBackend loadBackend(Backend backend, BackendSettings settings) @safe {
	PlatformBackend result;
	final switch (backend) {
		case Backend.sdl2:
		case Backend.autoSelect:
			result = new SDL2Platform;
			break;
		case Backend.none:
			result = new NullPlatform;
			break;
	}
	result.initialize();
	result.audio.initialize(settings.audio.sampleRate, settings.audio.channels, settings.audio.sampleRate);
	result.input.initialize(settings.input);
	result.video.initialize(settings.video);
	return result;
}

enum Backend {
	autoSelect,
	sdl2,
	none,
}

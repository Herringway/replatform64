module librehome.backend.common.loading;

import librehome.backend.common.interfaces;
import librehome.backend.sdl2;

PlatformBackend loadBackend(BackendSettings settings) @safe {
	auto backend = new SDL2Platform;
	backend.initialize();
	backend.audio.initialize(settings.audio.sampleRate, settings.audio.channels, settings.audio.sampleRate);
	backend.input.initialize(settings.input);
	backend.video.initialize(settings.video);
	backend.video.loadUIState(settings.ui);
	return backend;
}

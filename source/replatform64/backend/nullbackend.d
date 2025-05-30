module replatform64.backend.nullbackend;

import replatform64.backend.common;
import replatform64.ui;
import replatform64.util;

class NullAudio : AudioBackend {
	void initialize(uint sampleRate, uint channels, uint samples) {}
	void installCallback(void* data, AudioCallback callback) {}
	void deinitialize() @safe {}
	void loadWAV(const ubyte[] data) @safe {}
	void playWAV(size_t id, int channel = 0) @safe {}
}

class NullVideo : VideoBackend {
	void initialize(VideoSettings) @safe {}
	ImGui.ImGuiContext* initializeUI() { return null; }
	void deinitialize() @safe {}
	void getDrawingTexture(out Texture texture) @safe {}
	void createWindow(string title, WindowSettings settings) @safe {}
	WindowState getWindowState() const @safe { return typeof(return).init; }
	void createTexture(uint width, uint height, PixelFormat format) @safe {}
	void* createSurface(size_t width, size_t height, size_t stride, PixelFormat format) @safe { return null; }
	void* getRenderingTexture() @safe { return null; }
	void setSurfacePixels(void* surface, ubyte[] buffer) @trusted {}
	void startFrame() @safe {}
	void finishFrame() @safe {}
	void waitNextFrame() @safe {}
	void setTitle(scope const char[] title) @safe {}
}
class NullInput : InputBackend {
	void initialize(InputSettings) @safe {}
	InputState getState() @safe {
		return InputState.init;
	}
}

class NullPlatform : PlatformBackend {
	override void initialize() @safe {
		video = new NullVideo;
		audio = new NullAudio;
		input = new NullInput;
	}
	override void deinitialize() @safe {}
	override bool processEvents() @safe { return false; }
}
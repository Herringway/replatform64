module replatform64.backend.common.interfaces;

public import replatform64.backend.common.inputconstants;
import replatform64.ui;
import replatform64.util;

import std.bitmanip;
import std.typecons;

alias AudioCallback = void function(void*, ubyte[]);
interface AudioBackend {
	void initialize(uint sampleRate, uint channels, uint samples) @safe;
	void installCallback(void* data, AudioCallback callback) @safe;
	void deinitialize() @safe;
	void loadWAV(const ubyte[] data) @safe;
	void playWAV(size_t id, int channel = 0) @safe;
}

interface VideoBackend {
	void initialize(VideoSettings) @safe;
	void deinitialize() @safe;
	void getDrawingTexture(out Texture texture) @safe;
	void* getRenderingTexture() @safe;
	void createWindow(string title, WindowSettings settings) @safe;
	WindowState getWindowState() const @safe;
	void createTexture(uint width, uint height, PixelFormat format) @safe;
	void* createSurface(size_t width, size_t height, size_t stride, PixelFormat format) @safe;
	void setSurfacePixels(void* surface, ubyte[] buffer) @safe;
	void startFrame() @safe;
	void finishFrame() @safe;
	void waitNextFrame() @safe;
	void setTitle(scope const char[] title) @safe;
}
interface InputBackend {
	void initialize(InputSettings) @safe;
	InputState getState() @safe;
}

abstract class PlatformBackend {
	AudioBackend audio;
	VideoBackend video;
	InputBackend input;
	void initialize() @safe;
	void deinitialize() @safe;
	bool processEvents() @safe;
}

struct AudioSettings {
	ushort sampleRate = 32000;
	ushort channels = 2;
	ushort bufferSize = 4096;
}

struct BackendSettings {
	AudioSettings audio;
	VideoSettings video;
	InputSettings input;
}

struct WindowState {
	WindowMode mode;
	Nullable!uint x;
	Nullable!uint y;
	Nullable!uint width;
	Nullable!uint height;
}

struct VideoSettings {
	WindowState window;
	bool keepAspectRatio = true;
	uint zoom = 1;
	uint uiZoom = 1;
	string ui;
}

struct WindowSettings {
	uint baseWidth;
	uint baseHeight;
}

struct InputSettings {
	version(unittest) {
		// workaround for https://issues.dlang.org/show_bug.cgi?id=24428
		Controller[GamePadButton] gamepadMapping;
		AxisMapping[GamePadAxis] gamepadAxisMapping;
		Controller[KeyboardKey] keyboardMapping;
	} else {
		Controller[GamePadButton] gamepadMapping = [
			GamePadButton.x : Controller.y,
			GamePadButton.a : Controller.b,
			GamePadButton.b : Controller.a,
			GamePadButton.y : Controller.x,
			GamePadButton.start : Controller.start,
			GamePadButton.back : Controller.select,
			GamePadButton.leftShoulder : Controller.l,
			GamePadButton.rightShoulder : Controller.r,
			GamePadButton.dpadUp : Controller.up,
			GamePadButton.dpadDown : Controller.down,
			GamePadButton.dpadLeft : Controller.left,
			GamePadButton.dpadRight : Controller.right,
		];
		AxisMapping[GamePadAxis] gamepadAxisMapping = [
			GamePadAxis.leftX: AxisMapping.leftRight,
			GamePadAxis.leftY: AxisMapping.upDown,
		];
		Controller[KeyboardKey] keyboardMapping = [
			KeyboardKey.s: Controller.b,
			KeyboardKey.a: Controller.y,
			KeyboardKey.x: Controller.select,
			KeyboardKey.z: Controller.start,
			KeyboardKey.up: Controller.up,
			KeyboardKey.down: Controller.down,
			KeyboardKey.left: Controller.left,
			KeyboardKey.right: Controller.right,
			KeyboardKey.d: Controller.a,
			KeyboardKey.w: Controller.x,
			KeyboardKey.q: Controller.l,
			KeyboardKey.e: Controller.r,
			KeyboardKey.p: Controller.pause,
			KeyboardKey.backSlash: Controller.skipFrame,
			KeyboardKey.grave: Controller.fastForward,
			KeyboardKey.escape: Controller.exit
		];
	}
}

struct Texture {
	ubyte[] buffer;
	uint pitch;
	uint width;
	uint height;
	void* surface;
	Array2D!T asArray2D(T)() @safe pure {
		return Array2D!T(width, height, pitch / T.sizeof, cast(T[])buffer);
	}
	void delegate() @safe nothrow @nogc cleanup;
	~this() {
		cleanup();
	}
}

enum PixelFormat {
	rgb555,
	abgr8888,
	argb8888,
	bgra8888,
	rgba8888,
}

enum WindowMode {
	windowed,
	maximized,
	fullscreen,
	fullscreenExclusive,
}

private extern(C) __gshared ubyte internal;

struct BackendID {
	string id;
}

struct ABGR8888 {
	align(1):
	union {
		uint value;
		struct {
			ubyte red;
			ubyte green;
			ubyte blue;
			ubyte alpha;
		}
	}
	this(ubyte red, ubyte green, ubyte blue) @safe pure {
		this.red = red;
		this.green = green;
		this.blue = blue;
		this.alpha = 0xFF;
	}
	this(uint value) @safe pure {
		this.value = value;
	}
	void toString(S)(S sink) const {
		import std.format : formattedWrite;
		sink.formattedWrite("ABGR8888(%s, %s, %s, %s)", red, green, blue, alpha);
	}
}

struct RGB555 {
	align(1):
	union {
		struct {
			mixin(bitfields!(
				ubyte, "blue", 5,
				ubyte, "green", 5,
				ubyte, "red", 5,
				bool, "", 1,
			));
		}
		ushort value;
	}
	this(ubyte red, ubyte green, ubyte blue) @safe pure {
		this.red = red;
		this.green = green;
		this.blue = blue;
	}
	this(ushort value) @safe pure {
		this.value = value;
	}
	void toString(S)(S sink) const {
		import std.format : formattedWrite;
		sink.formattedWrite("RGB555(%s, %s, %s)", red, green, blue);
	}
}

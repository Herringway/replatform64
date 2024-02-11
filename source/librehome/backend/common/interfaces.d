module librehome.backend.common.interfaces;

public import librehome.backend.common.inputconstants;
import librehome.ui;

alias AudioCallback = void function(void*, ubyte[]);
alias DebugFunction = void delegate(const UIState);
interface AudioBackend {
	void initialize(void* data, AudioCallback callback, uint sampleRate, uint channels, uint samples) @safe;
	void deinitialize() @safe;
	void loadWAV(const ubyte[] data) @safe;
	void playWAV(size_t id, int channel = 0) @safe;
}

interface VideoBackend {
	void initialize() @safe;
	void setDebuggingFunctions(DebugFunction, DebugFunction, DebugFunction, DebugFunction) @safe;
	void deinitialize() @safe;
	void getDrawingTexture(out Texture texture) @safe;
	void createWindow(string title, WindowSettings settings) @safe;
	void createTexture(uint width, uint height, PixelFormat format) @safe;
	void startFrame() @safe;
	void finishFrame() @safe;
	void waitNextFrame() @safe;
	void setTitle(scope const char[] title) @safe;
	void hideUI() @safe;
	void showUI() @safe;
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

struct VideoSettings {
	WindowMode mode;
	bool keepAspectRatio = true;
	uint zoom = 1;
	uint uiZoom = 1;
}

struct WindowSettings {
	VideoSettings userSettings;
	uint width;
	uint height;
	bool debugging;
}

struct InputSettings {
	Controller[GamePadButton] gamepadMapping;
	AxisMapping[GamePadAxis] gamepadAxisMapping;
	Controller[KeyboardKey] keyboardMapping;
}

struct Texture {
	ubyte[] buffer;
	uint pitch;
	uint width;
	uint height;
	void delegate() @safe nothrow @nogc cleanup;
	~this() {
		cleanup();
	}
}

enum PixelFormat {
	rgb555,
	argb8888,
}

enum WindowMode {
	windowed,
	fullscreen,
	fullscreenExclusive,
}

struct InputState {
	ushort[2] controllers;
	bool exit;
	bool pause;
	bool step;
	bool fastForward;
}

InputSettings getDefaultInputSettings() pure @safe {
	InputSettings defaults;
	defaults.gamepadAxisMapping = [
		GamePadAxis.leftX: AxisMapping.leftRight,
		GamePadAxis.leftY: AxisMapping.upDown,
	];
	defaults.gamepadMapping = [
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
	defaults.keyboardMapping = [
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
	return defaults;
}

module replatform64.backend.sdl2.input;

import replatform64.backend.common;
import replatform64.backend.sdl2.common;
import replatform64.common;
import replatform64.ui;

import bindbc.sdl;

import std.file;
import std.logger;
import std.string;

class SDL2Input : InputBackend {
	private InputState state;
	private InputSettings settings;
	void initialize(InputSettings settings) @trusted {
		enforceSDL(SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER) == 0, "Couldn't initialise controller SDL subsystem");
		if ("gamecontrollerdb.txt".exists) {
			if (SDL_GameControllerAddMappingsFromFile("gamecontrollerdb.txt") < 0) {
				SDLError("Error loading game controller database");
			} else {
				info("Successfully loaded game controller database");
			}
		}
		SDL_GameControllerEventState(SDL_ENABLE);
		info("SDL game controller subsystem initialized");
		this.settings = settings;
	}
	InputState getState() @trusted {
		return state;
	}
	bool processEvent(ref SDL_Event event) {
		switch (event.type) {
			case SDL_KEYDOWN:
			case SDL_KEYUP:
				if (imguiAteKeyboard()) {
					break;
				}
				if (auto button = sdlKeyToKeyboardKey(event.key.keysym.scancode) in settings.keyboardMapping) {
					handleButton(state, *button, event.type == SDL_KEYDOWN, 1);
				}
				break;
			case SDL_CONTROLLERAXISMOTION:
				if (auto axis = sdlAxisToGamePadAxis(cast(SDL_GameControllerAxis)event.caxis.axis) in settings.gamepadAxisMapping) {
					handleAxis(state, *axis, event.caxis.value, SDL_GameControllerGetPlayerIndex(SDL_GameControllerFromInstanceID(event.caxis.which)));
				}
				break;
			case SDL_CONTROLLERBUTTONUP:
			case SDL_CONTROLLERBUTTONDOWN:
				if (auto button = sdlButtonToGamePadButton(cast(SDL_GameControllerButton)event.cbutton.button) in settings.gamepadMapping) {
					handleButton(state, *button, event.type == SDL_CONTROLLERBUTTONDOWN, SDL_GameControllerGetPlayerIndex(SDL_GameControllerFromInstanceID(event.cbutton.which)));
				}
				break;
			case SDL_CONTROLLERDEVICEADDED:
				connectGamepad(event.cdevice.which);
				break;

			case SDL_CONTROLLERDEVICEREMOVED:
				disconnectGamepad(event.cdevice.which);
				break;
			default: break;
		}
		return state.exit;
	}
}
private void connectGamepad(int id) {
	if (SDL_IsGameController(id)) {
		if (auto controller = SDL_GameControllerOpen(id)) {
			SDL_GameControllerSetPlayerIndex(controller, 1);
			const(char)* name = SDL_GameControllerNameForIndex(id);
			infof("Initialized controller: %s", name.fromStringz);
		} else {
			SDLError("Error opening controller: %s");
		}
	}
}
private void disconnectGamepad(int id) {
	if (auto controller = SDL_GameControllerFromInstanceID(id)) {
		infof("Controller disconnected: %s", SDL_GameControllerName(controller).fromStringz);
		SDL_GameControllerClose(controller);
	}
}
void applyButtonMask(ref InputState input, ushort val, bool pressed, uint playerID) @safe pure {
	if (pressed) {
		input.controllers[playerID - 1] |= val;
	} else {
		input.controllers[playerID - 1] &= cast(ushort)~val;
	}
}
void handleButton(ref InputState input, Controller button, bool pressed, uint playerID) @safe pure {
	final switch (button) {
		case Controller.up, Controller.down, Controller.left, Controller.right, Controller.l, Controller.r, Controller.select, Controller.start, Controller.a, Controller.b, Controller.x, Controller.y, Controller.extra1, Controller.extra2, Controller.extra3, Controller.extra4:
			applyButtonMask(input, cast(ushort)controllerToMask(button), pressed, playerID);
			break;
		case Controller.fastForward:
			input.fastForward = pressed;
			break;
		case Controller.pause:
			input.pause = pressed;
			break;
		case Controller.skipFrame:
			input.step = pressed;
			break;
		case Controller.exit:
			input.exit = pressed;
			break;
	}
}
void handleAxis(ref InputState input, AxisMapping axis, short value, uint playerID) @safe pure {
	enum upper = short.max / 2;
	enum lower = short.min / 2;
	const pressed = (value >= upper) || (value <= lower);
	final switch (axis) {
		case AxisMapping.upDown:
			applyButtonMask(input, cast(ushort)controllerToMask(Controller.down), value >= upper, playerID);
			applyButtonMask(input, cast(ushort)controllerToMask(Controller.up), value <= lower, playerID);
			break;
		case AxisMapping.leftRight:
			applyButtonMask(input, cast(ushort)controllerToMask(Controller.right), value >= upper, playerID);
			applyButtonMask(input, cast(ushort)controllerToMask(Controller.left), value <= lower, playerID);
			break;
		case AxisMapping.l, AxisMapping.r, AxisMapping.select, AxisMapping.start, AxisMapping.a, AxisMapping.b, AxisMapping.x, AxisMapping.y, AxisMapping.extra1, AxisMapping.extra2, AxisMapping.extra3, AxisMapping.extra4:
			applyButtonMask(input, cast(ushort)controllerAxisToMask(axis), pressed, playerID);
			break;
		case AxisMapping.fastForward:
			input.fastForward = pressed;
			break;
		case AxisMapping.pause:
			input.pause = pressed;
			break;
		case AxisMapping.skipFrame:
			input.step = pressed;
			break;
		case AxisMapping.exit:
			input.exit = pressed;
			break;
	}
}
GamePadAxis sdlAxisToGamePadAxis(SDL_GameControllerAxis axis) {
	switch (axis) {
		case SDL_CONTROLLER_AXIS_LEFTX: return GamePadAxis.leftX;
		case SDL_CONTROLLER_AXIS_LEFTY: return GamePadAxis.leftY;
		case SDL_CONTROLLER_AXIS_RIGHTX: return GamePadAxis.rightX;
		case SDL_CONTROLLER_AXIS_RIGHTY: return GamePadAxis.rightY;
		case SDL_CONTROLLER_AXIS_TRIGGERLEFT: return GamePadAxis.triggerLeft;
		case SDL_CONTROLLER_AXIS_TRIGGERRIGHT: return GamePadAxis.triggerRight;
		default: return GamePadAxis.invalid;
	}
}
GamePadButton sdlButtonToGamePadButton(SDL_GameControllerButton button) {
	switch (button) {
		case SDL_CONTROLLER_BUTTON_A: return GamePadButton.a;
		case SDL_CONTROLLER_BUTTON_B: return GamePadButton.b;
		case SDL_CONTROLLER_BUTTON_X: return GamePadButton.x;
		case SDL_CONTROLLER_BUTTON_Y: return GamePadButton.y;
		case SDL_CONTROLLER_BUTTON_BACK: return GamePadButton.back;
		case SDL_CONTROLLER_BUTTON_GUIDE: return GamePadButton.guide;
		case SDL_CONTROLLER_BUTTON_START: return GamePadButton.start;
		case SDL_CONTROLLER_BUTTON_LEFTSTICK: return GamePadButton.leftStick;
		case SDL_CONTROLLER_BUTTON_RIGHTSTICK: return GamePadButton.rightStick;
		case SDL_CONTROLLER_BUTTON_LEFTSHOULDER: return GamePadButton.leftShoulder;
		case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: return GamePadButton.rightShoulder;
		case SDL_CONTROLLER_BUTTON_DPAD_UP: return GamePadButton.dpadUp;
		case SDL_CONTROLLER_BUTTON_DPAD_DOWN: return GamePadButton.dpadDown;
		case SDL_CONTROLLER_BUTTON_DPAD_LEFT: return GamePadButton.dpadLeft;
		case SDL_CONTROLLER_BUTTON_DPAD_RIGHT: return GamePadButton.dpadRight;
		default: return GamePadButton.invalid;
	}
}

KeyboardKey sdlKeyToKeyboardKey(SDL_Scancode scancode) {
	switch (scancode) {
		case SDL_SCANCODE_A: return KeyboardKey.a;
		case SDL_SCANCODE_B: return KeyboardKey.b;
		case SDL_SCANCODE_C: return KeyboardKey.c;
		case SDL_SCANCODE_D: return KeyboardKey.d;
		case SDL_SCANCODE_E: return KeyboardKey.e;
		case SDL_SCANCODE_F: return KeyboardKey.f;
		case SDL_SCANCODE_G: return KeyboardKey.g;
		case SDL_SCANCODE_H: return KeyboardKey.h;
		case SDL_SCANCODE_I: return KeyboardKey.i;
		case SDL_SCANCODE_J: return KeyboardKey.j;
		case SDL_SCANCODE_K: return KeyboardKey.k;
		case SDL_SCANCODE_L: return KeyboardKey.l;
		case SDL_SCANCODE_M: return KeyboardKey.m;
		case SDL_SCANCODE_N: return KeyboardKey.n;
		case SDL_SCANCODE_O: return KeyboardKey.o;
		case SDL_SCANCODE_P: return KeyboardKey.p;
		case SDL_SCANCODE_Q: return KeyboardKey.q;
		case SDL_SCANCODE_R: return KeyboardKey.r;
		case SDL_SCANCODE_S: return KeyboardKey.s;
		case SDL_SCANCODE_T: return KeyboardKey.t;
		case SDL_SCANCODE_U: return KeyboardKey.u;
		case SDL_SCANCODE_V: return KeyboardKey.v;
		case SDL_SCANCODE_W: return KeyboardKey.w;
		case SDL_SCANCODE_X: return KeyboardKey.x;
		case SDL_SCANCODE_Y: return KeyboardKey.y;
		case SDL_SCANCODE_Z: return KeyboardKey.z;
		case SDL_SCANCODE_1: return KeyboardKey.number1;
		case SDL_SCANCODE_2: return KeyboardKey.number2;
		case SDL_SCANCODE_3: return KeyboardKey.number3;
		case SDL_SCANCODE_4: return KeyboardKey.number4;
		case SDL_SCANCODE_5: return KeyboardKey.number5;
		case SDL_SCANCODE_6: return KeyboardKey.number6;
		case SDL_SCANCODE_7: return KeyboardKey.number7;
		case SDL_SCANCODE_8: return KeyboardKey.number8;
		case SDL_SCANCODE_9: return KeyboardKey.number9;
		case SDL_SCANCODE_0: return KeyboardKey.number0;
		case SDL_SCANCODE_RETURN: return KeyboardKey.return_;
		case SDL_SCANCODE_ESCAPE: return KeyboardKey.escape;
		case SDL_SCANCODE_BACKSPACE: return KeyboardKey.backspace;
		case SDL_SCANCODE_TAB: return KeyboardKey.tab;
		case SDL_SCANCODE_SPACE: return KeyboardKey.space;
		case SDL_SCANCODE_MINUS: return KeyboardKey.minus;
		case SDL_SCANCODE_EQUALS: return KeyboardKey.equals;
		case SDL_SCANCODE_LEFTBRACKET: return KeyboardKey.leftBracket;
		case SDL_SCANCODE_RIGHTBRACKET: return KeyboardKey.rightBracket;
		case SDL_SCANCODE_BACKSLASH: return KeyboardKey.backSlash;
		case SDL_SCANCODE_NONUSHASH: return KeyboardKey.nonUSHash;
		case SDL_SCANCODE_SEMICOLON: return KeyboardKey.semicolon;
		case SDL_SCANCODE_APOSTROPHE: return KeyboardKey.apostrophe;
		case SDL_SCANCODE_GRAVE: return KeyboardKey.grave;
		case SDL_SCANCODE_COMMA: return KeyboardKey.comma;
		case SDL_SCANCODE_PERIOD: return KeyboardKey.period;
		case SDL_SCANCODE_SLASH: return KeyboardKey.slash;
		case SDL_SCANCODE_CAPSLOCK: return KeyboardKey.capsLock;
		case SDL_SCANCODE_F1: return KeyboardKey.f1;
		case SDL_SCANCODE_F2: return KeyboardKey.f2;
		case SDL_SCANCODE_F3: return KeyboardKey.f3;
		case SDL_SCANCODE_F4: return KeyboardKey.f4;
		case SDL_SCANCODE_F5: return KeyboardKey.f5;
		case SDL_SCANCODE_F6: return KeyboardKey.f6;
		case SDL_SCANCODE_F7: return KeyboardKey.f7;
		case SDL_SCANCODE_F8: return KeyboardKey.f8;
		case SDL_SCANCODE_F9: return KeyboardKey.f9;
		case SDL_SCANCODE_F10: return KeyboardKey.f10;
		case SDL_SCANCODE_F11: return KeyboardKey.f11;
		case SDL_SCANCODE_F12: return KeyboardKey.f12;
		case SDL_SCANCODE_PRINTSCREEN: return KeyboardKey.printScreen;
		case SDL_SCANCODE_SCROLLLOCK: return KeyboardKey.scrollLock;
		case SDL_SCANCODE_PAUSE: return KeyboardKey.pause;
		case SDL_SCANCODE_INSERT: return KeyboardKey.insert;
		case SDL_SCANCODE_HOME: return KeyboardKey.home;
		case SDL_SCANCODE_PAGEUP: return KeyboardKey.pageUp;
		case SDL_SCANCODE_DELETE: return KeyboardKey.delete_;
		case SDL_SCANCODE_END: return KeyboardKey.end;
		case SDL_SCANCODE_PAGEDOWN: return KeyboardKey.pageDown;
		case SDL_SCANCODE_RIGHT: return KeyboardKey.right;
		case SDL_SCANCODE_LEFT: return KeyboardKey.left;
		case SDL_SCANCODE_DOWN: return KeyboardKey.down;
		case SDL_SCANCODE_UP: return KeyboardKey.up;
		case SDL_SCANCODE_NUMLOCKCLEAR: return KeyboardKey.numLockClear;
		case SDL_SCANCODE_KP_DIVIDE: return KeyboardKey.kpDivide;
		case SDL_SCANCODE_KP_MULTIPLY: return KeyboardKey.kpMultiply;
		case SDL_SCANCODE_KP_MINUS: return KeyboardKey.kpMinus;
		case SDL_SCANCODE_KP_PLUS: return KeyboardKey.kpPlus;
		case SDL_SCANCODE_KP_ENTER: return KeyboardKey.kpEnter;
		case SDL_SCANCODE_KP_1: return KeyboardKey.kp1;
		case SDL_SCANCODE_KP_2: return KeyboardKey.kp2;
		case SDL_SCANCODE_KP_3: return KeyboardKey.kp3;
		case SDL_SCANCODE_KP_4: return KeyboardKey.kp4;
		case SDL_SCANCODE_KP_5: return KeyboardKey.kp5;
		case SDL_SCANCODE_KP_6: return KeyboardKey.kp6;
		case SDL_SCANCODE_KP_7: return KeyboardKey.kp7;
		case SDL_SCANCODE_KP_8: return KeyboardKey.kp8;
		case SDL_SCANCODE_KP_9: return KeyboardKey.kp9;
		case SDL_SCANCODE_KP_0: return KeyboardKey.kp0;
		case SDL_SCANCODE_KP_PERIOD: return KeyboardKey.kpPeriod;
		case SDL_SCANCODE_NONUSBACKSLASH: return KeyboardKey.nonUSBackslash;
		case SDL_SCANCODE_APPLICATION: return KeyboardKey.application;
		case SDL_SCANCODE_POWER: return KeyboardKey.power;
		case SDL_SCANCODE_KP_EQUALS: return KeyboardKey.kpEquals;
		case SDL_SCANCODE_F13: return KeyboardKey.f13;
		case SDL_SCANCODE_F14: return KeyboardKey.f14;
		case SDL_SCANCODE_F15: return KeyboardKey.f15;
		case SDL_SCANCODE_F16: return KeyboardKey.f16;
		case SDL_SCANCODE_F17: return KeyboardKey.f17;
		case SDL_SCANCODE_F18: return KeyboardKey.f18;
		case SDL_SCANCODE_F19: return KeyboardKey.f19;
		case SDL_SCANCODE_F20: return KeyboardKey.f20;
		case SDL_SCANCODE_F21: return KeyboardKey.f21;
		case SDL_SCANCODE_F22: return KeyboardKey.f22;
		case SDL_SCANCODE_F23: return KeyboardKey.f23;
		case SDL_SCANCODE_F24: return KeyboardKey.f24;
		case SDL_SCANCODE_EXECUTE: return KeyboardKey.execute;
		case SDL_SCANCODE_HELP: return KeyboardKey.help;
		case SDL_SCANCODE_MENU: return KeyboardKey.menu;
		case SDL_SCANCODE_SELECT: return KeyboardKey.select;
		case SDL_SCANCODE_STOP: return KeyboardKey.stop;
		case SDL_SCANCODE_AGAIN: return KeyboardKey.again;
		case SDL_SCANCODE_UNDO: return KeyboardKey.undo;
		case SDL_SCANCODE_CUT: return KeyboardKey.cut;
		case SDL_SCANCODE_COPY: return KeyboardKey.copy;
		case SDL_SCANCODE_PASTE: return KeyboardKey.paste;
		case SDL_SCANCODE_FIND: return KeyboardKey.find;
		case SDL_SCANCODE_MUTE: return KeyboardKey.mute;
		case SDL_SCANCODE_VOLUMEUP: return KeyboardKey.volumeUp;
		case SDL_SCANCODE_VOLUMEDOWN: return KeyboardKey.volumeDown;
		case SDL_SCANCODE_KP_COMMA: return KeyboardKey.kpComma;
		case SDL_SCANCODE_KP_EQUALSAS400: return KeyboardKey.kpEqualsAs400;
		case SDL_SCANCODE_INTERNATIONAL1: return KeyboardKey.international1;
		case SDL_SCANCODE_INTERNATIONAL2: return KeyboardKey.international2;
		case SDL_SCANCODE_INTERNATIONAL3: return KeyboardKey.international3;
		case SDL_SCANCODE_INTERNATIONAL4: return KeyboardKey.international4;
		case SDL_SCANCODE_INTERNATIONAL5: return KeyboardKey.international5;
		case SDL_SCANCODE_INTERNATIONAL6: return KeyboardKey.international6;
		case SDL_SCANCODE_INTERNATIONAL7: return KeyboardKey.international7;
		case SDL_SCANCODE_INTERNATIONAL8: return KeyboardKey.international8;
		case SDL_SCANCODE_INTERNATIONAL9: return KeyboardKey.international9;
		case SDL_SCANCODE_LANG1: return KeyboardKey.lang1;
		case SDL_SCANCODE_LANG2: return KeyboardKey.lang2;
		case SDL_SCANCODE_LANG3: return KeyboardKey.lang3;
		case SDL_SCANCODE_LANG4: return KeyboardKey.lang4;
		case SDL_SCANCODE_LANG5: return KeyboardKey.lang5;
		case SDL_SCANCODE_LANG6: return KeyboardKey.lang6;
		case SDL_SCANCODE_LANG7: return KeyboardKey.lang7;
		case SDL_SCANCODE_LANG8: return KeyboardKey.lang8;
		case SDL_SCANCODE_LANG9: return KeyboardKey.lang9;
		case SDL_SCANCODE_ALTERASE: return KeyboardKey.altErase;
		case SDL_SCANCODE_SYSREQ: return KeyboardKey.sysReq;
		case SDL_SCANCODE_CANCEL: return KeyboardKey.cancel;
		case SDL_SCANCODE_CLEAR: return KeyboardKey.clear;
		case SDL_SCANCODE_PRIOR: return KeyboardKey.prior;
		case SDL_SCANCODE_RETURN2: return KeyboardKey.return2;
		case SDL_SCANCODE_SEPARATOR: return KeyboardKey.separator;
		case SDL_SCANCODE_OUT: return KeyboardKey.out_;
		case SDL_SCANCODE_OPER: return KeyboardKey.oper;
		case SDL_SCANCODE_CLEARAGAIN: return KeyboardKey.clearAgain;
		case SDL_SCANCODE_CRSEL: return KeyboardKey.crsel;
		case SDL_SCANCODE_EXSEL: return KeyboardKey.exsel;
		case SDL_SCANCODE_KP_00: return KeyboardKey.kp00;
		case SDL_SCANCODE_KP_000: return KeyboardKey.kp000;
		case SDL_SCANCODE_THOUSANDSSEPARATOR: return KeyboardKey.thousandsSeparator;
		case SDL_SCANCODE_DECIMALSEPARATOR: return KeyboardKey.decimalSeparator;
		case SDL_SCANCODE_CURRENCYUNIT: return KeyboardKey.currencyUnit;
		case SDL_SCANCODE_CURRENCYSUBUNIT: return KeyboardKey.currencySubunit;
		case SDL_SCANCODE_KP_LEFTPAREN: return KeyboardKey.kpLeftParen;
		case SDL_SCANCODE_KP_RIGHTPAREN: return KeyboardKey.kpRightParen;
		case SDL_SCANCODE_KP_LEFTBRACE: return KeyboardKey.kpLeftBrace;
		case SDL_SCANCODE_KP_RIGHTBRACE: return KeyboardKey.kpRightBrace;
		case SDL_SCANCODE_KP_TAB: return KeyboardKey.kpTab;
		case SDL_SCANCODE_KP_BACKSPACE: return KeyboardKey.kpBackspace;
		case SDL_SCANCODE_KP_A: return KeyboardKey.kpA;
		case SDL_SCANCODE_KP_B: return KeyboardKey.kpB;
		case SDL_SCANCODE_KP_C: return KeyboardKey.kpC;
		case SDL_SCANCODE_KP_D: return KeyboardKey.kpD;
		case SDL_SCANCODE_KP_E: return KeyboardKey.kpE;
		case SDL_SCANCODE_KP_F: return KeyboardKey.kpF;
		case SDL_SCANCODE_KP_XOR: return KeyboardKey.kpXOR;
		case SDL_SCANCODE_KP_POWER: return KeyboardKey.kpPower;
		case SDL_SCANCODE_KP_PERCENT: return KeyboardKey.kpPercent;
		case SDL_SCANCODE_KP_LESS: return KeyboardKey.kpLess;
		case SDL_SCANCODE_KP_GREATER: return KeyboardKey.kpGreater;
		case SDL_SCANCODE_KP_AMPERSAND: return KeyboardKey.kpAmpersand;
		case SDL_SCANCODE_KP_DBLAMPERSAND: return KeyboardKey.kpDblAmpersand;
		case SDL_SCANCODE_KP_VERTICALBAR: return KeyboardKey.kpVerticalBar;
		case SDL_SCANCODE_KP_DBLVERTICALBAR: return KeyboardKey.kpDblVerticalBar;
		case SDL_SCANCODE_KP_COLON: return KeyboardKey.kpColon;
		case SDL_SCANCODE_KP_HASH: return KeyboardKey.kpHash;
		case SDL_SCANCODE_KP_SPACE: return KeyboardKey.kpSpace;
		case SDL_SCANCODE_KP_AT: return KeyboardKey.kpAt;
		case SDL_SCANCODE_KP_EXCLAM: return KeyboardKey.kpExclam;
		case SDL_SCANCODE_KP_MEMSTORE: return KeyboardKey.kpMemStore;
		case SDL_SCANCODE_KP_MEMRECALL: return KeyboardKey.kpMemRecall;
		case SDL_SCANCODE_KP_MEMCLEAR: return KeyboardKey.kpMemClear;
		case SDL_SCANCODE_KP_MEMADD: return KeyboardKey.kpMemAdd;
		case SDL_SCANCODE_KP_MEMSUBTRACT: return KeyboardKey.kpMemSubtract;
		case SDL_SCANCODE_KP_MEMMULTIPLY: return KeyboardKey.kpMemMultiply;
		case SDL_SCANCODE_KP_MEMDIVIDE: return KeyboardKey.kpMemDivide;
		case SDL_SCANCODE_KP_PLUSMINUS: return KeyboardKey.kpPlusMinus;
		case SDL_SCANCODE_KP_CLEAR: return KeyboardKey.kpClear;
		case SDL_SCANCODE_KP_CLEARENTRY: return KeyboardKey.kpClearEntry;
		case SDL_SCANCODE_KP_BINARY: return KeyboardKey.kpBinary;
		case SDL_SCANCODE_KP_OCTAL: return KeyboardKey.kpOctal;
		case SDL_SCANCODE_KP_DECIMAL: return KeyboardKey.kpDecimal;
		case SDL_SCANCODE_KP_HEXADECIMAL: return KeyboardKey.kpHexadecimal;
		case SDL_SCANCODE_LCTRL: return KeyboardKey.lCtrl;
		case SDL_SCANCODE_LSHIFT: return KeyboardKey.lShift;
		case SDL_SCANCODE_LALT: return KeyboardKey.lAlt;
		case SDL_SCANCODE_LGUI: return KeyboardKey.lGUI;
		case SDL_SCANCODE_RCTRL: return KeyboardKey.rCtrl;
		case SDL_SCANCODE_RSHIFT: return KeyboardKey.rShift;
		case SDL_SCANCODE_RALT: return KeyboardKey.rAlt;
		case SDL_SCANCODE_RGUI: return KeyboardKey.rGUI;
		case SDL_SCANCODE_MODE: return KeyboardKey.mode;
		case SDL_SCANCODE_AUDIONEXT: return KeyboardKey.audioNext;
		case SDL_SCANCODE_AUDIOPREV: return KeyboardKey.audioPrev;
		case SDL_SCANCODE_AUDIOSTOP: return KeyboardKey.audioStop;
		case SDL_SCANCODE_AUDIOPLAY: return KeyboardKey.audioPlay;
		case SDL_SCANCODE_AUDIOMUTE: return KeyboardKey.audioMute;
		case SDL_SCANCODE_MEDIASELECT: return KeyboardKey.mediaSelect;
		case SDL_SCANCODE_WWW: return KeyboardKey.www;
		case SDL_SCANCODE_MAIL: return KeyboardKey.mail;
		case SDL_SCANCODE_CALCULATOR: return KeyboardKey.calculator;
		case SDL_SCANCODE_COMPUTER: return KeyboardKey.computer;
		case SDL_SCANCODE_AC_SEARCH: return KeyboardKey.acSearch;
		case SDL_SCANCODE_AC_HOME: return KeyboardKey.acHome;
		case SDL_SCANCODE_AC_BACK: return KeyboardKey.acBack;
		case SDL_SCANCODE_AC_FORWARD: return KeyboardKey.acForward;
		case SDL_SCANCODE_AC_STOP: return KeyboardKey.acStop;
		case SDL_SCANCODE_AC_REFRESH: return KeyboardKey.acRefresh;
		case SDL_SCANCODE_AC_BOOKMARKS: return KeyboardKey.acBookmarks;
		case SDL_SCANCODE_BRIGHTNESSDOWN: return KeyboardKey.brightnessDown;
		case SDL_SCANCODE_BRIGHTNESSUP: return KeyboardKey.brightnessUp;
		case SDL_SCANCODE_DISPLAYSWITCH: return KeyboardKey.displaySwitch;
		case SDL_SCANCODE_KBDILLUMTOGGLE: return KeyboardKey.kbdIllumToggle;
		case SDL_SCANCODE_KBDILLUMDOWN: return KeyboardKey.kbdIllumDown;
		case SDL_SCANCODE_KBDILLUMUP: return KeyboardKey.kbdIllumUp;
		case SDL_SCANCODE_EJECT: return KeyboardKey.eject;
		case SDL_SCANCODE_SLEEP: return KeyboardKey.sleep;
		case SDL_SCANCODE_APP1: return KeyboardKey.app1;
		case SDL_SCANCODE_APP2: return KeyboardKey.app2;
		default: return KeyboardKey.invalid;
	}
}

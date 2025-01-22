module replatform64.backend.sdl3.common;

import std.exception;
import std.format;
import std.logger;
import std.string;
import std.traits;

import bindbc.sdl;
import sdl_mixer;

void SDLError(string fmt) {
	errorf(fmt, SDL_GetError().fromStringz);
}

void enforceSDL(lazy bool expr, string message) {
	if (!expr) {
		throw new Exception(format!"%s: %s"(SDL_GetError().fromStringz, message));
	}
}

void enforceSDLLoaded(string what, alias versionFunction, string libName, T)(T got) {
	enforce(got != T.noLibrary, "Could not load "~what~": No library found - "~libName~" is missing or has incorrect architecture");
	enforce(got != T.badLibrary, "Could not load "~what~": Bad library found - "~libName~" is incompatible");
    int ver = versionFunction();
	infof("Loaded "~what~": %s.%s.%s", SDL_VERSIONNUM_MAJOR(ver), SDL_VERSIONNUM_MINOR(ver), SDL_VERSIONNUM_MICRO(ver));
}
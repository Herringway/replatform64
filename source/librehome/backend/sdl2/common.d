module librehome.backend.sdl2.common;

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
	static if (is(ReturnType!versionFunction == void)) {
	    SDL_version ver;
	    versionFunction(&ver);
	} else {
	    SDL_version ver = *versionFunction();
	}
    infof("Loaded "~what~": %s.%s.%s", ver.major, ver.minor, ver.patch);
}
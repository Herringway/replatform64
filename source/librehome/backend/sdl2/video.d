module librehome.backend.sdl2.video;

import librehome.backend.common;
import librehome.backend.sdl2.common;

import bindbc.sdl;

import std.logger;
import std.string;

class SDL2Video : VideoBackend {
	private SDL_Window* window;
	private SDL_Renderer* renderer;
	private SDL_Texture* drawTexture;
	private WindowSettings settings;
	private int lastTime;
	void initialize() @trusted {
		enforceSDL(SDL_Init(SDL_INIT_VIDEO) == 0, "Error initializing SDL");
		infof("SDL video subsystem initialized (%s)", SDL_GetCurrentVideoDriver().fromStringz);
	}
	void createWindow(string title, WindowSettings settings) @trusted {
		assert(settings.width > 0, "Zero width is invalid");
		assert(settings.height > 0, "Zero height is invalid");
		enum windowFlags = SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE;
		this.settings = settings;
		infof("%s, %s", settings.width, settings.height);
		window = SDL_CreateWindow(
			title.toStringz,
			SDL_WINDOWPOS_UNDEFINED,
			SDL_WINDOWPOS_UNDEFINED,
			settings.width * settings.zoom + settings.leftPadding + settings.rightPadding,
			settings.height * settings.zoom + settings.topPadding + settings.bottomPadding,
			windowFlags
		);
		final switch (settings.mode) {
			case WindowMode.windowed:
				break;
			case WindowMode.fullscreen:
				SDL_SetWindowFullscreen(window, SDL_WINDOW_FULLSCREEN_DESKTOP);
				break;
			case WindowMode.fullscreenExclusive:
				SDL_SetWindowFullscreen(window, SDL_WINDOW_FULLSCREEN);
				break;
		}
		enforceSDL(window !is null, "Error creating SDL window");
		const rendererFlags = SDL_RENDERER_ACCELERATED;
		renderer = SDL_CreateRenderer(
			window, -1, rendererFlags
		);
		enforceSDL(renderer !is null, "Error creating SDL renderer");
		if (settings.keepAspectRatio) {
			SDL_RenderSetLogicalSize(renderer, settings.width + settings.leftPadding + settings.rightPadding, settings.height + settings.topPadding + settings.bottomPadding);
		}
		SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);
		SDL_RendererInfo renderInfo;
		SDL_GetRendererInfo(renderer, &renderInfo);
		infof("SDL renderer initialized (%s)", renderInfo.name.fromStringz);
	}
	void deinitialize() @trusted {
		// Close and destroy the window
		if (window !is null) {
			SDL_DestroyWindow(window);
		}
		// Close and destroy the renderer
		if (renderer !is null) {
			SDL_DestroyRenderer(renderer);
		}
		// Close and destroy the texture
		if (drawTexture !is null) {
			SDL_DestroyTexture(drawTexture);
		}
		SDL_QuitSubSystem(SDL_INIT_VIDEO);
	}
	void finishFrame() @trusted {
		lastTime = SDL_GetTicks();
		SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
		SDL_RenderClear(renderer);
		SDL_Rect screen;
		screen.x = settings.leftPadding;
		screen.y = settings.rightPadding;
		screen.w = settings.width;
		screen.h = settings.height;
		SDL_RenderCopy(renderer, drawTexture, null, &screen);
		SDL_RenderPresent(renderer);
	}
	void createTexture(uint width, uint height, PixelFormat format) @trusted {
		assert(width > 0, "Zero width is invalid");
		assert(height > 0, "Zero height is invalid");
		uint fmt;
		final switch (format) {
			case PixelFormat.rgb555: fmt = SDL_PIXELFORMAT_RGB555; break;
			case PixelFormat.argb8888: fmt = SDL_PIXELFORMAT_ARGB8888; break;
		}
		drawTexture = SDL_CreateTexture(renderer, fmt, SDL_TEXTUREACCESS_STREAMING, width, height);
		enforceSDL(drawTexture !is null, "Error creating SDL texture");
	}
	void getDrawingTexture(out Texture result) @trusted {
		ubyte* drawBuffer;
		int pitch;
		SDL_LockTexture(drawTexture, null, cast(void**)&drawBuffer, &pitch);
		result.pitch = pitch;
		result.buffer = drawBuffer[0 .. settings.height * result.pitch];
		result.cleanup = &freeTexture;
	}
	void freeTexture() @trusted nothrow @nogc {
		if (drawTexture) {
			SDL_UnlockTexture(drawTexture);
		}
	}
	void waitNextFrame() @trusted {
		int drawTime = SDL_GetTicks() - lastTime;
		if (drawTime < 16) {
			SDL_Delay(16 - drawTime);
		}
	}
}

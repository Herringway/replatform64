module replatform64.backend.sdl2.video;

import replatform64.backend.common;
import replatform64.backend.sdl2.common;

import replatform64.ui;

import imgui.sdl;
import imgui.sdlrenderer;

import bindbc.sdl;

import std.algorithm.comparison;
import std.logger;
import std.string;

class SDL2Video : VideoBackend {
	private SDL_Window* sdlWindow;
	private SDL_Renderer* renderer;
	private SDL_Texture* drawTexture;
	private WindowSettings window;
	private VideoSettings settings;
	private int lastTime;
	void initialize(VideoSettings settings) @trusted
		in(settings.uiZoom > 0, "Zoom is invalid")
	{
		this.settings = settings;
		enforceSDL(SDL_Init(SDL_INIT_VIDEO) == 0, "Error initializing SDL");
		infof("SDL video subsystem initialized (%s)", SDL_GetCurrentVideoDriver().fromStringz);
	}
	//void resetWindowSize(bool debugMode) @trusted {
	//	SDL_SetWindowSize(sdlWindow,
	//		(window.baseWidth + (250 * debugMode)) * max(1, settings.uiZoom, settings.zoom),
	//		(window.baseHeight + (150 * debugMode)) * max(1, settings.uiZoom, settings.zoom));
	//	SDL_SetWindowPosition(sdlWindow, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
	//}
	void createWindow(string title, WindowSettings window) @trusted
		in(window.width > 0, "Zero width is invalid")
		in(window.height > 0, "Zero height is invalid")
	{
		enum windowFlags = SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE;
		this.window = window;
		sdlWindow = SDL_CreateWindow(
			title.toStringz,
			settings.window.x < settings.window.x.max ? settings.window.x : SDL_WINDOWPOS_UNDEFINED,
			settings.window.y < settings.window.y.max ? settings.window.y : SDL_WINDOWPOS_UNDEFINED,
			settings.window.width < settings.window.width.max ? settings.window.width : (window.baseWidth * max(1, settings.uiZoom, settings.zoom)),
			settings.window.height < settings.window.height.max ? settings.window.height : (window.baseHeight * max(1, settings.uiZoom, settings.zoom)),
			windowFlags | (settings.window.mode == WindowMode.maximized ? SDL_WINDOW_MAXIMIZED : 0)
		);
		final switch (settings.window.mode) {
			case WindowMode.windowed:
				break;
			case WindowMode.maximized:
				break;
			case WindowMode.fullscreen:
				SDL_SetWindowFullscreen(sdlWindow, SDL_WINDOW_FULLSCREEN_DESKTOP);
				break;
			case WindowMode.fullscreenExclusive:
				SDL_SetWindowFullscreen(sdlWindow, SDL_WINDOW_FULLSCREEN);
				break;
		}
		enforceSDL(sdlWindow !is null, "Error creating SDL window");
		const rendererFlags = SDL_RENDERER_ACCELERATED;
		renderer = SDL_CreateRenderer(
			sdlWindow, -1, rendererFlags
		);
		enforceSDL(renderer !is null, "Error creating SDL renderer");
		SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);
		SDL_RendererInfo renderInfo;
		SDL_GetRendererInfo(renderer, &renderInfo);
		infof("SDL renderer initialized (%s)", renderInfo.name.fromStringz);

		ImGui_ImplSDL2_InitForSDLRenderer(sdlWindow, renderer);
		ImGui_ImplSDLRenderer_Init(renderer);
	}
	WindowState getWindowState() const @safe {
		return settings.window;
	}
	void deinitialize() @trusted {
		// destroy ImGui
		ImGui_ImplSDLRenderer_Shutdown();
		ImGui_ImplSDL2_Shutdown();
		// Close and destroy the window
		if (sdlWindow !is null) {
			SDL_DestroyWindow(sdlWindow);
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
	void startFrame() @trusted {
		lastTime = SDL_GetTicks();
		SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
		SDL_RenderClear(renderer);
		// ImGui
		ImGui_ImplSDL2_NewFrame();
		ImGui_ImplSDLRenderer_NewFrame();
		ImGui.NewFrame();
	}
	void finishFrame() @trusted {
		ImGui.Render();
		ImGui_ImplSDLRenderer_RenderDrawData(ImGui.GetDrawData());

		SDL_RenderPresent(renderer);
	}
	void createTexture(uint width, uint height, PixelFormat format) @trusted {
		assert(width > 0, "Zero width is invalid");
		assert(height > 0, "Zero height is invalid");
		const fmt = getFormat(format);
		drawTexture = SDL_CreateTexture(renderer, fmt, SDL_TEXTUREACCESS_STREAMING, width, height);
		enforceSDL(drawTexture !is null, "Error creating SDL texture");
	}
	private uint getFormat(PixelFormat format) @safe {
		final switch (format) {
			case PixelFormat.rgb555: return SDL_PIXELFORMAT_RGB555; break;
			case PixelFormat.argb8888: return SDL_PIXELFORMAT_ARGB8888; break;
			case PixelFormat.bgra8888: return SDL_PIXELFORMAT_BGRA8888; break;
			case PixelFormat.rgba8888: return SDL_PIXELFORMAT_RGBA8888; break;
			case PixelFormat.abgr8888: return SDL_PIXELFORMAT_ABGR8888; break;
		}
	}
	void getDrawingTexture(out Texture result) @trusted {
		ubyte* drawBuffer;
		int pitch;
		SDL_LockTexture(drawTexture, null, cast(void**)&drawBuffer, &pitch);
		result.pitch = pitch;
		result.width = window.baseWidth;
		result.height = window.baseHeight;
		result.buffer = drawBuffer[0 .. window.baseHeight * result.pitch];
		result.cleanup = &freeTexture;
	}
	void* getRenderingTexture() @trusted {
		return drawTexture;
	}
	void* createSurface(size_t width, size_t height, size_t stride, PixelFormat format) @trusted {
		assert(renderer, "No renderer");
		int bpp;
		uint redMask, greenMask, blueMask, alphaMask;
		const fmt = getFormat(format);
		auto tex = SDL_CreateTexture(renderer, fmt, SDL_TEXTUREACCESS_STREAMING, cast(int)width, cast(int)height);
		enforceSDL(tex != null, "Failed to create texture");
		return tex;
	}
	void setSurfacePixels(void* surface, ubyte[] buffer) @trusted {
		auto texture = cast(SDL_Texture*)surface;
		ubyte* drawBuffer;
		int pitch;
		enforceSDL(SDL_LockTexture(texture, null, cast(void**)&drawBuffer, &pitch) == 0, "Failed to lock surface");
		int height;
		SDL_QueryTexture(texture, null, null, null, &height);
		assert(buffer.length <= pitch * height, format!"Expected at least %s bytes in texture, got %s"(buffer.length, pitch * height));
		drawBuffer[0 .. buffer.length] = buffer;
		SDL_UnlockTexture(texture);
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
	void handleUIEvent(SDL_Event* event) {
		if (event.type == SDL_WINDOWEVENT) {
			switch (event.window.event) {
				case SDL_WINDOWEVENT_MOVED:
					settings.window.x = event.window.data1;
					settings.window.y = event.window.data2;
					break;
				case SDL_WINDOWEVENT_MAXIMIZED:
					settings.window.mode = WindowMode.maximized;
					break;
				case SDL_WINDOWEVENT_RESTORED:
				case SDL_WINDOWEVENT_MINIMIZED:
					settings.window.mode = WindowMode.windowed;
					break;
				case SDL_WINDOWEVENT_RESIZED:
				case SDL_WINDOWEVENT_SIZE_CHANGED:
					settings.window.width = event.window.data1;
					settings.window.height = event.window.data2;
					break;
				default: break;
			}
		}
		ImGui_ImplSDL2_ProcessEvent(event);
	}
	void setTitle(scope const char[] title) @trusted {
		SDL_SetWindowTitle(sdlWindow, title.toStringz);
	}
}

module replatform64.backend.sdl3.video;

import replatform64.backend.common;
import replatform64.backend.sdl3.common;

import replatform64.ui;

import imgui.sdl3;
import imgui.sdl3renderer;

import bindbc.sdl;

import std.algorithm.comparison;
import std.logger;
import std.string;

class SDL3Video : VideoBackend {
	private SDL_Window* sdlWindow;
	private SDL_Renderer* renderer;
	private SDL_Texture* drawTexture;
	private WindowSettings window;
	private VideoSettings settings;
	private ulong lastTime;
	private PixelFormat pixelFormat;
	void initialize(VideoSettings settings) @trusted
		in(settings.uiZoom > 0, "Zoom is invalid")
	{
		this.settings = settings;
		enforceSDL(SDL_Init(SDL_INIT_VIDEO), "Error initializing SDL");
		infof("SDL video subsystem initialized (%s)", SDL_GetCurrentVideoDriver().fromStringz);
	}
	void createWindow(string title, WindowSettings window) @trusted
		in(window.width > 0, "Zero width is invalid")
		in(window.height > 0, "Zero height is invalid")
	{
		//const windowFlags = SDL_WINDOW_RESIZABLE | (settings.window.mode == WindowMode.maximized ? SDL_WINDOW_MAXIMIZED : 0);
		this.window = window;
		const finalZoom = max(1, settings.uiZoom, settings.zoom);
		const finalWidth = settings.window.width.get(window.baseWidth * finalZoom);
		const finalHeight = settings.window.height.get(window.baseHeight * finalZoom);
		tracef("Want window %sx%s with zoom %s", settings.window.width.get(-1), settings.window.height.get(-1), finalZoom);
		infof("Creating window with size %sx%s", finalWidth, finalHeight);

		SDL_PropertiesID props = SDL_CreateProperties();
		SDL_SetStringProperty(props, SDL_PROP_WINDOW_CREATE_TITLE_STRING, title.toStringz);
		SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_X_NUMBER, settings.window.x.get(SDL_WINDOWPOS_UNDEFINED));
		SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_Y_NUMBER, settings.window.y.get(SDL_WINDOWPOS_UNDEFINED));
		SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER, finalWidth);
		SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER, finalHeight);
		SDL_SetBooleanProperty(props, SDL_PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN, true);
		SDL_SetBooleanProperty(props, SDL_PROP_WINDOW_CREATE_MAXIMIZED_BOOLEAN, settings.window.mode == WindowMode.maximized);
		sdlWindow = SDL_CreateWindowWithProperties(props);
		SDL_DestroyProperties(props);

		final switch (settings.window.mode) {
			case WindowMode.windowed:
				break;
			case WindowMode.maximized:
				break;
			case WindowMode.fullscreen:
				SDL_SetWindowFullscreenMode(sdlWindow, null);
				break;
			case WindowMode.fullscreenExclusive:
				assert(0, "Unsupported");
				//SDL_SetWindowFullscreen(sdlWindow, SDL_WINDOW_FULLSCREEN);
				break;
		}
		enforceSDL(sdlWindow !is null, "Error creating SDL window");
		const rendererFlags = 0;
		renderer = SDL_CreateRenderer(sdlWindow, null);
		enforceSDL(renderer !is null, "Error creating SDL renderer");
		SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);
		infof("SDL renderer initialized (%s)", SDL_GetRendererName(renderer).fromStringz);

		ImGui_ImplSDL3_InitForSDLRenderer(sdlWindow, renderer);
		ImGui_ImplSDLRenderer3_Init(renderer);
	}
	WindowState getWindowState() const @safe {
		return settings.window;
	}
	void deinitialize() @trusted {
		// destroy ImGui
		ImGui_ImplSDLRenderer3_Shutdown();
		ImGui_ImplSDL3_Shutdown();
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
		enforceSDL(SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255), "SDL_SetRenderDrawColor failed");
		enforceSDL(SDL_RenderClear(renderer), "SDL_RenderClear failed");
		// ImGui
		ImGui_ImplSDL3_NewFrame();
		ImGui_ImplSDLRenderer3_NewFrame();
		ImGui.NewFrame();
	}
	void finishFrame() @trusted {
		ImGui.Render();
		ImGui_ImplSDLRenderer3_RenderDrawData(ImGui.GetDrawData(), renderer);

		SDL_RenderPresent(renderer);
	}
	void createTexture(uint width, uint height, PixelFormat format) @trusted {
		assert(width > 0, "Zero width is invalid");
		assert(height > 0, "Zero height is invalid");
		const fmt = getFormat(format);
		this.pixelFormat = format;
		drawTexture = SDL_CreateTexture(renderer, fmt, SDL_TEXTUREACCESS_STREAMING, width, height);
		enforceSDL(drawTexture !is null, "Error creating SDL texture");
	}
	private SDL_PixelFormat getFormat(PixelFormat format) @safe {
		final switch (format) {
			case PixelFormat.bgr555: return SDL_PIXELFORMAT_XBGR1555; break;
			case PixelFormat.rgb555: return SDL_PIXELFORMAT_XRGB1555; break;
			case PixelFormat.argb8888: return SDL_PIXELFORMAT_ARGB8888; break;
			case PixelFormat.bgra8888: return SDL_PIXELFORMAT_BGRA8888; break;
			case PixelFormat.rgba8888: return SDL_PIXELFORMAT_RGBA8888; break;
			case PixelFormat.abgr8888: return SDL_PIXELFORMAT_ABGR8888; break;
		}
	}
	void getDrawingTexture(out Texture result) @trusted {
		ubyte* drawBuffer;
		int pitch;
		enforceSDL(SDL_LockTexture(drawTexture, null, cast(void**)&drawBuffer, &pitch), "Failed to lock texture");
		result.pitch = pitch;
		result.width = window.baseWidth;
		result.height = window.baseHeight;
		result.buffer = drawBuffer[0 .. window.baseHeight * result.pitch];
		result.cleanup = &freeTexture;
		result.format = pixelFormat;
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
		enforceSDL(SDL_LockTexture(texture, null, cast(void**)&drawBuffer, &pitch), "Failed to lock surface");
		const props = SDL_GetTextureProperties(texture);
		enforceSDL(!!props, "SDL_GetTextureProperties failed");
		const height = SDL_GetNumberProperty(props, SDL_PROP_TEXTURE_HEIGHT_NUMBER, 0);
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
		ulong drawTime = SDL_GetTicks() - lastTime;
		if (drawTime < 16) {
			SDL_Delay(cast(int)(16 - drawTime));
		}
	}
	void handleUIEvent(SDL_Event* event) {
		switch (event.type) {
			case SDL_EVENT_WINDOW_MOVED:
				settings.window.x = event.window.data1;
				settings.window.y = event.window.data2;
				break;
			case SDL_EVENT_WINDOW_MAXIMIZED:
				settings.window.mode = WindowMode.maximized;
				break;
			case SDL_EVENT_WINDOW_RESTORED:
			case SDL_EVENT_WINDOW_MINIMIZED:
				settings.window.mode = WindowMode.windowed;
				break;
			case SDL_EVENT_WINDOW_RESIZED:
			case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED :
				settings.window.width = event.window.data1;
				settings.window.height = event.window.data2;
				break;
			case SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED:
				int currentWidth, currentHeight;
				const displayScale = SDL_GetWindowDisplayScale(sdlWindow);
				//SDL_SetWindowSize(sdlWindow, cast(int)(width * displayScale), cast(int)(height * displayScale));
				enforceSDL(SDL_GetWindowSizeInPixels(sdlWindow, &currentWidth, &currentHeight), "SDL_GetWindowSizeInPixels");
				infof("Resolution: %sx%s (%s)", currentWidth, currentHeight, displayScale);
				auto io = &ImGui.GetIO();
				io.DisplaySize = ImVec2(cast(float)currentWidth, cast(float)currentHeight);
				io.DisplayFramebufferScale = ImVec2(displayScale, displayScale);
				io.FontGlobalScale = displayScale;

				ImGui_ImplSDLRenderer3_DestroyDeviceObjects();
				ImGui_ImplSDLRenderer3_CreateDeviceObjects();
				break;
			default: break;
		}
		ImGui_ImplSDL3_ProcessEvent(event);
	}
	void setTitle(scope const char[] title) @trusted {
		SDL_SetWindowTitle(sdlWindow, title.toStringz);
	}
}

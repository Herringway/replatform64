module librehome.backend.sdl2.video;

import librehome.backend.common;
import librehome.backend.sdl2.common;

import librehome.ui;

import imgui.sdl;
import imgui.sdlrenderer;
import d_imgui.imgui_h;
import ImGui = d_imgui;

import bindbc.sdl;

import std.logger;
import std.string;

class SDL2Video : VideoBackend {
	private DebugFunction debugging;
	private SDL_Window* window;
	private SDL_Renderer* renderer;
	private SDL_Texture* drawTexture;
	private WindowSettings settings;
	private int lastTime;
	private ImGui.ImGuiContext* context;
	private enum debugWindowWidth = 150;
	void initialize(typeof(debugging) debugFunc) @trusted {
		enforceSDL(SDL_Init(SDL_INIT_VIDEO) == 0, "Error initializing SDL");
		infof("SDL video subsystem initialized (%s)", SDL_GetCurrentVideoDriver().fromStringz);
		debugging = debugFunc;
	}
	void createWindow(string title, WindowSettings settings) @trusted
		in(settings.width > 0, "Zero width is invalid")
		in(settings.height > 0, "Zero height is invalid")
	{
		settings.leftPadding += debugWindowWidth * settings.debugging;
		enum windowFlags = SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE;
		this.settings = settings;
		window = SDL_CreateWindow(
			title.toStringz,
			SDL_WINDOWPOS_UNDEFINED,
			SDL_WINDOWPOS_UNDEFINED,
			(settings.width + settings.leftPadding + settings.rightPadding) * settings.userSettings.zoom,
			(settings.height + settings.topPadding + settings.bottomPadding) * settings.userSettings.zoom,
			windowFlags
		);
		final switch (settings.userSettings.mode) {
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
		if (settings.userSettings.keepAspectRatio) {
			SDL_RenderSetLogicalSize(renderer, settings.width + settings.leftPadding + settings.rightPadding, settings.height + settings.topPadding + settings.bottomPadding);
		}
		SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);
		SDL_RendererInfo renderInfo;
		SDL_GetRendererInfo(renderer, &renderInfo);
		infof("SDL renderer initialized (%s)", renderInfo.name.fromStringz);

		// ImGui
		IMGUI_CHECKVERSION();
		context = ImGui.CreateContext();
		ImGuiIO* io = &ImGui.GetIO();

		ImGui.StyleColorsDark();
		ImGui.GetStyle().ScaleAllSizes(1.0 / settings.userSettings.zoom);
		io.FontGlobalScale = 1.0 / settings.userSettings.zoom;

		ImGui_ImplSDL2_InitForSDLRenderer(window, renderer);
		ImGui_ImplSDLRenderer_Init(renderer);
	}
	void deinitialize() @trusted {
		// destroy ImGui
		ImGui_ImplSDLRenderer_Shutdown();
		ImGui_ImplSDL2_Shutdown();
		ImGui.DestroyContext(context);
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

		int width, height;
		SDL_GL_GetDrawableSize(window, &width, &height);
		if (debugging) {
			debugging(UIState(debugWindowWidth, height));
		}
		ImGui.Render();
		ImGui_ImplSDLRenderer_RenderDrawData(ImGui.GetDrawData());

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
	void handleUIEvent(SDL_Event* event) {
		ImGui_ImplSDL2_ProcessEvent(event);
	}
}

module librehome.backend.sdl2.video;

import librehome.backend.common;
import librehome.backend.sdl2.common;

import librehome.ui;

import imgui.sdl;
import imgui.sdlrenderer;
import d_imgui.imgui_h;
import ImGui = d_imgui;

import bindbc.sdl;

import std.algorithm.comparison;
import std.logger;
import std.string;

class SDL2Video : VideoBackend {
	private DebugFunction debugging;
	private DebugFunction platformDebugging;
	private DebugFunction gameStateDebugging;
	private DebugFunction platformStateDebugging;
	private SDL_Window* sdlWindow;
	private SDL_Renderer* renderer;
	private SDL_Texture* drawTexture;
	private WindowSettings window;
	private VideoSettings settings;
	private int lastTime;
	private ImGui.ImGuiContext* context;
	private bool renderUI = true;
	private bool debuggingEnabled;
	void initialize(VideoSettings settings) @trusted
		in(settings.uiZoom > 0, "Zoom is invalid")
	{
		this.settings = settings;
		enforceSDL(SDL_Init(SDL_INIT_VIDEO) == 0, "Error initializing SDL");
		infof("SDL video subsystem initialized (%s)", SDL_GetCurrentVideoDriver().fromStringz);
		// ImGui
		IMGUI_CHECKVERSION();
		context = ImGui.CreateContext();
		ImGuiIO* io = &ImGui.GetIO();
		io.IniFilename = "";

		ImGui.StyleColorsDark();
		ImGui.GetStyle().ScaleAllSizes(settings.uiZoom);
		io.FontGlobalScale = settings.uiZoom;
		infof("ImGui initialized");
	}
	void setDebuggingFunctions(DebugFunction debugFunc, DebugFunction platformDebugFunc, DebugFunction gameStateMenu, DebugFunction platformStateMenu) @safe {
		debugging = debugFunc;
		platformDebugging = platformDebugFunc;
		this.gameStateDebugging = gameStateMenu;
		this.platformStateDebugging = platformStateMenu;
		debuggingEnabled = true;
		resetWindowSize(true);
	}
	void resetWindowSize(bool debugMode) @trusted {
		SDL_SetWindowSize(sdlWindow,
			(window.baseWidth + (250 * debugMode)) * max(1, settings.uiZoom, settings.zoom),
			(window.baseHeight + (150 * debugMode)) * max(1, settings.uiZoom, settings.zoom));
		SDL_SetWindowPosition(sdlWindow, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
	}
	void createWindow(string title, WindowSettings window) @trusted
		in(window.width > 0, "Zero width is invalid")
		in(window.height > 0, "Zero height is invalid")
	{
		enum windowFlags = SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE;
		this.window = window;
		sdlWindow = SDL_CreateWindow(
			title.toStringz,
			SDL_WINDOWPOS_CENTERED,
			SDL_WINDOWPOS_CENTERED,
			window.baseWidth * max(1, settings.uiZoom, settings.zoom),
			window.baseHeight * max(1, settings.uiZoom, settings.zoom),
			windowFlags
		);
		final switch (settings.mode) {
			case WindowMode.windowed:
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
	void deinitialize() @trusted {
		// destroy ImGui
		ImGui_ImplSDLRenderer_Shutdown();
		ImGui_ImplSDL2_Shutdown();
		ImGui.DestroyContext(context);
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
		UIState state;
		const gameWidth = window.baseWidth * settings.zoom;
		const gameHeight = window.baseHeight * settings.zoom;
		state.scaleFactor = settings.uiZoom;
		SDL_GetWindowSize(sdlWindow, &state.width, &state.height);
		if (renderUI) {
			if (debuggingEnabled) {
				ImGui.SetNextWindowSize(ImGui.ImVec2(gameWidth, gameHeight), ImGuiCond.FirstUseEver);
				ImGui.Begin("Game", null, ImGuiWindowFlags.NoScrollbar);
				ImGui.Image(cast(void*)drawTexture, ImGui.GetContentRegionAvail());
				ImGui.End();
				int areaHeight;
				if (ImGui.BeginMainMenuBar()) {
					areaHeight = cast(int)ImGui.GetWindowSize().y;
					ImGui.EndMainMenuBar();
				}
				if (platformDebugging) {
					platformDebugging(state);
				}
				if (debugging) {
					debugging(state);
				}
				if (platformStateDebugging) {
					ImGui.Begin("Platform", null, ImGuiWindowFlags.None);
					platformStateDebugging(state);
					ImGui.End();
				}
				if (gameStateDebugging) {
					enum debugWidth = 500;
					ImGui.SetNextWindowSize(ImGui.ImVec2(debugWidth, state.height - (areaHeight - 1)));
					ImGui.SetNextWindowPos(ImGui.ImVec2(0, areaHeight - 1));
					ImGui.Begin("Debugging", null, ImGuiWindowFlags.NoTitleBar | ImGuiWindowFlags.NoMove | ImGuiWindowFlags.NoResize | ImGuiWindowFlags.NoBringToFrontOnFocus);
					gameStateDebugging(UIState(debugWidth, state.height - areaHeight - 1, state.scaleFactor));
					ImGui.End();
				}
			} else {
				ImGui.GetStyle().WindowPadding = ImVec2(0, 0);
				ImGui.GetStyle().WindowBorderSize = 0;
				ImGui.SetNextWindowSize(ImGui.ImVec2(state.width, state.height));
				ImGui.SetNextWindowPos(ImGui.ImVec2(0, 0));
				ImGui.Begin("Game", null, ImGuiWindowFlags.NoDecoration | ImGuiWindowFlags.NoInputs | ImGuiWindowFlags.NoBringToFrontOnFocus | ImGuiWindowFlags.NoSavedSettings);
				auto drawSize = ImGui.GetContentRegionAvail();
				if (settings.keepAspectRatio) {
					const scaleFactor = min(state.width / cast(float)gameWidth, state.height / cast(float)gameHeight);
					drawSize = ImGui.ImVec2(gameWidth * scaleFactor, gameHeight * scaleFactor);
				}
				ImGui.Image(cast(void*)drawTexture, drawSize);
				ImGui.End();
			}
		}
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
	uint getFormat(PixelFormat format) @safe {
		final switch (format) {
			case PixelFormat.rgb555: return SDL_PIXELFORMAT_RGB555; break;
			case PixelFormat.argb8888: return SDL_PIXELFORMAT_ARGB8888; break;
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
		ImGui_ImplSDL2_ProcessEvent(event);
	}
	void setTitle(scope const char[] title) @trusted {
		SDL_SetWindowTitle(sdlWindow, title.toStringz);
	}
	void showUI() @safe {
		renderUI = true;
	}
	void hideUI() @safe {
		renderUI = false;
	}
	void loadUIState(string str) @trusted {
		ImGui.LoadIniSettingsFromMemory(str);
	}
	string getUIState() @trusted {
		return ImGui.SaveIniSettingsToMemory();
	}
}

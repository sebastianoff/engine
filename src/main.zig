pub fn main() !void {
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != true) {
        return error.SDLInitFailed;
    }
    defer sdl.SDL_Quit();
    const window = sdl.SDL_CreateWindow("hello, world!", 800, 600, sdl.SDL_WINDOW_RESIZABLE) orelse {
        return error.FailedToCreateWindow;
    };
    defer sdl.SDL_DestroyWindow(window);
    var running = true;
    var e: sdl.SDL_Event = undefined;
    while (running) {
        while (sdl.SDL_PollEvent(&e) != false) {
            if (e.type == sdl.SDL_EVENT_QUIT) running = false;
        }
        sdl.SDL_Delay(16);
    }
}

const std = @import("std");
const sdl = @import("sdl");

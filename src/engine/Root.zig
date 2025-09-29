version: u32 = 1,

pub const frameFn = *const fn (frame: *Frame) callconv(.c) bool;
pub const mainFn = *const fn (root: *const Root) callconv(.c) void;
pub const deinitFn = *const fn () callconv(.c) void;
pub const nameFn = *const fn () callconv(.c) [*:0]const u8;

pub const Window = @import("Window.zig");
pub const Frame = extern struct {
    time: f32,
    dt: f32,
    width: f32,
    height: f32,
    /// in-out
    clear_color: @Vector(4, f32),

    pub fn draw(frame: *const Frame, window: *Window) bool {
        const cmd = sdl.SDL_AcquireGPUCommandBuffer(window.device_ptr) orelse {
            std.Thread.sleep(std.time.ns_per_ms);
            return false;
        };

        var swapchain_texture: ?*sdl.SDL_GPUTexture = null;
        var width: sdl.Uint32 = 0;
        var height: sdl.Uint32 = 0;
        if (!sdl.SDL_WaitAndAcquireGPUSwapchainTexture(cmd, window.ptr, &swapchain_texture, &width, &height)) {
            _ = sdl.SDL_CancelGPUCommandBuffer(cmd);
            std.Thread.sleep(std.time.ns_per_ms);
            return false;
        }

        var target: sdl.SDL_GPUColorTargetInfo = .{
            .texture = swapchain_texture.?,
            .mip_level = 0,
            .layer_or_depth_plane = 0,
            .clear_color = .{
                .r = frame.clear_color[0],
                .g = frame.clear_color[1],
                .b = frame.clear_color[2],
                .a = frame.clear_color[3],
            },
            .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
            .store_op = sdl.SDL_GPU_STOREOP_STORE,
            .resolve_texture = null,
            .resolve_mip_level = 0,
            .resolve_layer = 0,
            .cycle = false,
            .cycle_resolve_texture = false,
        };

        if (sdl.SDL_BeginGPURenderPass(cmd, &target, 1, null)) |pass| {
            sdl.SDL_EndGPURenderPass(pass);
        }
        _ = sdl.SDL_SubmitGPUCommandBuffer(cmd);
        return true;
    }

    pub fn update(frame: *Frame, window: *Window, callback: ?frameFn) bool {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = sdl.SDL_GetWindowSizeInPixels(window.ptr, &w, &h);
        frame.width = @floatFromInt(w);
        frame.height = @floatFromInt(h);

        if (callback) |f| {
            return f(frame);
        }
        return false;
    }
};

const sdl = @import("sdl");
const std = @import("std");
const Root = @This();

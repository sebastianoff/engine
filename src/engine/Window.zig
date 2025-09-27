ptr: *sdl.SDL_Window,
device_ptr: *sdl.SDL_GPUDevice,

pub const Config = struct {
    title: [:0]const u8,
    width: u32 = 1280,
    height: u32 = 720,
    resizable: bool = true,
    highdpi: bool = true,
    vsync: bool = false,
    frames_in_flight: u32 = 2,

    debug_gpu: bool = builtin.mode == .Debug,
    shader_formats: sdl.SDL_GPUShaderFormat = sdl.SDL_GPU_SHADERFORMAT_SPIRV,
    driver_name: ?[:0]const u8 = null,
};

pub fn init(config: Config) !Window {
    if (!sdl.SDL_InitSubSystem(sdl.SDL_INIT_VIDEO)) {
        return error.FailedToInitSdl;
    }
    var flags: sdl.Uint32 = sdl.SDL_WINDOW_HIDDEN;
    if (config.resizable) flags |= sdl.SDL_WINDOW_RESIZABLE;
    if (config.highdpi) flags |= sdl.SDL_WINDOW_HIGH_PIXEL_DENSITY;
    const window = sdl.SDL_CreateWindow(config.title, @intCast(config.width), @intCast(config.height), flags) orelse {
        sdl.SDL_QuitSubSystem(sdl.SDL_INIT_VIDEO);
        return error.FailedToInitWindw;
    };
    // init the device
    const name_ptr: [*c]const u8 = if (config.driver_name) |name| name else null;
    const device = sdl.SDL_CreateGPUDevice(config.shader_formats, config.debug_gpu, name_ptr) orelse {
        sdl.SDL_DestroyWindow(window);
        sdl.SDL_QuitSubSystem(sdl.SDL_INIT_VIDEO);
        return error.FailedToInitGpu;
    };
    // claim the window
    if (!sdl.SDL_ClaimWindowForGPUDevice(device, window)) {
        sdl.SDL_DestroyGPUDevice(device);
        sdl.SDL_DestroyWindow(window);
        sdl.SDL_QuitSubSystem(sdl.SDL_INIT_VIDEO);
        return error.FailedToClaimWindow;
    }

    _ = sdl.SDL_SetGPUAllowedFramesInFlight(device, config.frames_in_flight);
    const present_mode: c_uint = if (config.vsync) sdl.SDL_GPU_PRESENTMODE_VSYNC else sdl.SDL_GPU_PRESENTMODE_IMMEDIATE;
    _ = sdl.SDL_SetGPUSwapchainParameters(device, window, sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, present_mode);

    _ = sdl.SDL_ShowWindow(window);
    return .{ .ptr = window, .device_ptr = device };
}

/// r, g, b, a in [0, 1]
pub fn clearColor(window: *Window, r: f32, g: f32, b: f32, a: f32) !void {
    const command = sdl.SDL_AcquireGPUCommandBuffer(window.device_ptr) orelse return error.FailedToAcquireBuffer;
    // wait for the swapchain
    var swapchain_texture: ?*sdl.SDL_GPUTexture = null;
    var swapchain_height: sdl.Uint32 = 0;
    var swapchain_width: sdl.Uint32 = 0;
    if (!sdl.SDL_WaitAndAcquireGPUSwapchainTexture(command, window.ptr, &swapchain_texture, &swapchain_width, &swapchain_height)) {
        _ = sdl.SDL_CancelGPUCommandBuffer(command);
        return error.FailedToAcquireSwapchain;
    }
    var color_target: sdl.SDL_GPUColorTargetInfo = .{
        .texture = swapchain_texture.?,
        .mip_level = 0,
        .layer_or_depth_plane = 0,
        .clear_color = .{ .r = r, .g = g, .b = b, .a = a },
        .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl.SDL_GPU_STOREOP_STORE,
        .resolve_texture = null,
        .resolve_mip_level = 0,
        .resolve_layer = 0,
        .cycle = false,
        .cycle_resolve_texture = false,
    };
    const render_pass = sdl.SDL_BeginGPURenderPass(command, &color_target, 1, null) orelse {
        _ = sdl.SDL_CancelGPUCommandBuffer(command);
        return error.FailedToBeginRenderPass;
    };
    sdl.SDL_EndGPURenderPass(render_pass);
    if (!sdl.SDL_SubmitGPUCommandBuffer(command)) return error.FailedToSubmit;
}

pub fn deinit(window: *Window) void {
    _ = sdl.SDL_WaitForGPUIdle(window.device_ptr);
    sdl.SDL_ReleaseWindowFromGPUDevice(window.device_ptr, window.ptr);
    sdl.SDL_DestroyGPUDevice(window.device_ptr);
    sdl.SDL_DestroyWindow(window.ptr);
    sdl.SDL_QuitSubSystem(sdl.SDL_INIT_VIDEO);
}

const sdl = @import("sdl");
const builtin = @import("builtin");
const Window = @This();

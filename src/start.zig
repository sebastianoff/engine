pub const std_options: std.Options = .{
    .logFn = writer.log,
};

const mainFn = *const fn (root: *const Root) callconv(.c) void;
const frameFn = *const fn (frame: *Root.Frame) callconv(.c) bool;
const deinitFn = *const fn () callconv(.c) void;

pub const Lib = struct {
    source: []const u8 = &.{},
    mtime: i128 = 0,
    /// current live copy path
    source_hot: ?[]u8 = null,
    dyn: ?std.DynLib = null,
    // function pointers
    mainFn: ?mainFn = null,
    frameFn: ?frameFn = null,
    deinitFn: ?deinitFn = null,

    index: usize = 0,

    pub fn init(lib: *Lib, allocator: std.mem.Allocator, source: []const u8) !void {
        lib.* = .{
            .source = try allocator.dupe(u8, source),
        };
        lib.mtime = try currentMtime(source);
    }

    pub fn deinit(lib: *Lib, allocator: std.mem.Allocator) void {
        if (lib.deinitFn) |f| f();
        if (lib.dyn) |*l| l.close();
        if (lib.source_hot) |path| {
            std.fs.cwd().deleteFile(path) catch {};
            allocator.free(path);
        }
        allocator.free(lib.source);
    }

    fn initFresh(lib: *Lib, allocator: std.mem.Allocator) !void {
        if (lib.dyn) |*l| {
            if (lib.deinitFn) |f| f();
            l.close();
            lib.mainFn = null;
            lib.frameFn = null;
            lib.deinitFn = null;
        }
        if (lib.source_hot) |p| {
            std.fs.cwd().deleteFile(p) catch {};
            allocator.free(p);
            lib.source_hot = null;
        }
        const hot = try lib.initHotPath(allocator);
        errdefer {
            std.fs.cwd().deleteFile(hot) catch {};
            allocator.free(hot);
        }
        try lib.copySrcTo(allocator, hot);
        lib.dyn = try open(hot);
        try lib.bind();
        lib.source_hot = hot;
    }

    pub fn currentMtime(path: []const u8) !i128 {
        const stat = try std.fs.cwd().statFile(path);
        return @intCast(stat.mtime);
    }

    fn initHotPath(lib: *Lib, allocator: std.mem.Allocator) ![]u8 {
        lib.index += 1;
        const dir_path = std.fs.path.dirname(lib.source) orelse ".";
        const base = std.fs.path.basename(lib.source);
        const tmp_base = try std.fmt.allocPrint(allocator, "{s}.hot.{d}{s}", .{ std.fs.path.stem(base), lib.index, std.fs.path.extension(base) });
        defer allocator.free(tmp_base);
        return try std.fs.path.join(allocator, &.{ dir_path, tmp_base });
    }

    fn copySrcTo(lib: *Lib, allocator: std.mem.Allocator, dst: []const u8) !void {
        const dir_path = std.fs.path.dirname(dst) orelse ".";
        var dir = try std.fs.openDirAbsolute(dir_path, .{ .access_sub_paths = true });
        defer dir.close();

        var src_file = try std.fs.openFileAbsolute(lib.source, .{ .mode = .read_only });
        defer src_file.close();
        const data = try src_file.readToEndAlloc(allocator, 64 * 1024 * 1024);
        defer allocator.free(data);

        const base_dst = std.fs.path.basename(dst);
        var f = try dir.createFile(base_dst, .{ .truncate = true, .read = true });
        defer f.close();

        try f.writeAll(data);
    }

    fn open(path: []const u8) std.DynLib.Error!std.DynLib {
        var attemps: u32 = 0;
        while (true) {
            const lib = std.DynLib.open(path) catch |err| {
                if (attemps < 30) {
                    std.Thread.sleep(50 * std.time.ns_per_ms);
                    attemps += 1;
                    continue;
                }
                return err;
            };
            return lib;
        }
    }

    fn bind(lib: *Lib) !void {
        var dynlib = lib.dyn.?;
        lib.mainFn = dynlib.lookup(mainFn, "_main") orelse return error.Symbol_main;
        lib.frameFn = dynlib.lookup(frameFn, "_frame") orelse return error.Symbol_frame;
        lib.deinitFn = dynlib.lookup(deinitFn, "_deinit") orelse return error.Symbol_deinit;
    }
};

pub fn main() !u8 {
    log.debug("hello, world!", .{});
    log.debug("mode: {[mode]s}", .{ .mode = @tagName(builtin.mode) });
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const gpa, const debug = switch (builtin.mode) {
        .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
        .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
    };
    defer if (debug) {
        _ = debug_allocator.deinit();
    };
    var arena_allocator: std.heap.ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const allocator = arena_allocator.allocator();
    // cli
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 2) std.process.fatal("usage: {[self]s} [path]", .{ .self = args[0] });

    const path = try std.fs.cwd().realpathAlloc(allocator, args[1]);
    // running
    var lib: Lib = .{};
    try lib.init(allocator, path);
    defer lib.deinit(allocator);
    // init the window
    var window: Root.Window = try .init(.{ .title = "TODO customizable title" });
    defer window.deinit();
    // load the game initially
    try lib.initFresh(allocator);
    if (lib.mainFn) |init| init(&.{});
    // main loop
    var timer = try std.time.Timer.start();
    var prev = timer.read();
    var running = true;

    var last_color: [4]f32 = .{ 0.10, 0.14, 0.18, 1.0 };
    var time_acc: f32 = 0;
    // TODO: mvoe out to Root.update() and Root.draw() so this becomes nice and clean
    std.log.debug("main loop", .{});
    while (running) {
        const mtime = try Lib.currentMtime(lib.source);
        if (mtime != lib.mtime) {
            lib.mtime = mtime;
            try lib.initFresh(allocator);
            if (lib.mainFn) |init| init(&.{});
        }

        var ev: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&ev) == true) {
            if (ev.type == sdl.SDL_EVENT_QUIT) running = false;
        }
        // timing
        const now = timer.read();
        const dt_s = @as(f32, @floatFromInt(now - prev)) / @as(f32, std.time.ns_per_s);
        prev = now;
        time_acc += dt_s;

        const cmd = sdl.SDL_AcquireGPUCommandBuffer(window.device_ptr) orelse {
            std.Thread.sleep(std.time.ns_per_ms);
            continue;
        };
        var swapchain_texture: ?*sdl.SDL_GPUTexture = null;
        var width: sdl.Uint32 = 0;
        var height: sdl.Uint32 = 0;
        if (!sdl.SDL_WaitAndAcquireGPUSwapchainTexture(cmd, window.ptr, &swapchain_texture, &width, &height)) {
            _ = sdl.SDL_CancelGPUCommandBuffer(cmd);
            std.Thread.sleep(std.time.ns_per_ms);
            continue;
        }

        var frame: Root.Frame = .{
            .time = time_acc,
            .dt = dt_s,
            .width = @floatFromInt(width),
            .height = @floatFromInt(height),
            .clear_color = last_color,
        };
        if (lib.frameFn) |update| {
            running = running and update(&frame);
        } else {
            running = false;
        }
        last_color = frame.clear_color;

        var target: sdl.SDL_GPUColorTargetInfo = .{
            .texture = swapchain_texture.?,
            .mip_level = 0,
            .layer_or_depth_plane = 0,
            .clear_color = .{ .r = frame.clear_color[0], .g = frame.clear_color[1], .b = frame.clear_color[2], .a = frame.clear_color[3] },
            .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
            .store_op = sdl.SDL_GPU_STOREOP_STORE,
            .resolve_texture = null,
            .resolve_mip_level = 0,
            .resolve_layer = 0,
            .cycle = false,
            .cycle_resolve_texture = false,
        };

        if (running) {
            if (sdl.SDL_BeginGPURenderPass(cmd, &target, 1, null)) |pass| {
                sdl.SDL_EndGPURenderPass(pass);
            }
            _ = sdl.SDL_SubmitGPUCommandBuffer(cmd);
        } else {
            _ = sdl.SDL_SubmitGPUCommandBuffer(cmd);
            break;
        }
        std.Thread.sleep(std.time.ns_per_ms);
    }
    return 0;
}

const std = @import("std");
const sdl = @import("sdl");
const log = std.log.scoped(.start);
const writer = @import("engine/writer.zig");
const Root = @import("engine/Root.zig");
const builtin = @import("builtin");

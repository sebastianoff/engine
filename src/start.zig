pub const std_options: std.Options = .{
    .logFn = writer.log,
};

pub const Lib = struct {
    source: []const u8 = &.{},
    mtime: i128 = 0,
    /// current live copy path
    source_hot: ?[]u8 = null,
    dyn: ?std.DynLib = null,
    // function pointers
    mainFn: ?Root.mainFn = null,
    frameFn: ?Root.frameFn = null,
    deinitFn: ?Root.deinitFn = null,
    name: [*:0]const u8 = "",

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
        lib.mainFn = dynlib.lookup(Root.mainFn, "_main") orelse return error.Symbol_main;
        lib.frameFn = dynlib.lookup(Root.frameFn, "_frame") orelse return error.Symbol_frame;
        lib.deinitFn = dynlib.lookup(Root.deinitFn, "_deinit") orelse return error.Symbol_deinit;
        if (dynlib.lookup(Root.nameFn, "_name")) |name| {
            lib.name = name();
        } else {
            lib.name = "tip: export _name() [*:0]const u8 to set the name for your window";
        }
    }
};

pub fn main() !u8 {
    log.debug("hello, world!", .{});
    log.debug("mode: {[mode]s}", .{ .mode = @tagName(builtin.mode) });
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator, const debug = switch (builtin.mode) {
        .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
        .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
    };
    defer if (debug) {
        _ = debug_allocator.deinit();
    };
    // cli
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 2) std.process.fatal("usage: {[self]s} [path]", .{ .self = args[0] });

    const path = try std.fs.cwd().realpathAlloc(allocator, args[1]);
    defer allocator.free(path);
    // running
    var lib: Lib = .{};
    try lib.init(allocator, path);
    defer lib.deinit(allocator);
    // load the game initially
    try lib.initFresh(allocator);
    if (lib.mainFn) |init| init(&.{});
    std.log.debug("_name = {s}", .{lib.name});
    // init the window
    var window: Root.Window = try .init(.{ .title = std.mem.span(lib.name) });
    defer window.deinit();
    // main loop
    var timer = try std.time.Timer.start();
    var prev = timer.read();
    var running = true;

    // last
    var last_color: @Vector(4, f32) = .{ 0.10, 0.14, 0.18, 1.0 };
    var last_title_owned = try allocator.dupe(u8, std.mem.span(lib.name));
    defer allocator.free(last_title_owned);

    var time_acc: f32 = 0;
    std.log.debug("main loop", .{});
    while (running) {
        const mtime = try Lib.currentMtime(lib.source);
        if (mtime != lib.mtime) {
            lib.mtime = mtime;
            try lib.initFresh(allocator);
            if (lib.mainFn) |init| init(&.{});
            if (!std.mem.eql(u8, std.mem.span(lib.name), last_title_owned)) {
                window.setName(std.mem.span(lib.name)) catch {};
                allocator.free(last_title_owned);
                last_title_owned = try allocator.dupe(u8, std.mem.span(lib.name));
                std.log.debug("(new) _name = {s}", .{lib.name});
            }
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

        var frame: Root.Frame = .{
            .time = time_acc,
            .dt = dt_s,
            .width = 0,
            .height = 0,
            .clear_color = last_color,
        };

        running = running and frame.update(&window, lib.frameFn);
        last_color = frame.clear_color;

        if (running) {
            if (!frame.draw(&window)) {
                std.Thread.sleep(std.time.ns_per_ms);
                continue;
            }
        } else {
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

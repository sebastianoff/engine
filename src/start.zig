pub fn main() !u8 {
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
    var lib = std.DynLib.open(path) catch |err| {
        std.process.fatal("failed to open '{[lib]s}': {[err]s}", .{ .lib = path, .err = @errorName(err) });
    };
    defer lib.close();
    if (lib.lookup(*const fn () callconv(.c) c_int, "_main")) |_main| {
        return @intCast(_main());
    } else {
        std.process.fatal("'{[lib]s}' does not export the required '_main' symbol", .{ .lib = path });
    }
}

const std = @import("std");
const builtin = @import("builtin");

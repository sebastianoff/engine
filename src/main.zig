var t: f32 = 0;

export fn _main(root: *const Root) callconv(.c) void {
    _ = root;
    writer.info("game init", .{});
    t = 0;
}

export fn _frame(frame: *Root.Frame) callconv(.c) bool {
    t += frame.dt;
    const s = 0.5 * (1 + std.math.sin(t));
    frame.clear_color = .{ 0.7 + 0.10 * s, 0.14 + 0.08 * s, 0.18 + 0.06 * s, 1.0 };
    return true;
}

export fn _deinit() callconv(.c) void {
    writer.info("game deinit", .{});
}

const Root = @import("engine/Root.zig");
const builtin = @import("builtin");
const writer = @import("writer.zig");
const std = @import("std");

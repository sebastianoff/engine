var t: f32 = 0;

export fn _name() [*:0]const u8 {
    return "boovoi";
}

export fn _main(root: *const Root) void {
    _ = root;
    writer.info("game init", .{});
    t = 0;
}

export fn _frame(frame: *Root.Frame) bool {
    t += frame.dt;
    const s = 1 * (1 + std.math.sin(t));
    frame.clear_color = .{ 0.1 + 0.10 * s, 0.14 + 0.08 * s, 0.18 + 0.06 * s, 1.0 };
    return true;
}

export fn _deinit() void {
    writer.info("game deinit", .{});
}

const Root = @import("engine/Root.zig");
const builtin = @import("builtin");
const writer = @import("engine/writer.zig");
const std = @import("std");

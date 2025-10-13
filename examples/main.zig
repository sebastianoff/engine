const std = @import("std");

pub export fn init() u8 {
    std.debug.print("Hello, World!\n", .{});
    return 0;
}

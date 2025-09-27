export fn _main() c_int {
    writer.info("Hello, world!", .{});
    writer.info("==================================", .{});
    writer.info(@embedFile("LICENSE"), .{});
    writer.info("==================================", .{});
    return 0;
}

const writer = @import("writer.zig");
const sdl = @import("sdl");
const std = @import("std");

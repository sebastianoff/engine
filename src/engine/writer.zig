pub const default_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe, .ReleaseFast, .ReleaseSmall => .info,
};

pub var level: std.log.Level = default_level;

pub const colors = .{
    .debug = .{.dim},
    .info = .{},
    .warn = .{ .bold, .magenta },
    .err = .{ .bold, .red },
};

pub fn logEnabled(comptime message_level: std.log.Level) bool {
    return @intFromEnum(message_level) <= @intFromEnum(level);
}

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (!logEnabled(message_level)) return;
    var stderr: std.fs.File = .stderr();
    var stderr_writer = stderr.writer(&.{});
    var w = &stderr_writer.interface;
    const tty: std.Io.tty.Config = .detect(stderr);
    w.writeAll(if (scope == default_log_scope) "" else @tagName(scope) ++ ": ") catch {};
    inline for (@field(colors, @tagName(message_level))) |color| {
        tty.setColor(w, color) catch {};
    }
    w.print(format, args) catch {};
    w.writeByte('\n') catch {};
    tty.setColor(w, .reset) catch {};
}

pub fn Scoped(comptime scope: @Type(.enum_literal)) type {
    return struct {
        pub fn err(
            comptime format: []const u8,
            args: anytype,
        ) void {
            @branchHint(.cold);
            log(.err, scope, format, args);
        }

        pub fn warn(
            comptime format: []const u8,
            args: anytype,
        ) void {
            log(.warn, scope, format, args);
        }

        pub fn info(
            comptime format: []const u8,
            args: anytype,
        ) void {
            log(.info, scope, format, args);
        }

        pub fn debug(
            comptime format: []const u8,
            args: anytype,
        ) void {
            log(.debug, scope, format, args);
        }
    };
}

pub const default_log_scope = .default;

pub const Default = Scoped(default_log_scope);

pub const err = Default.err;
pub const warn = Default.warn;
pub const info = Default.info;
pub const debug = Default.debug;

const std = @import("std");
const builtin = @import("builtin");

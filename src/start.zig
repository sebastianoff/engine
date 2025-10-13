//! Engine dynamic library loader.
const builtin = @import("builtin");
const std = @import("std");
const build_options = @import("build_options");

pub const signatures = struct {
    pub const init = struct {
        pub const ptr = *const fn () callconv(.c) u8;
        pub const name = "init";

        pub fn default() callconv(.c) u8 {
            return 0;
        }
    };
};

pub fn main() !u8 {
    // allocator setup
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator, const debug = switch (builtin.mode) {
        .ReleaseSafe, .Debug => .{ debug_allocator.allocator(), true },
        else => .{ std.heap.smp_allocator, false },
    };
    defer {
        if (debug) _ = debug_allocator.deinit();
    }
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    //  since we will open libraries that are relative to the runner, we will
    // set cwd to the runner directory to avoid any path-related issues
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    var dir = try std.fs.openDirAbsolute(try std.fs.selfExeDirPath(&buffer), .{});
    defer dir.close();
    try dir.setAsCwd();
    std.log.debug("now working in {s}", .{try std.fs.realpath(".", &buffer)});
    // and still, where lib is located is unguaranteed, so we will try some options
    const paths: []const []const u8 = &.{ ".", "..", "lib", "../lib", "../../lib" };
    const name = try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{
        builtin.target.libPrefix(),
        build_options.basename,
        builtin.target.dynamicLibSuffix(),
    });
    std.log.debug("name = {s}", .{name});

    var lib = lib: {
        for (paths) |path| {
            const full = try std.fs.path.join(gpa, &.{ path, name });
            std.log.debug("searching {s}", .{full});
            break :lib (std.DynLib.open(full) catch continue);
        }
        std.process.fatal("unable to locate '{s}' in {f}", .{ name, std.fs.path.fmtJoin(paths) });
    };
    defer lib.close();

    const init = lib.lookup(signatures.init.ptr, signatures.init.name) orelse signatures.init.default;
    return init();
}

fn printUsageFatal() noreturn {
    const usage =
        \\[path]
        \\
        \\path - Path to the dynamic library to load
        \\
    ;
    std.debug.print("usage: {s}", .{usage});
    std.process.exit(1);
}

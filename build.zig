const std = @import("std");

pub fn build(b: *std.Build) void {
    // standard options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(
        .{ .preferred_optimize_mode = .ReleaseFast },
    );
    // options
    const options = b.addOptions();
    const name_raw = b.option([]const u8, "name", "Name for the launcher executable") orelse "unknown";
    options.addOption([]const u8, "name", name_raw);

    const basename_raw = b.option([]const u8, "basename", "The base name of your module that the dynamic library will use") orelse "unknown";
    options.addOption([]const u8, "basename", basename_raw);

    const root_raw = b.option([]const u8, "root", "Root of the module that will be passed to the runner to execute") orelse std.debug.panic("the required 'root' option was not passed", .{});
    options.addOption([]const u8, "root", root_raw);
    // there's a weird segmentation fault on linux that happens on any functions
    // that call `std.debug.lockStderrWriter` if you do not link libc on both
    // runner and the module.
    const link_libc = target.result.os.tag == .linux;
    // runner executable
    const start_exe = b.addExecutable(.{
        .name = name_raw,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/start.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = link_libc,
            .imports = &.{
                .{ .name = "build_options", .module = options.createModule() },
            },
        }),
    });
    b.installArtifact(start_exe);
    // the module itself
    const root_lib = b.addLibrary(.{
        .name = basename_raw,
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path(root_raw),
            .target = target,
            .optimize = optimize,
            .link_libc = link_libc,
        }),
    });
    b.installArtifact(root_lib);
}

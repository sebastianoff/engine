pub fn build(b: *std.Build) void {
    // steps
    const run_step = b.step("run", "Run the app");
    const fmt_step = b.step("fmt", "Modify source files in place to have conforming formatting");
    const test_fmt_step = b.step("test-fmt", "Check source files having conforming formatting");
    // standard options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });
    // sdl.
    const header = b.addWriteFiles().add("sdl.h", "#include <SDL3/SDL.h>\n");
    const sdl_mod = b.addTranslateC(.{ .root_source_file = header, .target = target, .optimize = optimize }).createModule();
    // root.
    const app_exe = b.addExecutable(.{
        .name = "app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "sdl", .module = sdl_mod },
            },
        }),
    });
    app_exe.root_module.linkSystemLibrary("sdl3", .{ .use_pkg_config = .yes, .preferred_link_mode = .dynamic, .needed = true });
    b.installArtifact(app_exe);
    // run
    run_step.dependOn(step: {
        const run_cmd = b.addRunArtifact(app_exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        break :step &run_cmd.step;
    });
    // fmt
    const fmt_paths: []const []const u8 = &.{ "build.zig", "src" };

    fmt_step.dependOn(&b.addFmt(.{ .paths = fmt_paths }).step);
    test_fmt_step.dependOn(&b.addFmt(.{ .paths = fmt_paths, .check = true }).step);
}

const std = @import("std");

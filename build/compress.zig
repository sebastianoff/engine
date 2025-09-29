pub const Options = struct {
    /// source directory to scan for pngs
    /// TODO: LazyPath
    src_dir: []const u8,
    install_dir: std.Build.InstallDir = .prefix,
    dest_subdir: []const u8 = "share/assets",
};

/// requires 'oxipng' in path
pub fn addStep(b: *std.Build, options: Options) *std.Build.Step {
    const step = b.step("compress", "Compress PNG assets and install them");
    var arena: std.heap.ArenaAllocator = .init(b.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const toktx = b.findProgram(&.{"toktx"}, &.{}) catch {
        const fail = b.addFail("toktx not found on PATH");
        step.dependOn(&fail.step);
        return step;
    };
    // collect relative png paths
    var rel_entries: std.ArrayList([]const u8) = .empty;
    defer rel_entries.deinit(allocator);
    collectRec(allocator, options.src_dir, "", &rel_entries) catch |err| {
        std.debug.print("error collecting from '{[dir]s}': {[err]s}", .{ .dir = options.src_dir, .err = @errorName(err) });
        return step;
    };
    for (rel_entries.items) |entry| {
        const src_path = b.pathJoin(&.{ options.src_dir, entry });

        const toktx_run = b.addSystemCommand(&.{toktx});
        toktx_run.setName(b.fmt("toktx {s}", .{entry}));
        toktx_run.addArgs(&.{ "--uastc", "4", "--zcmp", "18" });
        const rel_ktx = replaceExt(allocator, entry, ".ktx2") catch b.fmt("{s}.ktx2", .{entry});
        const out_basename_ktx = cacheBasename(allocator, rel_ktx) catch rel_ktx;
        const out_lp_ktx = toktx_run.addOutputFileArg(out_basename_ktx);
        toktx_run.addFileArg(b.path(src_path));

        const dest_rel_ktx = if (options.dest_subdir.len == 0)
            rel_ktx
        else
            b.pathJoin(&.{ options.dest_subdir, rel_ktx });

        const install_ktx = b.addInstallFileWithDir(out_lp_ktx, options.install_dir, dest_rel_ktx);
        step.dependOn(&install_ktx.step);
    }
    return step;
}

fn hasPngExt(name: []const u8) bool {
    if (name.len < 4) return false;
    const ext = name[name.len - 4 ..];
    return std.ascii.eqlIgnoreCase(ext, ".png");
}

pub fn collectRec(allocator: std.mem.Allocator, base_dir: []const u8, prefix: []const u8, out: *std.ArrayList([]const u8)) !void {
    var dir = try std.fs.cwd().openDir(base_dir, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .file => {
                if (hasPngExt(entry.name)) {
                    const rel = if (prefix.len != 0) try std.fs.path.join(allocator, &.{ prefix, entry.name }) else try allocator.dupe(u8, entry.name);
                    try out.append(allocator, rel);
                }
            },
            .directory => {
                // we'll scan recursively
                // skip hidden dirs
                if (entry.name.len != 0 and (entry.name[0] == '.' or entry.name[0] == '_')) continue;
                const child_base = try std.fs.path.join(allocator, &.{ base_dir, entry.name });
                const child_prefix = if (prefix.len != 0) try std.fs.path.join(allocator, &.{ prefix, entry.name }) else try allocator.dupe(u8, entry.name);
                try collectRec(allocator, child_base, child_prefix, out);
            },
            else => {},
        }
    }
}

fn cacheBasename(allocator: std.mem.Allocator, rel: []const u8) ![]const u8 {
    const s = try allocator.dupe(u8, rel);
    for (s) |*c| {
        switch (c.*) {
            '/', '\\', ':' => c.* = '_',
            else => {},
        }
    }
    return s;
}

fn replaceExt(allocator: std.mem.Allocator, rel: []const u8, new_ext: []const u8) ![]u8 {
    const old_ext = std.fs.path.extension(rel);
    const stem = rel[0 .. rel.len - old_ext.len];
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ stem, new_ext });
}

const std = @import("std");

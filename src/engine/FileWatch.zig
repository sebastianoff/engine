const std = @import("std");
/// inotify instance fd
fd: std.posix.fd_t,

pub const Event = struct {
    wd: i32,
    mask: u32,
    cookie: u32,
    name: []const u8,

    pub fn asMask(event: Event) Mask {
        return .fromBits(event.mask);
    }
};

pub const Mask = struct {
    access: bool = false, // IN_ACCESS
    attrib: bool = false, // IN_ATTRIB
    close_write: bool = false, // IN_CLOSE_WRITE
    close_nowrite: bool = false, // IN_CLOSE_NOWRITE
    create: bool = false, // IN_CREATE
    delete: bool = false, // IN_DELETE
    delete_self: bool = false, // IN_DELETE_SELF
    modify: bool = false, // IN_MODIFY
    move_self: bool = false, // IN_MOVE_SELF
    moved_from: bool = false, // IN_MOVED_FROM
    moved_to: bool = false, // IN_MOVED_TO
    open: bool = false, // IN_OPEN

    close: bool = false, // IN_CLOSE = IN_CLOSE_WRITE | IN_CLOSE_NOWRITE
    move: bool = false, // IN_MOVE = IN_MOVED_FROM | IN_MOVED_TO

    only_dir: bool = false, // IN_ONLYDIR
    dont_follow: bool = false, // IN_DONT_FOLLOW
    excl_unlink: bool = false, // IN_EXCL_UNLINK
    mask_add: bool = false, // IN_MASK_ADD
    oneshot: bool = false, // IN_ONESHOT

    is_dir: bool = false, // IN_ISDIR
    ignored: bool = false, // IN_IGNORED
    q_overflow: bool = false, // IN_Q_OVERFLOW
    unmount: bool = false, // IN_UNMOUNT

    pub fn toBits(mask: Mask) u32 {
        const IN = std.os.linux.IN;
        var bits: u32 = 0;

        if (mask.access) bits |= IN.ACCESS;
        if (mask.attrib) bits |= IN.ATTRIB;
        if (mask.close_write) bits |= IN.CLOSE_WRITE;
        if (mask.close_nowrite) bits |= IN.CLOSE_NOWRITE;
        if (mask.create) bits |= IN.CREATE;
        if (mask.delete) bits |= IN.DELETE;
        if (mask.delete_self) bits |= IN.DELETE_SELF;
        if (mask.modify) bits |= IN.MODIFY;
        if (mask.move_self) bits |= IN.MOVE_SELF;
        if (mask.moved_from) bits |= IN.MOVED_FROM;
        if (mask.moved_to) bits |= IN.MOVED_TO;
        if (mask.open) bits |= IN.OPEN;

        if (mask.close) bits |= IN.CLOSE;
        if (mask.move) bits |= IN.MOVE;

        if (mask.only_dir) bits |= IN.ONLYDIR;
        if (mask.dont_follow) bits |= IN.DONT_FOLLOW;
        if (mask.excl_unlink) bits |= IN.EXCL_UNLINK;
        if (mask.mask_add) bits |= IN.MASK_ADD;
        if (mask.oneshot) bits |= IN.ONESHOT;

        return bits;
    }

    pub fn fromBits(bits: u32) Mask {
        const IN = std.os.linux.IN;
        return .{
            .access = (bits & IN.ACCESS) != 0,
            .attrib = (bits & IN.ATTRIB) != 0,
            .close_write = (bits & IN.CLOSE_WRITE) != 0,
            .close_nowrite = (bits & IN.CLOSE_NOWRITE) != 0,
            .create = (bits & IN.CREATE) != 0,
            .delete = (bits & IN.DELETE) != 0,
            .delete_self = (bits & IN.DELETE_SELF) != 0,
            .modify = (bits & IN.MODIFY) != 0,
            .move_self = (bits & IN.MOVE_SELF) != 0,
            .moved_from = (bits & IN.MOVED_FROM) != 0,
            .moved_to = (bits & IN.MOVED_TO) != 0,
            .open = (bits & IN.OPEN) != 0,

            .close = (bits & IN.CLOSE) != 0, // composite
            .move = (bits & IN.MOVE) != 0, // composite

            .only_dir = (bits & IN.ONLYDIR) != 0,
            .dont_follow = (bits & IN.DONT_FOLLOW) != 0,
            .excl_unlink = (bits & IN.EXCL_UNLINK) != 0,
            .mask_add = (bits & IN.MASK_ADD) != 0,
            .oneshot = (bits & IN.ONESHOT) != 0,

            .is_dir = (bits & IN.ISDIR) != 0,
            .ignored = (bits & IN.IGNORED) != 0,
            .q_overflow = (bits & IN.Q_OVERFLOW) != 0,
            .unmount = (bits & IN.UNMOUNT) != 0,
        };
    }
};

pub fn open() !FileWatch {
    const flags: u32 = std.os.linux.IN.CLOEXEC | std.os.linux.IN.NONBLOCK;
    return .{ .fd = try std.posix.inotify_init1(flags) };
}

pub fn close(w: *FileWatch) void {
    if (w.fd != -1) {
        std.posix.close(w.fd);
        w.fd = -1;
    }
}

pub fn appendWatch(w: *const FileWatch, pathname: []const u8, mask: Mask) !i32 {
    return std.posix.inotify_add_watch(w.fd, pathname, mask.toBits());
}

pub fn removeWatch(w: *const FileWatch, wd: i32) void {
    std.posix.inotify_rm_watch(w.fd, wd);
}

pub fn fdNo(w: *const FileWatch) std.posix.fd_t {
    return w.fd;
}

pub fn iterator(w: *const FileWatch, buffer: []u8) Iterator {
    return .init(w, buffer);
}

pub const Iterator = struct {
    fd: std.posix.fd_t,
    buffer: []u8,
    len: usize = 0,
    off: usize = 0,

    pub fn init(w: *const FileWatch, buffer: []u8) Iterator {
        std.debug.assert(buffer.len >= @sizeOf(std.os.linux.inotify_event));
        return .{ .fd = w.fd, .buffer = buffer };
    }

    pub fn next(it: *Iterator) !?Event {
        const Header = std.os.linux.inotify_event;
        const header_size: usize = @sizeOf(Header);

        while (true) {
            if (it.off + header_size <= it.len) {
                @branchHint(.likely); // There's no benefit but I actually just love this built-in.
                // On x86/x86_64, unaligned 4/8-byte loads are fine and codegen looks better.
                // It seems like Zig emits field loads with memory operands rather than copying
                // into a temporary first, which is exactly what bytesAsValue has shown here.
                const base: [*]const u8 = it.buffer.ptr + it.off;
                const header: *align(1) const Header = @ptrCast(base);
                // NUL-terminated and padded.
                const name_len = header.len;
                const rec_len: usize = header_size + name_len;
                // The kernel shouldn’t even split events across reads, but just to be safe
                // against corruption and too small buffers.
                if (rec_len > it.buffer.len) return error.RecordTooBig;
                if (it.off + rec_len > it.len) return error.UnexpectedPartialEvent;
                // Also includes NUL.
                var name = it.buffer[it.off + header_size .. it.off + rec_len];
                // Then just trim all the training NULs we had.
                // Which, again, improves codegen, so we don't get a massive
                // search.
                var end = name.len;
                while (end != 0 and name[end - 1] == 0) end -= 1;
                name = name[0..end];

                const event: Event = .{
                    .wd = header.wd,
                    .mask = header.mask,
                    .cookie = header.cookie,
                    .name = name,
                };
                it.off += rec_len;
                return event;
            }
            // Refill if we don't have enough bytes.
            // Never inlining helps to kind of shrink the caller's code because the
            // errno switch/table isn't included.
            const refillNeverInline = try @call(.never_inline, Iterator.refill, .{it});
            if (!refillNeverInline) return null; // WouldBlock / no data
        }
    }

    pub fn waitNext(it: *Iterator) !Event {
        if (try it.next()) |event| return event;

        var fd = [_]std.posix.pollfd{.{ .fd = it.fd, .events = std.posix.POLL.IN, .revents = 0 }};
        _ = try std.posix.poll(&fd, -1);
        while (true) {
            if (try it.next()) |ev| return ev;
            _ = try std.posix.poll(&fd, -1);
        }
    }

    fn refill(it: *Iterator) !bool {
        it.off = 0;
        it.len = 0;

        const n = std.posix.read(it.fd, it.buffer) catch |err| {
            if (err == error.WouldBlock) return false;
            return err;
        };

        it.len = n;
        return n != 0;
    }
};

test {
    var fw: FileWatch = try .open();
    defer fw.close();

    try std.testing.expect(fw.fd != -1);
    try std.testing.expectEqual(fw.fd, fw.fdNo());

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const alloc = std.testing.allocator;
    const dir_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(dir_path);

    const mask: Mask = .{
        .create = true,
        .moved_from = true,
        .moved_to = true,
        .delete = true,
    };
    const wd = try fw.appendWatch(dir_path, mask);
    try std.testing.expect(wd >= 0);

    var buffer: [4096]u8 = undefined;
    var it = fw.iterator(&buffer);

    try std.testing.expect((try it.next()) == null);

    {
        var f = try tmp.dir.createFile("one", .{ .read = true, .exclusive = true });
        try f.writeAll("abc");
        f.close();
    }
    const ev_create = try it.waitNext();
    try std.testing.expect(ev_create.asMask().create);
    try std.testing.expectEqualStrings("one", ev_create.name);

    try tmp.dir.rename("one", "two");

    var seen_from = false;
    var seen_to = false;
    var cookie_from: u32 = 0;
    var cookie_to: u32 = 0;

    var attempts: usize = 0;
    while (!(seen_from and seen_to) and attempts < 8) : (attempts += 1) {
        const e = try it.waitNext();
        const m = e.asMask();
        if (m.moved_from and !seen_from and std.mem.eql(u8, e.name, "one")) {
            seen_from = true;
            cookie_from = e.cookie;
        } else if (m.moved_to and !seen_to and std.mem.eql(u8, e.name, "two")) {
            seen_to = true;
            cookie_to = e.cookie;
        }
    }
    try std.testing.expect(seen_from and seen_to);
    try std.testing.expect(cookie_from == cookie_to);

    try tmp.dir.deleteFile("two");
    const ev_delete = try it.waitNext();
    try std.testing.expect(ev_delete.asMask().delete);
    try std.testing.expectEqualStrings("two", ev_delete.name);

    fw.removeWatch(wd);
}

const FileWatch = @This();

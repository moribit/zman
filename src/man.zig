const std = @import("std");
pub const Reference = struct { page: []const u8, section: u8 = 2, relation: enum { direct, related } = .direct };
const Mapping = struct { symbol: []const u8, reference: Reference };
pub const mappings = [_]Mapping{
    .{ .symbol = "std.posix.read", .reference = .{ .page = "read" } },
    .{ .symbol = "std.posix.openat", .reference = .{ .page = "openat" } },
    .{ .symbol = "std.posix.openatZ", .reference = .{ .page = "openat" } },
    .{ .symbol = "std.posix.poll", .reference = .{ .page = "poll" } },
    .{ .symbol = "std.posix.ppoll", .reference = .{ .page = "ppoll" } },
    .{ .symbol = "std.posix.getpeername", .reference = .{ .page = "getpeername" } },
    .{ .symbol = "std.posix.setsockopt", .reference = .{ .page = "setsockopt" } },
    .{ .symbol = "std.posix.mmap", .reference = .{ .page = "mmap" } },
    .{ .symbol = "std.posix.munmap", .reference = .{ .page = "munmap" } },
    .{ .symbol = "std.posix.mremap", .reference = .{ .page = "mremap" } },
    .{ .symbol = "std.posix.msync", .reference = .{ .page = "msync" } },
    .{ .symbol = "std.posix.kill", .reference = .{ .page = "kill" } },
    .{ .symbol = "std.posix.getppid", .reference = .{ .page = "getppid" } },
    .{ .symbol = "std.posix.gethostname", .reference = .{ .page = "gethostname" } },
    .{ .symbol = "std.posix.uname", .reference = .{ .page = "uname" } },
    .{ .symbol = "std.posix.sigaction", .reference = .{ .page = "sigaction" } },
    .{ .symbol = "std.posix.sigprocmask", .reference = .{ .page = "sigprocmask" } },
    .{ .symbol = "std.posix.getrusage", .reference = .{ .page = "getrusage" } },
    .{ .symbol = "std.posix.fdatasync", .reference = .{ .page = "fdatasync" } },
    .{ .symbol = "std.posix.sync", .reference = .{ .page = "sync" } },
    .{ .symbol = "std.posix.syncfs", .reference = .{ .page = "syncfs" } },
    .{ .symbol = "std.posix.tcgetattr", .reference = .{ .page = "tcgetattr", .section = 3 } },
    .{ .symbol = "std.posix.tcsetattr", .reference = .{ .page = "tcsetattr", .section = 3 } },
    .{ .symbol = "std.os.linux.open", .reference = .{ .page = "open" } },
    .{ .symbol = "std.os.linux.read", .reference = .{ .page = "read" } },
    .{ .symbol = "std.os.linux.write", .reference = .{ .page = "write" } },
    .{ .symbol = "std.os.linux.close", .reference = .{ .page = "close" } },
    .{ .symbol = "std.os.linux.poll", .reference = .{ .page = "poll" } },
    .{ .symbol = "std.os.linux.epoll_create", .reference = .{ .page = "epoll_create" } },
    .{ .symbol = "std.os.linux.epoll_create1", .reference = .{ .page = "epoll_create1" } },
    .{ .symbol = "std.os.linux.epoll_ctl", .reference = .{ .page = "epoll_ctl" } },
    .{ .symbol = "std.os.linux.epoll_wait", .reference = .{ .page = "epoll_wait" } },
    .{ .symbol = "std.os.linux.socket", .reference = .{ .page = "socket" } },
    .{ .symbol = "std.os.linux.bind", .reference = .{ .page = "bind" } },
    .{ .symbol = "std.os.linux.listen", .reference = .{ .page = "listen" } },
    .{ .symbol = "std.os.linux.accept", .reference = .{ .page = "accept" } },
    .{ .symbol = "std.os.linux.accept4", .reference = .{ .page = "accept4" } },
    .{ .symbol = "std.os.linux.connect", .reference = .{ .page = "connect" } },
    .{ .symbol = "std.os.linux.sendto", .reference = .{ .page = "sendto" } },
    .{ .symbol = "std.os.linux.recvfrom", .reference = .{ .page = "recvfrom" } },
    .{ .symbol = "std.os.linux.sendmsg", .reference = .{ .page = "sendmsg" } },
    .{ .symbol = "std.os.linux.recvmsg", .reference = .{ .page = "recvmsg" } },
    .{ .symbol = "std.c.open", .reference = .{ .page = "open" } },
    .{ .symbol = "std.c.read", .reference = .{ .page = "read" } },
    .{ .symbol = "std.c.write", .reference = .{ .page = "write" } },
    .{ .symbol = "std.c.close", .reference = .{ .page = "close" } },
    .{ .symbol = "std.c.poll", .reference = .{ .page = "poll" } },
    .{ .symbol = "std.c.socket", .reference = .{ .page = "socket" } },
    .{ .symbol = "std.c.bind", .reference = .{ .page = "bind" } },
    .{ .symbol = "std.c.listen", .reference = .{ .page = "listen" } },
    .{ .symbol = "std.c.accept", .reference = .{ .page = "accept" } },
    .{ .symbol = "std.c.connect", .reference = .{ .page = "connect" } },
    .{ .symbol = "std.c.send", .reference = .{ .page = "send" } },
    .{ .symbol = "std.c.recv", .reference = .{ .page = "recv" } },
    .{ .symbol = "std.Io.Dir.openFile", .reference = .{ .page = "open", .relation = .related } },
};
pub fn reference(symbol: []const u8) ?Reference {
    for (mappings) |mapping| if (std.mem.eql(u8, mapping.symbol, symbol)) return mapping.reference;
    return null;
}
pub fn describe(a: std.mem.Allocator, ref: ?Reference) ![]const u8 {
    if (ref) |r| return std.fmt.allocPrint(a, "SYSTEM MANUAL\n\nSystem manual on this host:\n    {s}({d}) [{s}]\n", .{ r.page, r.section, @tagName(r.relation) });
    return a.dupe(u8, "SYSTEM MANUAL\n\nNo explicit system manual mapping for this symbol.\n");
}
// exe is injected in tests. Production always uses PATH's man, without a shell.
pub fn open(io: std.Io, ref: Reference, exe: []const u8) !void {
    const section = [_]u8{'0' + ref.section};
    var child = std.process.spawn(io, .{ .argv = &.{ exe, &section, ref.page }, .stderr = .ignore }) catch |err| switch (err) {
        error.FileNotFound => return error.ManCommandNotFound,
        else => return error.ManCommandFailed,
    };
    defer child.kill(io);
    const term = try child.wait(io);
    if (term != .exited) return error.ManCommandFailed;
    switch (term.exited) {
        0 => {},
        1, 16 => return error.ManualPageNotInstalled,
        else => return error.ManCommandFailed,
    }
}
test "explicit host manual metadata" {
    const r = reference("std.posix.read").?;
    try std.testing.expectEqualStrings("read", r.page);
    try std.testing.expectEqual(@as(u8, 2), r.section);
    try std.testing.expect(r.relation == .direct);
    try std.testing.expect(reference("std.ArrayList") == null);
    try std.testing.expect(reference("std.Io.Dir.openFile").?.relation == .related);
    const json = try std.json.Stringify.valueAlloc(std.testing.allocator, r, .{});
    defer std.testing.allocator.free(json);
    try std.testing.expectEqualStrings("{\"page\":\"read\",\"section\":2,\"relation\":\"direct\"}", json);
}
test "man process argv, missing command and page" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "fake-man", .data = "#!/bin/sh\n[ \"$1\" = 2 ] && [ \"$2\" = read ] || exit 3\nexit 0\n", .flags = .{ .permissions = .executable_file } });
    const path = try tmp.dir.realPathFileAlloc(io, "fake-man", a);
    defer a.free(path);
    try open(io, reference("std.posix.read").?, path);
    try tmp.dir.writeFile(io, .{ .sub_path = "fake-man", .data = "#!/bin/sh\nexit 16\n", .flags = .{ .permissions = .executable_file } });
    try std.testing.expectError(error.ManualPageNotInstalled, open(io, reference("std.posix.read").?, path));
    try std.testing.expectError(error.ManCommandNotFound, open(io, reference("std.posix.read").?, "/zman-does-not-exist/man"));
}

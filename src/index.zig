const std = @import("std");
pub const Kind = enum { function, @"const", @"var", @"struct", @"enum", @"union", @"opaque", error_set, namespace, type, unknown };
pub const Entry = struct {
    fq_name: []const u8,
    short_name: []const u8,
    kind: Kind,
    visibility: []const u8 = "pub",
    signature: []const u8,
    docs: []const u8,
    source_path: []const u8,
    source_line: u32,
    declaration_start: u32,
    declaration_end: u32,
};
pub const File = struct { path: []const u8, size: u64, mtime: i96 };
pub const Index = struct { entries: []const Entry, files: []const File };
pub fn read(a: std.mem.Allocator, io: std.Io, path: []const u8) ![:0]u8 {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(32 * 1024 * 1024));
    defer a.free(bytes);
    return a.dupeSentinel(u8, bytes, 0);
}

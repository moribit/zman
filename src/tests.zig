const std = @import("std");
const parser = @import("parser.zig");
const search = @import("search.zig");
const render = @import("render.zig");
test "public AST declarations, docs, nested and imports" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try std.fs.path.resolve(a, &.{"tests"});
    var builder: parser.Builder = .{ .a = a, .io = std.testing.io, .root = root };
    const index = try builder.build();
    const read = index.entries[search.exact(index.entries, "std.read").?];
    try std.testing.expectEqualStrings("pub fn read(buf: []u8) usize", read.signature);
    try std.testing.expectEqualStrings("/// Reads bytes, unchanged.", read.docs);
    try std.testing.expect(search.exact(index.entries, "std.hidden") == null);
    try std.testing.expect(search.exact(index.entries, "std.Box.Mode") != null);
    try std.testing.expect(search.exact(index.entries, "std.child.answer") != null);
    const child = index.entries[search.exact(index.entries, "std.child").?];
    try std.testing.expectEqualStrings("//! Child container documentation.", child.docs);
    const hits = try search.search(a, index.entries, "open file", 10);
    try std.testing.expectEqualStrings("std.Box.openFile", index.entries[hits[0].entry_index].fq_name);
    const human = try render.human(a, read, "0.17.0", false);
    const expected = try std.fmt.allocPrint(a, "std.read\n\nfunction\n\nSIGNATURE\n\npub fn read(buf: []u8) usize\n\nDESCRIPTION\n\nReads bytes, unchanged.\n\nSOURCE\n\n{s}:3\n\nZIG VERSION\n\n0.17.0\n", .{read.source_path});
    try std.testing.expectEqualStrings(expected, human);
}

test "cache roundtrip, corruption and source invalidation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(io, ".", a);
    const source_path = try std.fs.path.join(a, &.{ root, "std.zig" });
    try tmp.dir.writeFile(io, .{ .sub_path = "std.zig", .data = "pub const answer = 42;" });
    var builder: parser.Builder = .{ .a = a, .io = io, .root = root };
    const index = try builder.build();
    const cache = @import("cache.zig");
    const filename = try std.fs.path.join(a, &.{ root, "index.json" });
    try cache.save(a, io, filename, "test-id", index);
    const loaded = try cache.load(a, io, filename, "test-id");
    try std.testing.expectEqualStrings("std.answer", loaded.entries[0].fq_name);
    try std.testing.expectError(error.CacheInvalidated, cache.load(a, io, filename, "other-id"));
    try tmp.dir.writeFile(io, .{ .sub_path = "std.zig", .data = "pub const answer = 123456;" });
    try std.testing.expectError(error.CacheInvalidated, cache.load(a, io, filename, "test-id"));
    try tmp.dir.writeFile(io, .{ .sub_path = "index.json", .data = "{ broken" });
    _ = cache.load(a, io, filename, "test-id") catch return;
    _ = source_path;
    return error.TestExpectedError;
}

test "dotted typo suggestions outrank partial prose" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Entry = @import("index.zig").Entry;
    const entries = [_]Entry{
        .{ .fq_name = "std.posix.read", .short_name = "read", .kind = .function, .signature = "pub fn read() void", .docs = "/// Read bytes.", .source_path = "posix.zig", .source_line = 1, .declaration_start = 0, .declaration_end = 1 },
        .{ .fq_name = "std.a", .short_name = "a", .kind = .@"const", .signature = "pub const a = 0", .docs = "/// Read unrelated text.", .source_path = "a.zig", .source_line = 1, .declaration_start = 0, .declaration_end = 1 },
    };
    const hits = try search.search(a, &entries, "posx.read", 10);
    try std.testing.expectEqual(@as(usize, 0), hits[0].entry_index);
    try std.testing.expect(hits[0].match_kind == .fuzzy);
}

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
    try std.testing.expect(index.entries[search.exact(index.entries, "std.ErrorSet").?].kind == .error_set);
    try std.testing.expect(index.entries[search.exact(index.entries, "std.ErrorValue").?].kind == .@"const");
    try std.testing.expect(search.exact(index.entries, "std.Box.Mode") != null);
    try std.testing.expect(search.exact(index.entries, "std.child.answer") != null);
    const child = index.entries[search.exact(index.entries, "std.child").?];
    try std.testing.expectEqualStrings("//! Child container documentation.", child.docs);
    const hits = try search.search(a, index.entries, "open file", 10);
    try std.testing.expectEqualStrings("std.Box.openFile", index.entries[hits[0].entry_index].fq_name);
    const human = try render.human(a, read, "0.17.0", false);
    const expected = try std.fmt.allocPrint(a, "std.read\n────────\n\nFUNCTION\n\nSEMANTICS\n  Status      syntax_only\n\nSIGNATURE\n  pub fn read(buf: []u8) usize\n\nDESCRIPTION\n  Reads bytes, unchanged.\n\nSOURCE\n  {s}:3\n\nZIG VERSION\n  0.17.0\n", .{read.source_path});
    try std.testing.expectEqualStrings(expected, human);
}

test "human hierarchy plain goldens and ANSI boundaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const styles = @import("style.zig");
    const Entry = @import("index.zig").Entry;
    const alias: Entry = .{ .fq_name = "std.ArrayListUnmanaged", .short_name = "ArrayListUnmanaged", .kind = .function, .semantic_kind = .type_factory, .resolution = .resolved, .alias_of = "std.ArrayList", .returns_type = true, .signature = "pub fn ArrayList(comptime T: type) type", .docs = "/// Fixture paragraph with `T`.\n///\n/// Another unchanged paragraph.", .source_path = "/fixture/std.zig", .source_line = 52, .declaration_start = 0, .declaration_end = 1 };
    const plain = try render.human(a, alias, "0.17.0", false);
    try std.testing.expectEqualStrings(try @import("index.zig").read(a, std.testing.io, "tests/golden/alias.txt"), plain);
    const colored = try render.human(a, alias, "0.17.0", true);
    try std.testing.expectEqualStrings(plain, try stripAnsi(a, colored));
    for ([_]struct { styles.Role, []const u8 }{
        .{ .title, alias.fq_name }, .{ .kind, "TYPE FACTORY" }, .{ .section, "SEMANTICS" }, .{ .section, "SIGNATURE" }, .{ .metadata_key, "Status" }, .{ .symbol, "std.ArrayList" }, .{ .secondary, "/fixture/std.zig:52" }, .{ .keyword, "pub" },
    }) |boundary| {
        try std.testing.expect(std.mem.indexOf(u8, colored, try std.mem.concat(a, u8, &.{ styles.ansi(boundary[0]), boundary[1], styles.reset })) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, colored, "\n  Fixture paragraph with `T`.\n\n  Another unchanged paragraph.\n") != null);
    const write: Entry = .{ .fq_name = "std.os.linux.write", .short_name = "write", .kind = .function, .semantic_kind = .function, .resolution = .resolved, .signature = "pub fn write(fd: fd_t, buf: [*]const u8, count: usize) usize", .docs = "", .source_path = "/fixture/os/linux.zig", .source_line = 1787, .declaration_start = 0, .declaration_end = 1 };
    const manual = try render.humanWithManual(a, write, "0.17.0", false, true);
    try std.testing.expectEqualStrings(try @import("index.zig").read(a, std.testing.io, "tests/golden/manual.txt"), manual);
    try std.testing.expectEqualStrings(manual, try stripAnsi(a, try render.humanWithManual(a, write, "0.17.0", true, true)));
    const json = try render.json(a, alias, "0.17.0");
    try std.testing.expect(std.mem.indexOfScalar(u8, json, 27) == null);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, json, .{});
    try std.testing.expectEqualStrings(alias.signature, parsed.value.object.get("signature").?.string);
    try std.testing.expectEqualStrings(alias.docs, parsed.value.object.get("docs").?.string);
    try std.testing.expectEqualStrings("autodoc", parsed.value.object.get("semantic_backend").?.string);
}

fn stripAnsi(a: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < bytes.len) {
        if (bytes[i] == 27) {
            i = (std.mem.indexOfScalarPos(u8, bytes, i, 'm') orelse return error.InvalidAnsi) + 1;
        } else {
            try out.append(a, bytes[i]);
            i += 1;
        }
    }
    return out.items;
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

test "old cache format and damaged checksum rebuild signals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(io, ".", a);
    const filename = try std.fs.path.join(a, &.{ root, "index" });
    const cache = @import("cache.zig");
    try tmp.dir.writeFile(io, .{ .sub_path = "index", .data = "ZMAN\n1\n0\n{}" });
    try std.testing.expectError(error.CacheInvalidated, cache.load(a, io, filename, "id"));
    try tmp.dir.writeFile(io, .{ .sub_path = "index", .data = "ZMAN\n2\n0\n{}" });
    try std.testing.expectError(error.CacheCorruption, cache.load(a, io, filename, "id"));
}

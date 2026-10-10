const std = @import("std");
const environment = @import("environment.zig");
const parser = @import("parser.zig");
const semantic = @import("semantic.zig");
const search = @import("search.zig");
const model = @import("index.zig");
const render = @import("render.zig");
const man = @import("man.zig");
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    var env = try environment.detect(a, io);
    const root = try std.fs.path.resolve(a, &.{"tests/semantic"});
    var builder: parser.Builder = .{ .a = a, .io = io, .root = root };
    var index = try builder.build();
    env.std_dir = root;
    try semantic.resolve(a, io, env, init.environ_map.get("TMPDIR") orelse "/tmp", &index);
    const direct = find(index, "std.DirectType");
    try std.testing.expect(direct.is_type == true);
    const alias = find(index, "std.Alias");
    try std.testing.expectEqualStrings("std.DirectType", alias.alias_of.?);
    try std.testing.expectEqualStrings(direct.signature, alias.signature);
    try std.testing.expectEqualStrings(direct.docs, alias.docs);
    try std.testing.expectEqual(direct.declaration_start, alias.declaration_start);
    try std.testing.expect(alias.alias_source.?.byte_start != direct.declaration_start);
    try std.testing.expect(find(index, "std.Alias.method").semantic_kind == .function);
    for ([_][]const u8{ "std.Reexport", "std.ImportMember", "std.FooAlias" }) |name| {
        const reexport = find(index, name);
        try std.testing.expectEqualStrings("std.child.ChildType", reexport.canonical_name.?);
        try std.testing.expectEqualStrings("std.child.ChildType", reexport.reexport_of.?);
    }
    try std.testing.expect(find(index, "std.Generic").returns_type == true);
    try std.testing.expect(find(index, "std.Generic.member").semantic_kind == .function);
    try std.testing.expect(search.exact(index.entries, "std.Generic.phantom") == null);
    try std.testing.expect(find(index, "std.NumberType").is_type == true);
    try std.testing.expect(find(index, "std.number").semantic_kind == .constant);
    try std.testing.expect(find(index, "std.number").is_type == false);
    for ([_][]const u8{ "std.A", "std.B", "std.C", "std.CycleMember" }) |name| try std.testing.expect(find(index, name).resolution == .cyclic);
    for ([_][]const u8{ "std.Unknown", "std.Branch", "std.ValueFunction" }) |name| try std.testing.expect(find(index, name).resolution == .unresolved);
    try std.testing.expectEqualStrings("std.DirectType", find(index, "std.DirectType.Self").canonical_name.?);
    const source = try model.read(a, io, try std.fs.path.join(a, &.{ root, "std.zig" }));
    const self_start = std.mem.indexOf(u8, source, "    const Self = @This();").? + 4;
    const foo_start = std.mem.indexOf(u8, source, "const Foo = struct").?;
    var self_link = false;
    for (index.relationships) |link| if (link.source.byte_start == self_start and link.target.byte_start == foo_start) {
        self_link = true;
    };
    try std.testing.expect(self_link);
    const hits = try search.search(a, index.entries, "ChildType", 100);
    var grouped: usize = 0;
    for (hits) |hit| if (std.mem.eql(u8, index.entries[hit.entry_index].canonical_name orelse "", "std.child.ChildType")) {
        grouped += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), grouped);
    // Actual installed stdlib, without a fixture semantic oracle.
    env = try environment.detect(a, io);
    builder = .{ .a = a, .io = io, .root = env.std_dir };
    index = try builder.build();
    try semantic.resolve(a, io, env, init.environ_map.get("TMPDIR") orelse "/tmp", &index);
    const list = find(index, "std.ArrayList");
    try std.testing.expect(list.semantic_kind == .type_factory and list.returns_type == true);
    try std.testing.expectEqualStrings("std.ArrayList", find(index, "std.ArrayListUnmanaged").alias_of.?);
    try std.testing.expect(find(index, "std.mem.Allocator").is_type == true);
    try std.testing.expect(find(index, "std.os.linux.fd_t").is_type == true);
    try std.testing.expect(find(index, "std.math.pi").semantic_kind == .constant);
    const read = find(index, "std.posix.read");
    try std.testing.expectEqualStrings("pub fn read(fd: fd_t, buf: []u8) ReadError!usize", read.signature);
    const json = try render.json(a, read, env.version);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, json, .{});
    try std.testing.expectEqualStrings("read", parsed.value.object.get("system_manual").?.object.get("page").?.string);
    var private_self: usize = 0;
    for (index.relationships) |link| {
        if (!std.mem.endsWith(u8, link.source.path, "array_list.zig")) continue;
        const bytes = try model.read(a, io, link.source.path);
        const declaration = bytes[link.source.byte_start..link.source.byte_end];
        if (std.mem.indexOf(u8, declaration, "Self = @This()") != null) private_self += 1;
    }
    try std.testing.expect(private_self > 0);
    // Every mapped std.posix symbol must really exist in this installation.
    for (man.mappings) |mapping| if (std.mem.startsWith(u8, mapping.symbol, "std.posix.")) try std.testing.expect(search.exact(index.entries, mapping.symbol) != null);
    try std.Io.File.stdout().writeStreamingAll(io, "Semantic fixture and installed Zig integration passed.\n");
}
fn find(index: model.Index, name: []const u8) model.Entry {
    return index.entries[search.exact(index.entries, name) orelse @panic(name)];
}

const std = @import("std");
const model = @import("index.zig");
const protocol = @import("semantic/protocol.zig");
const Environment = @import("environment.zig").Environment;

pub const revision = blk: {
    @setEvalBranchQuota(100000);
    break :blk std.hash.Wyhash.hash(0, @embedFile("semantic.zig") ++ @embedFile("semantic/driver.zig") ++ @embedFile("semantic/protocol.zig") ++ @embedFile("semantic/guard.zig") ++ @embedFile("semantic/native_allocator.zig") ++ @embedFile("index.zig"));
};

pub fn resolve(a: std.mem.Allocator, io: std.Io, env: Environment, work_parent: []const u8, index: *model.Index) !void {
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    var random: [8]u8 = undefined;
    std.Io.random(io, &random);
    const work = try std.fmt.allocPrint(temporary, "{s}/semantic-{x}", .{ work_parent, std.mem.readInt(u64, &random, .little) });
    try std.Io.Dir.cwd().createDirPath(io, work);
    defer std.Io.Dir.cwd().deleteTree(io, work) catch {};
    const names = [_][]const u8{ "Walk.zig", "Decl.zig", "native_allocator.zig", "driver.zig", "index.zig", "protocol.zig" };
    var sources: [names.len][]const u8 = undefined;
    for (names[0..2], 0..) |name, i| {
        const official = try std.fs.path.join(temporary, &.{ env.lib_dir, "docs/wasm", name });
        const bytes = try model.read(temporary, io, official);
        sources[i] = try adapt(temporary, bytes, i == 0);
    }
    sources[2] = @embedFile("semantic/native_allocator.zig");
    sources[3] = @embedFile("semantic/driver.zig");
    sources[4] = @embedFile("index.zig");
    sources[5] = try replace(temporary, @embedFile("semantic/protocol.zig"), "../index.zig", "index.zig");
    var hash = std.hash.Wyhash.init(revision);
    hash.update(env.version);
    hash.update(env.zig_exe);
    for (sources) |source| hash.update(source);
    const backend = try std.fmt.allocPrint(temporary, "{s}/backend-{x}", .{ work_parent, hash.final() });
    const staging = try std.fs.path.join(temporary, &.{ work, "backend" });
    try std.Io.Dir.cwd().createDirPath(io, staging);
    for (names, sources) |name, source| try write(temporary, io, staging, name, source);
    std.Io.Dir.rename(.cwd(), staging, .cwd(), backend, io) catch {
        // An existing backend is reusable only when every input is identical.
        for (names, sources) |name, source| {
            const path = try std.fs.path.join(temporary, &.{ backend, name });
            const old = try model.read(temporary, io, path);
            if (!std.mem.eql(u8, old, source)) return error.SemanticBackendInvalid;
        }
    };
    const driver = try std.fs.path.join(temporary, &.{ backend, "driver.zig" });
    const output = try std.fs.path.join(temporary, &.{ work, "facts.json" });
    const zig_cache = try std.fs.path.join(temporary, &.{ work_parent, "zig-cache" });
    const result = try std.process.run(temporary, io, .{ .argv = &.{ env.zig_exe, "run", driver, "-OReleaseSafe", "--zig-lib-dir", env.lib_dir, "--cache-dir", zig_cache, "--global-cache-dir", zig_cache, "--", env.std_dir, output }, .stdout_limit = .limited(4096), .stderr_limit = .limited(1024 * 1024) });
    if (result.term != .exited or result.term.exited != 0) return error.SemanticBackendFailed;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, output, temporary, .limited(64 * 1024 * 1024));
    const parsed = try std.json.parseFromSlice(protocol.Output, temporary, bytes, .{ .allocate = .alloc_always });
    if (parsed.value.format != 1) return error.SemanticBackendUnsupported;
    try enrich(a, index, parsed.value);
    // Backend source changes invalidate the same way as stdlib changes.
    var files: std.ArrayList(model.File) = .empty;
    try files.appendSlice(a, index.files);
    for ([_][]const u8{ "Walk.zig", "Decl.zig" }) |name| {
        const path = try std.fs.path.join(a, &.{ env.lib_dir, "docs/wasm", name });
        const stat = try std.Io.Dir.cwd().statFile(io, path, .{});
        try files.append(a, .{ .path = path, .size = stat.size, .mtime = stat.mtime.nanoseconds });
    }
    index.files = files.items;
}
fn write(a: std.mem.Allocator, io: std.Io, work: []const u8, name: []const u8, bytes: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fs.path.join(a, &.{ work, name }), .data = bytes });
}
fn replace(a: std.mem.Allocator, bytes: []const u8, before: []const u8, after: []const u8) ![]const u8 {
    if (std.mem.count(u8, bytes, before) != 1) return error.SemanticBackendUnsupported;
    return std.mem.replaceOwned(u8, a, bytes, before, after);
}
pub fn adapt(a: std.mem.Allocator, source: []const u8, walk: bool) ![]const u8 {
    var bytes = try replace(a, source, "const gpa = std.heap.wasm_allocator;", "const gpa = @import(\"native_allocator.zig\").allocator;");
    if (walk) {
        const decl = "pub fn categorize_decl(file_index: File.Index, node: Ast.Node.Index) Category {";
        bytes = try replace(a, bytes, decl, decl ++ "\n if (!enter(file_index, node, 0)) return .{ .global_const = node }; defer leave();");
        const expr = "pub fn categorize_expr(file_index: File.Index, node: Ast.Node.Index) Category {";
        bytes = try replace(a, bytes, expr, expr ++ "\n if (!enter(file_index, node, 1)) return .{ .global_const = node }; defer leave();");
        bytes = try std.mem.concat(a, u8, &.{ bytes, "\n", @embedFile("semantic/guard.zig") });
    } else {
        // The shipped autodoc accessor predates the optional return operand in
        // this AST ABI. Preserve its algorithm with the matching accessor.
        bytes = try replace(a, bytes, "return ast.nodeData(stmt).node;", "return ast.nodeData(stmt).opt_node.unwrap();");
        const child = "pub fn get_child(decl: *const Decl, name: []const u8) ?Decl.Index {";
        bytes = try replace(a, bytes, child, child ++ "\n if (!Walk.enterChild(decl.file, decl.ast_node, name)) return null; defer Walk.leave();");
    }
    return bytes;
}

const Resolved = struct { target: u32, status: model.Resolution };
fn chase(facts: []const protocol.Fact, id: u32) Resolved {
    var seen: [512]u32 = undefined;
    var count: usize = 0;
    var current = id;
    while (true) {
        if (current >= facts.len) return .{ .target = id, .status = .unresolved };
        for (seen[0..count]) |visited| if (visited == current) return .{ .target = id, .status = .cyclic };
        if (facts[current].cyclic) return .{ .target = id, .status = .cyclic };
        if (count == seen.len) return .{ .target = id, .status = .unresolved };
        seen[count] = current;
        count += 1;
        const fact = facts[current];
        if (!fact.known) return .{ .target = current, .status = if (current == id) .unresolved else .partially_resolved };
        current = fact.target orelse return .{ .target = current, .status = .resolved };
    }
}
const Export = struct { name: []const u8, fact: u32, parent: ?[]const u8 };
const Graph = struct {
    a: std.mem.Allocator,
    facts: []const protocol.Fact,
    children: []std.ArrayList(u32),
    exports: std.ArrayList(Export) = .empty,
    active: [64]u32 = undefined,
    fn visit(self: *Graph, id: u32, name: []const u8, parent: ?[]const u8, depth: usize) anyerror!void {
        if (depth >= self.active.len or self.exports.items.len >= 100000) return error.SemanticGraphLimit;
        if (depth != 0) try self.exports.append(self.a, .{ .name = name, .fact = id, .parent = parent });
        const resolved = chase(self.facts, id);
        if (resolved.status != .resolved) return;
        const target = resolved.target;
        if (self.facts[target].category != .namespace and self.facts[target].category != .type and self.facts[target].category != .type_factory) return;
        for (self.active[0..depth]) |visited| if (visited == target) return;
        self.active[depth] = target;
        const members = self.children[target].items;
        for (members) |child| {
            const fact = self.facts[child];
            if (!fact.is_pub or !fact.exportable) continue;
            var ambiguous = false;
            for (members) |other| if (other != child and std.mem.eql(u8, self.facts[other].name, fact.name)) {
                ambiguous = true;
                break;
            };
            if (ambiguous) continue;
            const raw = fact.name;
            const short = if (std.mem.startsWith(u8, raw, "@\"")) try std.zig.string_literal.parseAlloc(self.a, raw[1..]) else raw;
            const path = try std.fmt.allocPrint(self.a, "{s}.{s}", .{ name, short });
            try self.visit(child, path, name, depth + 1);
        }
    }
};
// Only official backend facts enter here. No Zig expression is evaluated by zman.
pub fn enrich(a: std.mem.Allocator, index: *model.Index, output: protocol.Output) !void {
    const facts = output.facts;
    if (output.root_id >= facts.len) return error.SemanticBackendInvalid;
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();
    const temp = scratch.allocator();
    const children = try temp.alloc(std.ArrayList(u32), facts.len);
    @memset(children, .empty);
    for (facts, 0..) |fact, id| {
        if (fact.id != id or fact.end < fact.start or fact.line == 0 or (fact.target != null and fact.target.? >= facts.len)) return error.SemanticBackendInvalid;
        if (fact.parent) |parent| {
            if (parent >= facts.len) return error.SemanticBackendInvalid;
            try children[parent].append(temp, @intCast(id));
        }
    }
    var graph: Graph = .{ .a = temp, .facts = facts, .children = children };
    try graph.visit(output.root_id, "std", null, 0);
    var list: std.ArrayList(model.Entry) = .empty;
    try list.appendSlice(a, index.entries);
    var names: std.StringHashMapUnmanaged(u32) = .empty;
    for (list.items, 0..) |e, i| try names.put(temp, e.fq_name, @intCast(i));
    const entry_facts = try temp.alloc(?u32, 100000 + index.entries.len);
    @memset(entry_facts, null);
    const templates = try temp.alloc(?model.Entry, facts.len);
    @memset(templates, null);
    var paths: std.StringHashMapUnmanaged([]const u8) = .empty;
    var files: std.ArrayList(model.File) = .empty;
    for (output.files) |file| {
        const path = try a.dupe(u8, file.path);
        try paths.put(temp, file.path, path);
        try files.append(a, .{ .path = path, .size = file.size, .mtime = file.mtime });
    }
    for (graph.exports.items) |item| {
        const fact = facts[item.fact];
        const pos = names.get(item.name) orelse blk: {
            const name = try a.dupe(u8, item.name);
            var entry = try template(a, fact, templates, &paths);
            entry.fq_name = name;
            try list.append(a, entry);
            const i: u32 = @intCast(list.items.len - 1);
            try names.put(temp, name, i);
            break :blk i;
        };
        entry_facts[pos] = item.fact;
        list.items[pos].member_of = if (item.parent) |parent| try a.dupe(u8, parent) else null;
    }
    const canonical = try temp.alloc(?u32, facts.len);
    @memset(canonical, null);
    // Prefer a direct declaration over a re-export, then shortest public path and lexical order.
    for (list.items, 0..) |entry, i| {
        const id = entry_facts[i] orelse continue;
        const resolved = chase(facts, id);
        if (resolved.status == .cyclic) continue;
        const target = resolved.target;
        if (canonical[target]) |old| {
            const old_id = entry_facts[old].?;
            const direct = id == target;
            const old_direct = old_id == target;
            if (direct != old_direct) {
                if (direct) canonical[target] = @intCast(i);
            } else if (entry.fq_name.len < list.items[old].fq_name.len or (entry.fq_name.len == list.items[old].fq_name.len and std.mem.lessThan(u8, entry.fq_name, list.items[old].fq_name))) canonical[target] = @intCast(i);
        } else canonical[target] = @intCast(i);
    }
    const aliases = try temp.alloc(std.ArrayList([]const u8), list.items.len);
    @memset(aliases, .empty);
    var stats: model.SemanticStats = .{ .backend = .autodoc, .declarations = @intCast(facts.len) };
    for (list.items, 0..) |*entry, i| {
        const id = entry_facts[i] orelse {
            entry.resolution = .unresolved;
            stats.unresolved += 1;
            continue;
        };
        const resolved = chase(facts, id);
        entry.resolution = resolved.status;
        switch (resolved.status) {
            .resolved => stats.resolved += 1,
            .partially_resolved => stats.partially_resolved += 1,
            .cyclic => stats.cyclic += 1,
            else => stats.unresolved += 1,
        }
        if (resolved.status == .cyclic or resolved.status == .unresolved) continue;
        const target = facts[resolved.target];
        if (resolved.status == .resolved) {
            entry.semantic_kind = target.category;
            entry.is_type = target.category == .type or target.category == .namespace;
            entry.is_namespace = target.is_namespace or target.category == .namespace;
            if (target.category == .type_factory) entry.returns_type = true;
        }
        const canon = canonical[resolved.target] orelse continue;
        entry.canonical_name = list.items[canon].fq_name;
        if (canon != i) {
            entry.target_entry = canon;
            entry.alias_of = list.items[canon].fq_name;
            if (!std.mem.eql(u8, facts[id].file, target.file)) entry.reexport_of = entry.alias_of;
            try aliases[canon].append(temp, entry.fq_name);
            stats.public_aliases += 1;
        }
        if (facts[id].target != null and !target.root and resolved.target != id) {
            entry.alias_signature = entry.signature;
            entry.alias_docs = entry.docs;
            entry.alias_source = .{ .path = entry.source_path, .line = entry.source_line, .byte_start = entry.declaration_start, .byte_end = entry.declaration_end };
            const original = try template(a, target, templates, &paths);
            entry.signature = original.signature;
            entry.docs = original.docs;
            entry.source_path = original.source_path;
            entry.source_line = original.source_line;
            entry.declaration_start = original.declaration_start;
            entry.declaration_end = original.declaration_end;
            entry.kind = original.kind;
        }
    }
    for (aliases, 0..) |alias_list, i| if (alias_list.items.len != 0) {
        list.items[i].aliases = try a.dupe([]const u8, alias_list.items);
    };
    var relationships: std.ArrayList(model.Relationship) = .empty;
    for (facts) |fact| if (fact.target) |target_id| {
        stats.alias_edges += 1;
        const target = facts[target_id];
        try relationships.append(a, .{ .source = try location(a, fact, &paths), .target = try location(a, target, &paths), .relation = if (std.mem.eql(u8, fact.file, target.file)) .alias_of else .reexport_of });
    };
    index.* = .{ .entries = list.items, .files = files.items, .semantic = stats, .relationships = relationships.items };
}
fn location(a: std.mem.Allocator, fact: protocol.Fact, paths: *std.StringHashMapUnmanaged([]const u8)) !model.Source {
    return .{ .path = paths.get(fact.file) orelse try a.dupe(u8, fact.file), .line = fact.line, .byte_start = fact.start, .byte_end = fact.end };
}
fn template(a: std.mem.Allocator, fact: protocol.Fact, templates: []?model.Entry, paths: *std.StringHashMapUnmanaged([]const u8)) !model.Entry {
    if (templates[fact.id]) |entry| return entry;
    const raw = fact.name;
    const name = if (std.mem.startsWith(u8, raw, "@\"")) try std.zig.string_literal.parseAlloc(a, raw[1..]) else try a.dupe(u8, raw);
    const entry: model.Entry = .{ .fq_name = "", .short_name = name, .kind = fact.kind, .signature = try a.dupe(u8, fact.signature), .docs = try a.dupe(u8, fact.docs), .source_path = paths.get(fact.file) orelse try a.dupe(u8, fact.file), .source_line = fact.line, .declaration_start = fact.start, .declaration_end = fact.end };
    templates[fact.id] = entry;
    return entry;
}

test "official fact graph canonical aliases, cycles and unresolved" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var facts: [8]protocol.Fact = undefined;
    const names = [_][]const u8{ "", "Direct", "Alias", "Reexport", "A", "B", "Unknown", "number" };
    for (&facts, 0..) |*fact, i| fact.* = .{ .id = @intCast(i), .parent = if (i == 0) null else 0, .is_pub = true, .name = names[i], .file = "/fixture/std.zig", .start = @intCast(i * 10), .end = @intCast(i * 10 + 8), .line = @intCast(i + 1), .signature = "official source slice", .docs = "/// unchanged", .kind = .@"const", .category = .constant, .known = true, .cyclic = false };
    facts[0].root = true;
    facts[0].category = .namespace;
    facts[1].category = .type;
    facts[2].target = 1;
    facts[2].category = .unknown;
    facts[3].target = 1;
    facts[3].category = .unknown;
    facts[3].file = "/fixture/reexport.zig";
    facts[4].target = 5;
    facts[5].target = 4;
    facts[6].known = false;
    var index: model.Index = .{ .entries = &.{}, .files = &.{} };
    try enrich(a, &index, .{ .root_id = 0, .facts = &facts, .files = &.{} });
    const search = @import("search.zig");
    const alias = index.entries[search.exact(index.entries, "std.Alias").?];
    try std.testing.expectEqualStrings("std.Direct", alias.canonical_name.?);
    try std.testing.expectEqual(@as(u32, 10), alias.declaration_start);
    try std.testing.expectEqual(@as(u32, 20), alias.alias_source.?.byte_start);
    try std.testing.expect(alias.is_type == true);
    try std.testing.expect(index.entries[search.exact(index.entries, "std.A").?].resolution == .cyclic);
    try std.testing.expect(index.entries[search.exact(index.entries, "std.B").?].resolution == .cyclic);
    try std.testing.expect(index.entries[search.exact(index.entries, "std.Unknown").?].is_type == null);
    try std.testing.expect(index.entries[search.exact(index.entries, "std.number").?].semantic_kind == .constant);
    try std.testing.expectEqual(@as(u32, 2), index.semantic.cyclic);
}
test "unsupported autodoc source cannot be silently adapted" {
    try std.testing.expectError(error.SemanticBackendUnsupported, adapt(std.testing.allocator, "changed backend", true));
}

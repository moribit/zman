const std = @import("std");
const Walk = @import("Walk.zig");
const protocol = @import("protocol.zig");
const Ast = std.zig.Ast;
pub const std_options: std.Options = .{ .log_level = .err };
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(a);
    const root = args[1];
    var dir = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(a);
    defer walker.deinit();
    var paths: std.ArrayList([]const u8) = .empty;
    var directories: std.ArrayList([]const u8) = .empty;
    try directories.append(a, "");
    while (try walker.next(io)) |item| {
        if (item.kind == .directory) {
            try directories.append(a, try a.dupe(u8, item.path));
            continue;
        }
        if (item.kind != .file or !std.mem.endsWith(u8, item.basename, ".zig") or std.mem.endsWith(u8, item.basename, "test.zig")) continue;
        try paths.append(a, try a.dupe(u8, item.path));
    }
    std.mem.sort([]const u8, paths.items, {}, struct {
        fn less(_: void, x: []const u8, y: []const u8) bool {
            return std.mem.lessThan(u8, x, y);
        }
    }.less);
    var files: std.ArrayList(protocol.File) = .empty;
    for (directories.items) |relative| {
        const path = try std.fs.path.join(a, &.{ root, relative });
        const stat = try std.Io.Dir.cwd().statFile(io, path, .{});
        try files.append(a, .{ .path = path, .size = stat.size, .mtime = stat.mtime.nanoseconds });
    }
    for (paths.items) |relative| {
        const path = try std.fs.path.join(a, &.{ root, relative });
        const bytes = try dir.readFileAlloc(io, relative, a, .limited(32 * 1024 * 1024));
        const stat = try dir.statFile(io, relative, .{});
        try files.append(a, .{ .path = path, .size = stat.size, .mtime = stat.mtime.nanoseconds });
        // Walk consumes a final newline as its sentinel. The bytes before it stay unchanged.
        const source = if (bytes.len > 0 and bytes[bytes.len - 1] == '\n') bytes else try std.mem.concat(a, u8, &.{ bytes, "\n" });
        const key = try std.fmt.allocPrint(a, "std/{s}", .{relative});
        const index = try Walk.add_file(key, source);
        if (source.len > 1 and index.get_ast().source.len == 0) return error.SemanticParseFailure;
        if (std.mem.eql(u8, relative, "std.zig")) try Walk.modules.put(@import("native_allocator.zig").allocator, "std", index);
    }
    const root_id = Walk.modules.get("std").?.findRootDecl();
    var facts: std.ArrayList(protocol.Fact) = .empty;
    for (Walk.decls.items, 0..) |*decl, id| {
        Walk.resolution_failed = false;
        Walk.cycle_detected = false;
        const category = decl.categorize();
        const cyclic = Walk.cycle_detected;
        const failed = Walk.resolution_failed;
        const ast = decl.file.get_ast();
        const node = decl.ast_node;
        const root_node = ast.nodeTag(node) == .root;
        const info = decl.extra_info();
        var first = ast.firstToken(node);
        const last = ast.lastToken(node);
        var kind: protocol.Kind = .unknown;
        var signature_last = last;
        var fbuf: [1]Ast.Node.Index = undefined;
        var value = decl.value_node();
        if (ast.fullFnProto(&fbuf, node)) |full| {
            first = full.firstToken();
            kind = .function;
            signature_last = ast.lastToken(full.ast.proto_node);
        } else if (ast.fullVarDecl(node)) |full| {
            first = full.firstToken();
            kind = if (ast.tokenTag(full.ast.mut_token) == .keyword_var) .@"var" else .@"const";
            value = full.ast.init_node.unwrap();
        }
        if (value) |v| {
            var cbuf: [2]Ast.Node.Index = undefined;
            if (ast.fullContainerDecl(&cbuf, v)) |container| {
                kind = switch (ast.tokenTag(container.ast.main_token)) {
                    .keyword_struct => .@"struct",
                    .keyword_enum => .@"enum",
                    .keyword_union => .@"union",
                    .keyword_opaque => .@"opaque",
                    else => .unknown,
                };
                signature_last = container.ast.main_token;
            } else if (ast.nodeTag(v) == .error_set_decl or ast.nodeTag(v) == .merge_error_sets) kind = .error_set;
        }
        const start: u32 = if (root_node) 0 else ast.tokenStart(first);
        const end: u32 = if (root_node) @intCast(ast.source.len) else @intCast(ast.tokenStart(last) + ast.tokenSlice(last).len);
        const signature_end = if (root_node) 0 else ast.tokenStart(signature_last) + ast.tokenSlice(signature_last).len;
        var docs: []const u8 = "";
        var doc_first = first;
        if (!root_node) {
            while (doc_first > 0 and ast.tokenTag(doc_first - 1) == .doc_comment) doc_first -= 1;
            if (doc_first != first) docs = ast.source[ast.tokenStart(doc_first) .. ast.tokenStart(first - 1) + ast.tokenSlice(first - 1).len];
        } else {
            var t: Ast.TokenIndex = 0;
            while (ast.tokenTag(t) == .container_doc_comment) : (t += 1) {}
            if (t > 0) docs = ast.source[0 .. ast.tokenStart(t - 1) + ast.tokenSlice(t - 1).len];
        }
        const target: ?u32 = if (category == .alias) @intCast(@backingInt(category.alias)) else null;
        const semantic_kind: protocol.SemanticKind = switch (category) {
            .alias => .unknown,
            .namespace => if (root_node) .namespace else .type,
            .container, .type, .type_type, .error_set => .type,
            .type_function => .type_factory,
            .function => .function,
            .global_variable => .variable,
            .global_const, .primitive => .constant,
        };
        // Autodoc's fallback global_const and branch heuristics are not compiler proofs.
        const known = !failed and conservative(ast, value, category);
        const key = decl.file.path();
        const path = try std.fs.path.join(a, &.{ root, key[4..] });
        try facts.append(a, .{ .id = @intCast(id), .parent = if (decl.parent == .none) null else @intCast(@backingInt(decl.parent)), .is_pub = info.is_pub, .exportable = safeMember(decl), .name = info.name, .file = path, .start = start, .end = end, .line = @intCast(1 + std.mem.count(u8, ast.source[0..start], "\n")), .signature = if (root_node) "" else ast.source[start..signature_end], .docs = docs, .kind = kind, .category = semantic_kind, .target = target, .cyclic = cyclic, .known = known, .root = root_node, .is_namespace = category == .namespace });
    }
    const output = try std.json.Stringify.valueAlloc(a, protocol.Output{ .root_id = @intCast(@backingInt(root_id)), .facts = facts.items, .files = files.items }, .{ .emit_null_optional_fields = false });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = args[2], .data = output });
}
fn conservative(ast: *Ast, value: ?Ast.Node.Index, category: Walk.Category) bool {
    const node = value orelse return category == .global_variable;
    const tag = ast.nodeTag(node);
    if (tag == .@"if" or tag == .if_simple or tag == .@"switch" or tag == .switch_comma) return false;
    if (category == .type_function) {
        var buf: [1]Ast.Node.Index = undefined;
        const full = ast.fullFnProto(&buf, node) orelse return false;
        const result = full.ast.return_type.unwrap() orelse return false;
        return ast.nodeTag(result) == .identifier and std.mem.eql(u8, ast.tokenSlice(ast.nodeMainToken(result)), "type");
    }
    if (category == .alias) {
        if (ast.nodeTag(node) == .builtin_call_two or ast.nodeTag(node) == .builtin_call) {
            const builtin = ast.tokenSlice(ast.nodeMainToken(node));
            if (std.mem.eql(u8, builtin, "@This") and category.alias.get().file.get_ast().nodeTag(category.alias.get().ast_node) == .fn_decl) return false;
        }
        return true;
    }
    if (category == .global_const) return switch (tag) {
        .number_literal, .string_literal, .multiline_string_literal, .char_literal, .enum_literal => true,
        .identifier => Walk.isPrimitiveNonType(ast.tokenSlice(ast.nodeMainToken(node))),
        else => false,
    };
    return true;
}

// Autodoc groups nested anonymous containers under a function. Expose only
// members whose declaration is in its literal returned container.
fn safeMember(decl: *const Walk.Decl) bool {
    const parent = if (decl.parent != .none) decl.parent.get() else return true;
    const ast = parent.file.get_ast();
    if (ast.nodeTag(parent.ast_node) != .fn_decl) return true;
    const returned = parent.get_type_fn_return_expr() orelse return false;
    var buf: [2]Ast.Node.Index = undefined;
    const container = ast.fullContainerDecl(&buf, returned) orelse return false;
    for (container.ast.members) |node| if (node == decl.ast_node) return true;
    return false;
}

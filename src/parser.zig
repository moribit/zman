const std = @import("std");
const model = @import("index.zig");
const Ast = std.zig.Ast;
pub const Builder = struct {
    a: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    entries: std.ArrayList(model.Entry) = .empty,
    files: std.ArrayList(model.File) = .empty,
    active: std.StringHashMapUnmanaged(void) = .empty,
    visited: std.StringHashMapUnmanaged(void) = .empty,
    pub fn build(self: *Builder) !model.Index {
        const root_path = try std.fs.path.join(self.a, &.{ self.root, "std.zig" });
        _ = std.Io.Dir.cwd().statFile(self.io, root_path, .{}) catch return error.StdlibNotFound;
        try self.file(root_path, "std", 0);
        return .{ .entries = self.entries.items, .files = self.files.items };
    }
    fn file(self: *Builder, path: []const u8, prefix: []const u8, depth: usize) anyerror!void {
        if (depth > 40 or self.active.contains(path)) return;
        const key = try std.fmt.allocPrint(self.a, "{s}:{s}", .{ path, prefix });
        if (self.visited.contains(key)) return;
        try self.visited.put(self.a, key, {});
        const source = model.read(self.a, self.io, path) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer self.a.free(source);
        const stat = try std.Io.Dir.cwd().statFile(self.io, path, .{});
        var known = false;
        for (self.files.items) |f| {
            if (std.mem.eql(u8, f.path, path)) {
                known = true;
                break;
            }
        }
        if (!known) try self.files.append(self.a, .{ .path = path, .size = stat.size, .mtime = stat.mtime.nanoseconds });
        var tree = try Ast.parse(self.a, source, .{ .mode = .zig });
        defer tree.deinit(self.a);
        if (tree.errors.len != 0) return error.ParseFailure;
        try self.active.put(self.a, path, {});
        defer _ = self.active.remove(path);
        try self.members(tree, tree.rootDecls(), path, prefix, depth);
    }
    fn members(self: *Builder, tree: Ast, nodes: []const Ast.Node.Index, path: []const u8, prefix: []const u8, depth: usize) anyerror!void {
        for (nodes) |node| {
            var fn_buf: [1]Ast.Node.Index = undefined;
            var name_token: Ast.TokenIndex = undefined;
            var first: Ast.TokenIndex = undefined;
            var kind: model.Kind = .unknown;
            var init: ?Ast.Node.Index = null;
            var signature_end = tree.lastToken(node);
            if (tree.fullFnProto(&fn_buf, node)) |fun| {
                if (fun.visib_token == null or fun.name_token == null) continue;
                first = fun.firstToken();
                name_token = fun.name_token.?;
                kind = .function;
                signature_end = tree.lastToken(fun.ast.proto_node);
            } else if (tree.fullVarDecl(node)) |v| {
                if (v.visib_token == null) continue;
                first = v.firstToken();
                name_token = v.ast.mut_token + 1;
                kind = if (tree.tokens.items(.tag)[v.ast.mut_token] == .keyword_var) .@"var" else .@"const";
                init = v.ast.init_node.unwrap();
            } else continue;
            if (tree.tokens.items(.tag)[first] != .keyword_pub) continue;
            const name_raw = tree.tokenSlice(name_token);
            const name = if (std.mem.startsWith(u8, name_raw, "@\"")) try std.zig.string_literal.parseAlloc(self.a, name_raw[1..]) else name_raw;
            const fq = try std.fmt.allocPrint(self.a, "{s}.{s}", .{ prefix, name });
            const starts = tree.tokens.items(.start);
            const start = starts[first];
            const end = starts[tree.lastToken(node)] + tree.tokenSlice(tree.lastToken(node)).len;
            var container_buf: [2]Ast.Node.Index = undefined;
            const container = if (init) |n| tree.fullContainerDecl(&container_buf, n) else null;
            var import_path: ?[]const u8 = null;
            if (init) |n| {
                const tok = tree.firstToken(n);
                const tags = tree.tokens.items(.tag);
                if (tags[tok] == .builtin and std.mem.eql(u8, tree.tokenSlice(tok), "@import") and tags[tok + 1] == .l_paren and tags[tok + 2] == .string_literal and tags[tok + 3] == .r_paren and tree.lastToken(n) == tok + 3) {
                    const relative = try std.zig.string_literal.parseAlloc(self.a, tree.tokenSlice(tok + 2));
                    if (std.mem.endsWith(u8, relative, ".zig")) {
                        const resolved = try std.fs.path.resolve(self.a, &.{ std.fs.path.dirname(path).?, relative });
                        if (std.mem.startsWith(u8, resolved, self.root) and resolved.len > self.root.len and resolved[self.root.len] == std.fs.path.sep) import_path = resolved;
                    }
                }
                if (tree.tokens.items(.tag)[tok] == .keyword_error) kind = .error_set;
            }
            if (container) |c| {
                kind = switch (tree.tokens.items(.tag)[c.ast.main_token]) {
                    .keyword_struct => .@"struct",
                    .keyword_enum => .@"enum",
                    .keyword_union => .@"union",
                    .keyword_opaque => .@"opaque",
                    else => .unknown,
                };
                signature_end = c.ast.main_token;
            }
            if (import_path != null) kind = .namespace;
            var doc_first = first;
            while (doc_first > 0 and tree.tokens.items(.tag)[doc_first - 1] == .doc_comment) doc_first -= 1;
            var docs: []const u8 = "";
            if (doc_first != first) docs = tree.source[starts[doc_first] .. starts[first - 1] + tree.tokenSlice(first - 1).len];
            if (import_path) |p| {
                if (docs.len == 0) {
                    const imported = try model.read(self.a, self.io, p);
                    defer self.a.free(imported);
                    var tokenizer = std.zig.Tokenizer.init(imported);
                    var doc_end: usize = 0;
                    while (true) {
                        const t = tokenizer.next();
                        if (t.tag != .container_doc_comment) break;
                        doc_end = t.loc.end;
                    }
                    if (doc_end != 0) docs = try self.a.dupe(u8, imported[0..doc_end]);
                }
            }
            try self.entries.append(self.a, .{ .fq_name = fq, .short_name = try self.a.dupe(u8, name), .kind = kind, .signature = try self.a.dupe(u8, tree.source[start .. starts[signature_end] + tree.tokenSlice(signature_end).len]), .docs = try self.a.dupe(u8, docs), .source_path = path, .source_line = @intCast(1 + std.mem.count(u8, tree.source[0..start], "\n")), .declaration_start = @intCast(start), .declaration_end = @intCast(end) });
            if (container) |c| try self.members(tree, c.ast.members, path, fq, depth + 1);
            if (import_path) |p| try self.file(p, fq, depth + 1);
        }
    }
};

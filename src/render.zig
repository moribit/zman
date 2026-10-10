const std = @import("std");
const model = @import("index.zig");
const highlight = @import("highlight.zig");
const man = @import("man.zig");
pub fn cleanDocs(a: std.mem.Allocator, docs: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, docs, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimStart(u8, raw, " \t");
        const content = if (std.mem.startsWith(u8, line, "///") or std.mem.startsWith(u8, line, "//!")) line[3..] else line;
        try out.appendSlice(a, if (std.mem.startsWith(u8, content, " ")) content[1..] else content);
        try out.append(a, '\n');
    }
    return out.items;
}
pub fn human(a: std.mem.Allocator, e: model.Entry, version: []const u8, color: bool) ![]const u8 {
    const signature = try highlight.render(a, e.signature, color);
    const docs = try cleanDocs(a, e.docs);
    var info: std.ArrayList(u8) = .empty;
    if (e.resolution != .syntax_only) {
        try info.appendSlice(a, try std.fmt.allocPrint(a, "RESOLUTION\n\n{s} (Zig autodoc)\n", .{@tagName(e.resolution)}));
        if (e.alias_of) |alias| try info.appendSlice(a, try std.fmt.allocPrint(a, "\nAlias of:\n    {s}\n", .{alias}));
        if (e.returns_type == true) try info.appendSlice(a, "\nReturns: type\n");
        try info.appendSlice(a, "\n");
    }
    return std.fmt.allocPrint(a, "{s}\n\n{s}\n\n{s}SIGNATURE\n\n{s}\n\nDESCRIPTION\n\n{s}\nSOURCE\n\n{s}:{d}\n\nZIG VERSION\n\n{s}\n", .{ e.fq_name, displayKind(e), info.items, signature, docs, e.source_path, e.source_line, version });
}
pub fn json(a: std.mem.Allocator, e: model.Entry, version: []const u8) ![]const u8 {
    return std.json.Stringify.valueAlloc(a, .{ .zig_version = version, .name = e.fq_name, .kind = @tagName(e.kind), .visibility = e.visibility, .signature = e.signature, .docs = e.docs, .semantic_backend = if (e.resolution == .syntax_only) "syntax_only" else "autodoc", .semantic_kind = @tagName(e.semantic_kind), .resolution = @tagName(e.resolution), .canonical_name = e.canonical_name, .aliases = e.aliases, .alias_of = e.alias_of, .reexport_of = e.reexport_of, .target_entry = e.target_entry, .member_of = e.member_of, .returns_type = e.returns_type, .is_type = e.is_type, .is_namespace = e.is_namespace, .alias_signature = e.alias_signature, .alias_docs = e.alias_docs, .alias_source = e.alias_source, .system_manual = man.reference(e.fq_name), .source = .{ .path = e.source_path, .line = e.source_line, .byte_start = e.declaration_start, .byte_end = e.declaration_end } }, .{ .whitespace = .indent_2 });
}
pub fn results(a: std.mem.Allocator, entries: []const model.Entry, matches: []const @import("search.zig").Result, query: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, try std.fmt.allocPrint(a, "Search results for: {s}\n\n", .{query}));
    if (matches.len > 0 and matches[0].match_kind == .fuzzy) try out.appendSlice(a, "Did you mean:\n\n");
    for (matches, 0..) |match, i| {
        const e = entries[match.entry_index];
        const docs = try cleanDocs(a, e.docs);
        var lines = std.mem.tokenizeScalar(u8, docs, '\n');
        const preview = lines.next() orelse "";
        try out.appendSlice(a, try std.fmt.allocPrint(a, "{d}. {s}\n   {s}\n   {s}\n", .{ i + 1, e.fq_name, displayKind(e), preview }));
        if (e.aliases.len > 0) {
            try out.appendSlice(a, "   aliases:");
            for (e.aliases[0..@min(3, e.aliases.len)]) |alias| try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{alias}));
            if (e.aliases.len > 3) try out.appendSlice(a, " …");
            try out.append(a, '\n');
        }
        try out.append(a, '\n');
    }
    return out.items;
}
pub fn source(a: std.mem.Allocator, io: std.Io, e: model.Entry, color: bool) ![]const u8 {
    const bytes = try model.read(a, io, e.source_path);
    if (e.declaration_end > bytes.len) return error.SourceChanged;
    const first_line = e.source_line -| 3;
    const end_line = e.source_line + @as(u32, @intCast(std.mem.count(u8, bytes[e.declaration_start..e.declaration_end], "\n"))) + 3;
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, try std.fmt.allocPrint(a, "{s}:{d}\n\n", .{ e.source_path, e.source_line }));
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var line_no: u32 = 0;
    while (lines.next()) |line| {
        line_no += 1;
        if (line_no < first_line) continue;
        if (line_no > end_line) break;
        try out.appendSlice(a, try std.fmt.allocPrint(a, "{d: >5} {s}\n", .{ line_no, try highlight.render(a, line, color) }));
    }
    return out.items;
}

pub fn displayKind(e: model.Entry) []const u8 {
    if (e.resolution != .resolved) return @tagName(e.kind);
    return switch (e.semantic_kind) {
        .type_factory => "TYPE FACTORY",
        .type => "TYPE",
        .namespace => "NAMESPACE",
        .function => "FUNCTION",
        .constant => "CONST",
        .variable => "VAR",
        .unknown => @tagName(e.kind),
    };
}

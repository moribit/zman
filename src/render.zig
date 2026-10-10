const std = @import("std");
const model = @import("index.zig");
const highlight = @import("highlight.zig");
const man = @import("man.zig");
const styles = @import("style.zig");

const HumanRenderer = struct {
    a: std.mem.Allocator,
    color: bool,
    out: std.ArrayList(u8) = .empty,

    fn text(self: *HumanRenderer, bytes: []const u8) !void {
        try self.out.appendSlice(self.a, bytes);
    }
    fn styled(self: *HumanRenderer, role: styles.Role, bytes: []const u8) !void {
        if (self.color) try self.text(styles.ansi(role));
        try self.text(bytes);
        if (self.color) try self.text(styles.reset);
    }
    fn title(self: *HumanRenderer, name: []const u8) !void {
        try self.styled(.title, name);
        try self.text("\n");
        if (self.color) try self.text(styles.ansi(.secondary));
        for (0..name.len) |_| try self.text("─");
        if (self.color) try self.text(styles.reset);
        try self.text("\n");
    }
    fn section(self: *HumanRenderer, heading: []const u8) !void {
        try self.text("\n");
        try self.styled(.section, heading);
        try self.text("\n");
    }
    fn metadata(self: *HumanRenderer, key: []const u8, value: []const u8, role: ?styles.Role) !void {
        try self.text("  ");
        try self.styled(.metadata_key, key);
        for (0..12 -| key.len) |_| try self.text(" ");
        if (role) |r| try self.styled(r, value) else try self.text(value);
        try self.text("\n");
    }
    fn body(self: *HumanRenderer, bytes: []const u8, role: ?styles.Role) !void {
        var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, bytes, "\n"), '\n');
        while (lines.next()) |line| {
            if (line.len > 0) {
                try self.text("  ");
                if (role) |r| try self.styled(r, line) else try self.text(line);
            }
            try self.text("\n");
        }
    }
    fn manual(self: *HumanRenderer, reference: ?man.Reference) !void {
        try self.section("SYSTEM MANUAL");
        if (reference) |ref| {
            try self.metadata("Host page", try std.fmt.allocPrint(self.a, "{s}({d})", .{ ref.page, ref.section }), .symbol);
            try self.metadata("Relation", @tagName(ref.relation), null);
        } else try self.body("No explicit system manual mapping for this symbol.", null);
    }
};
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
    return humanWithManual(a, e, version, color, false);
}
pub fn humanWithManual(a: std.mem.Allocator, e: model.Entry, version: []const u8, color: bool, include_manual: bool) ![]const u8 {
    var ui: HumanRenderer = .{ .a = a, .color = color };
    try ui.title(e.fq_name);
    try ui.text("\n");
    try ui.styled(.kind, displayKind(e));
    try ui.text("\n");
    try ui.section("SEMANTICS");
    try ui.metadata("Status", @tagName(e.resolution), null);
    if (e.alias_of) |alias| try ui.metadata("Alias of", alias, .symbol);
    if (e.returns_type == true) try ui.metadata("Returns", try highlight.render(a, "type", color), null);
    try ui.section("SIGNATURE");
    try ui.body(try highlight.render(a, e.signature, color), null);
    try ui.section("DESCRIPTION");
    try ui.body(if (e.docs.len == 0) "No Zig documentation attached." else try cleanDocs(a, e.docs), null);
    if (include_manual) try ui.manual(man.reference(e.fq_name));
    try ui.section("SOURCE");
    try ui.body(try std.fmt.allocPrint(a, "{s}:{d}", .{ e.source_path, e.source_line }), .secondary);
    try ui.section("ZIG VERSION");
    try ui.body(version, .secondary);
    return ui.out.items;
}
pub fn manual(a: std.mem.Allocator, reference: ?man.Reference, color: bool) ![]const u8 {
    var ui: HumanRenderer = .{ .a = a, .color = color };
    try ui.manual(reference);
    return ui.out.items;
}
pub fn manualLink(a: std.mem.Allocator, name: []const u8, reference: ?man.Reference, color: bool) ![]const u8 {
    var ui: HumanRenderer = .{ .a = a, .color = color };
    try ui.title(name);
    try ui.manual(reference);
    return ui.out.items;
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
    var ui: HumanRenderer = .{ .a = a, .color = color };
    try ui.styled(.secondary, try std.fmt.allocPrint(a, "{s}:{d}", .{ e.source_path, e.source_line }));
    try ui.text("\n\n");
    try out.appendSlice(a, ui.out.items);
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
    if (e.resolution != .resolved) return switch (e.kind) {
        .function => "FUNCTION",
        .@"const" => "CONST",
        .@"var" => "VAR",
        .@"struct" => "STRUCT",
        .@"enum" => "ENUM",
        .@"union" => "UNION",
        .@"opaque" => "OPAQUE",
        .error_set => "ERROR SET",
        .namespace => "NAMESPACE",
        .type => "TYPE",
        .unknown => "UNKNOWN",
    };
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

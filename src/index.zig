const std = @import("std");
pub const Kind = enum { function, @"const", @"var", @"struct", @"enum", @"union", @"opaque", error_set, namespace, type, unknown };
pub const SemanticKind = enum { unknown, function, type_factory, type, namespace, constant, variable };
pub const Resolution = enum { syntax_only, resolved, partially_resolved, unresolved, cyclic };
pub const Source = struct { path: []const u8, line: u32, byte_start: u32, byte_end: u32 };
pub const Relationship = struct { source: Source, target: Source, relation: enum { alias_of, reexport_of } };
pub const SemanticStats = struct {
    backend: enum { syntax_only, autodoc } = .syntax_only,
    declarations: u32 = 0,
    alias_edges: u32 = 0,
    public_aliases: u32 = 0,
    resolved: u32 = 0,
    partially_resolved: u32 = 0,
    unresolved: u32 = 0,
    cyclic: u32 = 0,
};
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
    semantic_kind: SemanticKind = .unknown,
    resolution: Resolution = .syntax_only,
    canonical_name: ?[]const u8 = null,
    aliases: []const []const u8 = &.{},
    alias_of: ?[]const u8 = null,
    reexport_of: ?[]const u8 = null,
    target_entry: ?u32 = null,
    member_of: ?[]const u8 = null,
    returns_type: ?bool = null,
    is_type: ?bool = null,
    is_namespace: ?bool = null,
    alias_signature: ?[]const u8 = null,
    alias_docs: ?[]const u8 = null,
    alias_source: ?Source = null,
};
pub const File = struct { path: []const u8, size: u64, mtime: i96 };
pub const Index = struct { entries: []const Entry, files: []const File, semantic: SemanticStats = .{}, relationships: []const Relationship = &.{} };
pub fn read(a: std.mem.Allocator, io: std.Io, path: []const u8) ![:0]u8 {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(64 * 1024 * 1024));
    defer a.free(bytes);
    return a.dupeSentinel(u8, bytes, 0);
}

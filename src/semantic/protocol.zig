const model = @import("../index.zig");
pub const File = model.File;
pub const Kind = model.Kind;
pub const SemanticKind = model.SemanticKind;
pub const Fact = struct {
    id: u32,
    parent: ?u32 = null,
    is_pub: bool,
    exportable: bool = true,
    name: []const u8,
    file: []const u8,
    start: u32,
    end: u32,
    line: u32,
    signature: []const u8,
    docs: []const u8,
    kind: model.Kind,
    category: model.SemanticKind,
    known: bool,
    cyclic: bool,
    target: ?u32 = null,
    is_namespace: bool = false,
    root: bool = false,
};
pub const Output = struct { format: u32 = 1, root_id: u32, facts: []const Fact, files: []const model.File };

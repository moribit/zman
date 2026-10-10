const std = @import("std");
const styles = @import("style.zig");
pub fn render(a: std.mem.Allocator, source: []const u8, color: bool) ![]const u8 {
    if (!color) return a.dupe(u8, source);
    const terminated = try a.dupeSentinel(u8, source, 0);
    defer a.free(terminated);
    var tokens = std.zig.Tokenizer.init(terminated);
    var out: std.ArrayList(u8) = .empty;
    var last: usize = 0;
    while (true) {
        const token = tokens.next();
        if (token.tag == .eof) break;
        try gap(a, &out, source[last..token.loc.start]);
        const tag = @tagName(token.tag);
        const role: styles.Role = if (std.mem.startsWith(u8, tag, "keyword_")) .keyword else switch (token.tag) {
            .builtin => .builtin,
            .string_literal, .multiline_string_literal_line, .char_literal => .literal,
            .number_literal => .number,
            .doc_comment, .container_doc_comment => .comment,
            .identifier => if (std.zig.primitives.isPrimitive(source[token.loc.start..token.loc.end])) .builtin else .identifier,
            else => .punctuation,
        };
        // Tokenizer skips ordinary comments. Color those gaps independently of prose.
        try out.appendSlice(a, styles.ansi(role));
        try out.appendSlice(a, source[token.loc.start..token.loc.end]);
        try out.appendSlice(a, styles.reset);
        last = token.loc.end;
    }
    try gap(a, &out, source[last..]);
    return out.toOwnedSlice(a);
}
test "plain preserves bytes and ANSI includes builtin" {
    const a = std.testing.allocator;
    const s = "pub fn read(fd: i32, buf: []u8) usize { if (buf.len == 0) return 0; const value: usize = @intCast(fd); // comment\n return value; }";
    const plain = try render(a, s, false);
    defer a.free(plain);
    try std.testing.expectEqualStrings(s, plain);
    const colored = try render(a, s, true);
    defer a.free(colored);
    try std.testing.expect(std.mem.indexOf(u8, colored, "\x1b[36m@intCast") != null);
    for ([_][]const u8{ "\x1b[35mpub", "\x1b[39mread", "\x1b[36musize", "\x1b[33m0", "\x1b[90m// comment", "\x1b[34m(" }) |token| try std.testing.expect(std.mem.indexOf(u8, colored, token) != null);
}

fn gap(a: std.mem.Allocator, out: *std.ArrayList(u8), bytes: []const u8) !void {
    var start: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, start, "//")) |comment| {
        const end = if (std.mem.indexOfScalarPos(u8, bytes, comment, '\n')) |n| n else bytes.len;
        try out.appendSlice(a, bytes[start..comment]);
        try out.appendSlice(a, styles.ansi(.comment));
        try out.appendSlice(a, bytes[comment..end]);
        try out.appendSlice(a, styles.reset);
        start = end;
    }
    try out.appendSlice(a, bytes[start..]);
}

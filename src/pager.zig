const std = @import("std");
const Mode = @import("cli.zig").Mode;
// A small argv lexer; shell expansion and execution are deliberately absent.
pub fn argv(a: std.mem.Allocator, text: []const u8) ![][]const u8 {
    var args: std.ArrayList([]const u8) = .empty;
    var word: std.ArrayList(u8) = .empty;
    var quote: ?u8 = null;
    var escaped = false;
    var started = false;
    for (text) |c| {
        if (escaped) {
            try word.append(a, c);
            escaped = false;
            started = true;
            continue;
        }
        if (c == '\\' and quote != '\'') {
            escaped = true;
            continue;
        }
        if (quote) |q| {
            if (c == q) quote = null else try word.append(a, c);
            started = true;
        } else if (c == '\'' or c == '"') {
            quote = c;
            started = true;
        } else if (std.ascii.isWhitespace(c)) {
            if (started) {
                try args.append(a, try a.dupe(u8, word.items));
                word.clearRetainingCapacity();
                started = false;
            }
        } else {
            try word.append(a, c);
            started = true;
        }
    }
    if (quote != null or escaped) return error.InvalidCommand;
    if (started) try args.append(a, try a.dupe(u8, word.items));
    if (args.items.len == 0) return error.InvalidCommand;
    return args.items;
}
pub fn output(a: std.mem.Allocator, io: std.Io, map: *std.process.Environ.Map, text: []const u8, mode: Mode, tty: bool) !void {
    if (mode != .never and tty and (mode == .always or std.mem.count(u8, text, "\n") > 40)) {
        const command = map.get("ZMAN_PAGER") orelse map.get("PAGER") orelse "less -R";
        const args = argv(a, command) catch return std.Io.File.stdout().writeStreamingAll(io, text);
        var child = std.process.spawn(io, .{ .argv = args, .stdin = .pipe }) catch return std.Io.File.stdout().writeStreamingAll(io, text);
        defer child.kill(io);
        child.stdin.?.writeStreamingAll(io, text) catch {};
        child.stdin.?.close(io);
        child.stdin = null;
        const term = try child.wait(io);
        if (term != .exited or term.exited != 0) return error.PagerFailure;
        return;
    }
    try std.Io.File.stdout().writeStreamingAll(io, text);
}
pub fn edit(a: std.mem.Allocator, io: std.Io, map: *std.process.Environ.Map, path: []const u8, line: u32) !void {
    const command = map.get("ZMAN_EDITOR") orelse map.get("VISUAL") orelse map.get("EDITOR") orelse return error.EditorNotConfigured;
    const base = try argv(a, command);
    var args: std.ArrayList([]const u8) = .empty;
    try args.appendSlice(a, base);
    const name = std.fs.path.basename(base[0]);
    if (std.mem.eql(u8, name, "vim") or std.mem.eql(u8, name, "nvim") or std.mem.eql(u8, name, "vi")) {
        try args.append(a, try std.fmt.allocPrint(a, "+{d}", .{line}));
        try args.append(a, path);
    } else if (std.mem.eql(u8, name, "code")) {
        try args.append(a, "--goto");
        try args.append(a, try std.fmt.allocPrint(a, "{s}:{d}", .{ path, line }));
    } else try args.append(a, path);
    var child = std.process.spawn(io, .{ .argv = args.items }) catch return error.EditorFailure;
    defer child.kill(io);
    const term = try child.wait(io);
    if (term != .exited or term.exited != 0) return error.EditorFailure;
}
test "quoted command argv" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const args = try argv(arena.allocator(), "editor --flag 'a b'");
    try std.testing.expectEqualStrings("a b", args[2]);
}

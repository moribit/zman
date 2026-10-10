const std = @import("std");
pub const Mode = enum { auto, always, never };
pub const Options = struct { command: enum { lookup, search, source, edit, man, reindex, help, version } = .lookup, query: []const u8 = "", limit: usize = 10, color: Mode = .auto, pager: Mode = .auto, json: bool = false, source: bool = false, man: bool = false };
pub const help = "Usage:\n  zman <symbol-or-query>\n  zman search <query> [--limit 20]\n  zman source <symbol>\n  zman edit <symbol>\n  zman man <symbol>\n  zman reindex\n\nOptions:\n  --json  --source  --man  --color=auto|always|never\n  --pager=auto|always|never  --no-color  --help  --version\n\nExamples:\n  zman std.posix.read\n  zman posix.read\n  zman read\n  zman \"open file\"\n";
pub fn parse(a: std.mem.Allocator, args: []const [:0]const u8) !Options {
    var o: Options = .{};
    var parts: std.ArrayList([]const u8) = .empty;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) o.command = .help else if (std.mem.eql(u8, arg, "--version")) o.command = .version else if (std.mem.eql(u8, arg, "--json")) o.json = true else if (std.mem.eql(u8, arg, "--man")) o.man = true else if (std.mem.eql(u8, arg, "--source")) o.source = true else if (std.mem.eql(u8, arg, "--no-color")) o.color = .never else if (std.mem.eql(u8, arg, "--color")) o.color = .always else if (std.mem.startsWith(u8, arg, "--color=")) o.color = std.meta.stringToEnum(Mode, arg[8..]) orelse return error.InvalidArguments else if (std.mem.startsWith(u8, arg, "--pager=")) o.pager = std.meta.stringToEnum(Mode, arg[8..]) orelse return error.InvalidArguments else if (std.mem.eql(u8, arg, "--limit")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            o.limit = std.fmt.parseInt(usize, args[i], 10) catch return error.InvalidArguments;
            if (o.limit == 0 or o.limit > 1000) return error.InvalidArguments;
        } else if (std.mem.startsWith(u8, arg, "--")) return error.InvalidArguments else if (parts.items.len == 0 and o.command == .lookup and std.meta.stringToEnum(@FieldType(Options, "command"), arg) != null) o.command = std.meta.stringToEnum(@FieldType(Options, "command"), arg).? else try parts.append(a, arg);
    }
    o.query = try std.mem.join(a, " ", parts.items);
    if (o.query.len == 0 and o.command == .lookup) o.command = .help;
    if (o.query.len == 0 and (o.command == .search or o.command == .source or o.command == .edit or o.command == .man)) return error.InvalidArguments;
    return o;
}

test "man command and reference flags preserve JSON mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const reference = try parse(a, &.{ "zman", "std.posix.read", "--man", "--json" });
    try std.testing.expect(reference.command == .lookup and reference.man and reference.json);
    const command = try parse(a, &.{ "zman", "man", "std.posix.read", "--json" });
    try std.testing.expect(command.command == .man and command.json);
    try std.testing.expectError(error.InvalidArguments, parse(a, &.{ "zman", "man" }));
}

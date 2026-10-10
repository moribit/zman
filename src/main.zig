const std = @import("std");
const cli = @import("cli.zig");
const environment = @import("environment.zig");
const parser = @import("parser.zig");
const cache = @import("cache.zig");
const search = @import("search.zig");
const render = @import("render.zig");
const pager = @import("pager.zig");
pub fn main(init: std.process.Init) void {
    execute(init) catch |err| {
        const message: []const u8 = switch (err) {
            error.ZigExecutableNotFound => "Zig executable not found in PATH",
            error.ZigEnvFailure => "zig env failed",
            error.StdlibNotFound => "Zig standard library not found",
            error.FileNotFound => "stdlib or source file not found",
            error.ParseFailure => "could not parse Zig standard library",
            error.InvalidArguments => "invalid arguments (see --help)",
            error.SymbolNotFound => "symbol not found",
            error.AmbiguousQuery => "query is ambiguous; use a fully-qualified symbol",
            error.EditorNotConfigured => "set ZMAN_EDITOR, VISUAL, or EDITOR",
            error.EditorFailure => "editor failed",
            error.PagerFailure => "pager failed",
            else => @errorName(err),
        };
        const text = std.fmt.allocPrint(init.arena.allocator(), "error: {s}\n", .{message}) catch return;
        std.Io.File.stderr().writeStreamingAll(init.io, text) catch {};
        std.process.exit(1);
    };
}
fn execute(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    const options = try cli.parse(a, try init.minimal.args.toSlice(a));
    if (options.command == .help) {
        try std.Io.File.stdout().writeStreamingAll(io, cli.help);
        return;
    }
    const env = try environment.detect(a, io);
    if (options.command == .version) {
        try std.Io.File.stdout().writeStreamingAll(io, try std.fmt.allocPrint(a, "zman 0.1.0\nZig docs: {s}\n", .{env.version}));
        return;
    }
    if (!std.mem.startsWith(u8, env.version, "0.17.")) try std.Io.File.stderr().writeStreamingAll(io, "warning: zman was developed against Zig 0.17\n");
    const id = try cache.identity(a, env);
    const filename = try cache.path(a, init.environ_map, id);
    var index: ?@import("index.zig").Index = null;
    if (options.command != .reindex) if (filename) |p| {
        index = cache.load(a, io, p, id) catch null;
    };
    if (index == null) {
        var builder: parser.Builder = .{ .a = a, .io = io, .root = env.std_dir };
        index = try builder.build();
        if (filename) |p| cache.save(a, io, p, id, index.?) catch {
            try std.Io.File.stderr().writeStreamingAll(io, "warning: could not write cache\n");
        };
    }
    const entries = index.?.entries;
    if (options.command == .reindex) {
        try std.Io.File.stdout().writeStreamingAll(io, try std.fmt.allocPrint(a, "Indexed {d} declarations from Zig {s}.\n", .{ entries.len, env.version }));
        return;
    }
    const tty = try std.Io.File.stdout().isTty(io);
    const color = !options.json and options.color != .never and init.environ_map.get("NO_COLOR") == null and !std.mem.eql(u8, init.environ_map.get("TERM") orelse "", "dumb") and (options.color == .always or tty);
    if (options.command != .search) if (search.exact(entries, options.query)) |i| {
        const e = entries[i];
        if (options.command == .edit) {
            try pager.edit(a, io, init.environ_map, e.source_path, e.source_line);
            return;
        }
        var output = if (options.json) try render.json(a, e, env.version) else if (options.command == .source) try render.source(a, io, e, color) else try render.human(a, e, env.version, color);
        if (options.source and !options.json and options.command != .source) output = try std.mem.concat(a, u8, &.{ output, "\n", try render.source(a, io, e, color) });
        try pager.output(a, io, init.environ_map, output, if (options.json) .never else options.pager, tty);
        return;
    };
    const matches = try search.search(init.gpa, entries, options.query, options.limit);
    defer init.gpa.free(matches);
    if (matches.len == 0) {
        try std.Io.File.stderr().writeStreamingAll(io, try std.fmt.allocPrint(a, "No matches for: {s}\n", .{options.query}));
        return error.SymbolNotFound;
    }
    if (options.command == .edit or options.command == .source) {
        try std.Io.File.stderr().writeStreamingAll(io, try render.results(a, entries, matches, options.query));
        return error.AmbiguousQuery;
    }
    const output = if (options.json) blk: {
        var found: std.ArrayList(@import("index.zig").Entry) = .empty;
        for (matches) |match| try found.append(a, entries[match.entry_index]);
        break :blk try std.json.Stringify.valueAlloc(a, .{ .zig_version = env.version, .query = options.query, .results = found.items }, .{ .whitespace = .indent_2 });
    } else try render.results(a, entries, matches, options.query);
    try pager.output(a, io, init.environ_map, output, if (options.json) .never else options.pager, tty);
}
test {
    std.testing.refAllDecls(@This());
    _ = @import("highlight.zig");
    _ = @import("search.zig");
    _ = @import("pager.zig");
    _ = @import("tests.zig");
}

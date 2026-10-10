const std = @import("std");
const cli = @import("cli.zig");
const environment = @import("environment.zig");
const parser = @import("parser.zig");
const cache = @import("cache.zig");
const search = @import("search.zig");
const render = @import("render.zig");
const pager = @import("pager.zig");
const semantic = @import("semantic.zig");
const man = @import("man.zig");
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
            error.ManCommandNotFound => "man command not found",
            error.ManCommandFailed => "man command failed",
            error.ManMappingNotFound => "no explicit system manual mapping for this symbol",
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
        try std.Io.File.stdout().writeStreamingAll(io, try std.fmt.allocPrint(a, "zman {s}\nZig docs: {s}\n", .{ @import("build_options").version, env.version }));
        return;
    }
    if (!std.mem.startsWith(u8, env.version, "0.17.")) try std.Io.File.stderr().writeStreamingAll(io, "warning: zman was developed against Zig 0.17\n");
    const id = try cache.identity(a, io, env);
    const filename = try cache.path(a, init.environ_map, id);
    var index: ?@import("index.zig").Index = null;
    if (options.command != .reindex) if (filename) |p| {
        index = cache.load(a, io, p, id) catch null;
    };
    if (index == null) {
        try std.Io.File.stderr().writeStreamingAll(io, try std.fmt.allocPrint(a, "Indexing Zig {s} documentation (official autodoc backend)...\n", .{env.version}));
        var builder: parser.Builder = .{ .a = a, .io = io, .root = env.std_dir };
        index = try builder.build();
        const work_parent = if (filename) |p| std.fs.path.dirname(p).? else init.environ_map.get("TMPDIR") orelse "/tmp";
        semantic.resolve(a, io, env, work_parent, &index.?) catch |err| {
            try std.Io.File.stderr().writeStreamingAll(io, try std.fmt.allocPrint(a, "warning: semantic backend unavailable ({s}); using syntax index\n", .{@errorName(err)}));
        };
        if (filename) |p| cache.save(a, io, p, id, index.?) catch {
            try std.Io.File.stderr().writeStreamingAll(io, "warning: could not write cache\n");
        };
    }
    const entries = index.?.entries;
    if (options.command == .reindex) {
        const text = if (options.json) try std.json.Stringify.valueAlloc(a, .{ .zig_version = env.version, .index_entries = entries.len, .semantic = index.?.semantic }, .{ .whitespace = .indent_2 }) else try std.fmt.allocPrint(a, "Indexed {d} declarations from Zig {s}.\nSemantic backend: {s}; resolved: {d}; partial: {d}; unresolved: {d}; cyclic: {d}; alias edges: {d}.\n", .{ entries.len, env.version, @tagName(index.?.semantic.backend), index.?.semantic.resolved, index.?.semantic.partially_resolved, index.?.semantic.unresolved, index.?.semantic.cyclic, index.?.semantic.alias_edges });
        try std.Io.File.stdout().writeStreamingAll(io, text);
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
        const manual = man.reference(e.fq_name);
        if (options.command == .man and !options.json) {
            try std.Io.File.stdout().writeStreamingAll(io, try std.fmt.allocPrint(a, "Zig API:\n    {s}\n\n{s}\n", .{ e.fq_name, try man.describe(a, manual) }));
            const ref = manual orelse return error.ManMappingNotFound;
            man.open(io, ref, "man") catch |err| {
                if (err == error.ManualPageNotInstalled) {
                    try std.Io.File.stderr().writeStreamingAll(io, try std.fmt.allocPrint(a, "error: manual page {s}({d}) is not installed on this host\n", .{ ref.page, ref.section }));
                    std.process.exit(1);
                }
                return err;
            };
            return;
        }
        var output = if (options.json) try render.json(a, e, env.version) else if (options.command == .source) try render.source(a, io, e, color) else try render.human(a, e, env.version, color);
        if (options.source and !options.json and options.command != .source) output = try std.mem.concat(a, u8, &.{ output, "\n", try render.source(a, io, e, color) });
        if (options.man and !options.json) output = try std.mem.concat(a, u8, &.{ "ZIG DOCUMENTATION\n\n", output, "\n", try man.describe(a, manual) });
        try pager.output(a, io, init.environ_map, output, if (options.json) .never else options.pager, tty);
        return;
    };
    const matches = try search.search(init.gpa, entries, options.query, options.limit);
    defer init.gpa.free(matches);
    if (matches.len == 0) {
        try std.Io.File.stderr().writeStreamingAll(io, try std.fmt.allocPrint(a, "No matches for: {s}\n", .{options.query}));
        return error.SymbolNotFound;
    }
    if (options.command == .edit or options.command == .source or options.command == .man) {
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
    _ = @import("man.zig");
    _ = @import("semantic.zig");
    _ = @import("cli.zig");
}

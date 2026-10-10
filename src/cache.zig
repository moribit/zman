const std = @import("std");
const model = @import("index.zig");
const Environment = @import("environment.zig").Environment;
const Payload = struct { format: u32 = 2, identity: []const u8, index: model.Index };
pub fn identity(a: std.mem.Allocator, io: std.Io, env: Environment) ![]const u8 {
    var backend = std.hash.Wyhash.init(@import("semantic.zig").revision);
    for ([_][]const u8{ "Walk.zig", "Decl.zig" }) |name| {
        const file = try std.fs.path.join(a, &.{ env.lib_dir, "docs/wasm", name });
        const stat = std.Io.Dir.cwd().statFile(io, file, .{}) catch {
            backend.update("unavailable");
            continue;
        };
        const metadata = try std.fmt.allocPrint(a, "{d}:{d}", .{ stat.size, stat.mtime.nanoseconds });
        backend.update(metadata);
    }
    return std.fmt.allocPrint(a, "2|autodoc-{x}|{s}|{s}|{s}|{s}", .{ backend.final(), env.version, env.zig_exe, env.std_dir, env.target });
}
pub fn path(a: std.mem.Allocator, map: *std.process.Environ.Map, id: []const u8) !?[]const u8 {
    const base = map.get("XDG_CACHE_HOME") orelse if (map.get("HOME")) |home| try std.fs.path.join(a, &.{ home, if (@import("builtin").os.tag == .macos) "Library/Caches" else ".cache" }) else return null;
    return try std.fmt.allocPrint(a, "{s}/zman/{x}/index.json", .{ base, std.hash.Wyhash.hash(0, id) });
}
// All decoded index storage belongs to the caller's long-lived arena.
pub fn load(a: std.mem.Allocator, io: std.Io, filename: []const u8, id: []const u8) !model.Index {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, filename, a, .limited(64 * 1024 * 1024));
    var header = std.mem.splitScalar(u8, bytes, '\n');
    if (!std.mem.eql(u8, header.next() orelse return error.CacheCorruption, "ZMAN")) return error.CacheCorruption;
    if (!std.mem.eql(u8, header.next() orelse return error.CacheCorruption, "2")) return error.CacheInvalidated;
    const checksum = std.fmt.parseInt(u64, header.next() orelse return error.CacheCorruption, 16) catch return error.CacheCorruption;
    const payload = header.rest();
    if (std.hash.Wyhash.hash(0, payload) != checksum) return error.CacheCorruption;
    const parsed = try std.json.parseFromSlice(Payload, a, payload, .{ .allocate = .alloc_if_needed });
    if (parsed.value.format != 2 or !std.mem.eql(u8, parsed.value.identity, id)) return error.CacheInvalidated;
    for (parsed.value.index.files) |file| {
        const stat = try std.Io.Dir.cwd().statFile(io, file.path, .{});
        if (stat.size != file.size or stat.mtime.nanoseconds != file.mtime) return error.CacheInvalidated;
    }
    for (parsed.value.index.entries) |entry| if (entry.declaration_end < entry.declaration_start or entry.source_line == 0 or !std.mem.startsWith(u8, entry.fq_name, "std.")) return error.CacheCorruption;
    for (parsed.value.index.entries) |entry| if (entry.target_entry) |target| {
        if (target >= parsed.value.index.entries.len) return error.CacheCorruption;
    };
    return parsed.value.index;
}
pub fn save(a: std.mem.Allocator, io: std.Io, filename: []const u8, id: []const u8, index: model.Index) !void {
    const payload = try std.json.Stringify.valueAlloc(a, Payload{ .identity = id, .index = index }, .{ .emit_null_optional_fields = false });
    defer a.free(payload);
    const header = try std.fmt.allocPrint(a, "ZMAN\n2\n{x}\n", .{std.hash.Wyhash.hash(0, payload)});
    const bytes = try std.mem.concat(a, u8, &.{ header, payload });
    defer a.free(bytes);
    try std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(filename).?);
    var random: [8]u8 = undefined;
    std.Io.random(io, &random);
    const temporary = try std.fmt.allocPrint(a, "{s}.{x}.tmp", .{ filename, std.mem.readInt(u64, &random, .little) });
    defer std.Io.Dir.cwd().deleteFile(io, temporary) catch {};
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = temporary, .data = bytes, .flags = .{ .exclusive = true } });
    try std.Io.Dir.rename(.cwd(), temporary, .cwd(), filename, io);
}

const std = @import("std");
const model = @import("index.zig");
const Environment = @import("environment.zig").Environment;
const Payload = struct { format: u32 = 1, identity: []const u8, index: model.Index };
const Envelope = struct { marker: []const u8 = "ZMAN", checksum: u64, payload: []const u8 };
pub fn identity(a: std.mem.Allocator, env: Environment) ![]const u8 {
    return std.fmt.allocPrint(a, "{s}|{s}|{s}|{s}", .{ env.version, env.zig_exe, env.std_dir, env.target });
}
pub fn path(a: std.mem.Allocator, map: *std.process.Environ.Map, id: []const u8) !?[]const u8 {
    const base = map.get("XDG_CACHE_HOME") orelse if (map.get("HOME")) |home| try std.fs.path.join(a, &.{ home, if (@import("builtin").os.tag == .macos) "Library/Caches" else ".cache" }) else return null;
    return try std.fmt.allocPrint(a, "{s}/zman/{x}/index.json", .{ base, std.hash.Wyhash.hash(0, id) });
}
// All decoded index storage belongs to the caller's long-lived arena.
pub fn load(a: std.mem.Allocator, io: std.Io, filename: []const u8, id: []const u8) !model.Index {
    const bytes = try model.read(a, io, filename);
    defer a.free(bytes);
    const envelope = try std.json.parseFromSlice(Envelope, a, bytes, .{ .allocate = .alloc_always });
    if (!std.mem.eql(u8, envelope.value.marker, "ZMAN") or std.hash.Wyhash.hash(0, envelope.value.payload) != envelope.value.checksum) return error.CacheCorruption;
    const parsed = try std.json.parseFromSlice(Payload, a, envelope.value.payload, .{ .allocate = .alloc_always });
    if (parsed.value.format != 1 or !std.mem.eql(u8, parsed.value.identity, id)) return error.CacheInvalidated;
    for (parsed.value.index.files) |file| {
        const stat = try std.Io.Dir.cwd().statFile(io, file.path, .{});
        if (stat.size != file.size or stat.mtime.nanoseconds != file.mtime) return error.CacheInvalidated;
    }
    for (parsed.value.index.entries) |entry| if (entry.declaration_end < entry.declaration_start or entry.source_line == 0 or !std.mem.startsWith(u8, entry.fq_name, "std.")) return error.CacheCorruption;
    return parsed.value.index;
}
pub fn save(a: std.mem.Allocator, io: std.Io, filename: []const u8, id: []const u8, index: model.Index) !void {
    const payload = try std.json.Stringify.valueAlloc(a, Payload{ .identity = id, .index = index }, .{});
    defer a.free(payload);
    const bytes = try std.json.Stringify.valueAlloc(a, Envelope{ .checksum = std.hash.Wyhash.hash(0, payload), .payload = payload }, .{});
    defer a.free(bytes);
    try std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(filename).?);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = filename, .data = bytes });
}

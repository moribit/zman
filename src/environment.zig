const std = @import("std");
pub const Environment = struct { zig_exe: []const u8, version: []const u8, lib_dir: []const u8, std_dir: []const u8, target: []const u8 };
pub fn detect(a: std.mem.Allocator, io: std.Io) !Environment {
    const result = std.process.run(a, io, .{ .argv = &.{ "zig", "env" }, .stdout_limit = .limited(1024 * 1024) }) catch |err| switch (err) {
        error.FileNotFound => return error.ZigExecutableNotFound,
        else => return error.ZigEnvFailure,
    };
    defer a.free(result.stdout);
    defer a.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) return error.ZigEnvFailure;
    const keys = [_][]const u8{ "zig_exe", "version", "lib_dir", "std_dir", "target" };
    var values: [5][]const u8 = undefined;
    if (std.mem.startsWith(u8, std.mem.trimStart(u8, result.stdout, " \n"), "{")) {
        const parsed = try std.json.parseFromSlice(std.json.Value, a, result.stdout, .{});
        defer parsed.deinit();
        for (keys, 0..) |key, i| values[i] = try a.dupe(u8, (parsed.value.object.get(key) orelse return error.ZigEnvFailure).string);
    } else {
        const source = try a.dupeSentinel(u8, result.stdout, 0);
        defer a.free(source);
        var tokenizer = std.zig.Tokenizer.init(source);
        var found: [5]bool = @splat(false);
        while (true) {
            const token = tokenizer.next();
            if (token.tag == .eof) break;
            if (token.tag != .identifier) continue;
            for (keys, 0..) |key, i| if (std.mem.eql(u8, source[token.loc.start..token.loc.end], key)) {
                if (tokenizer.next().tag != .equal) return error.ZigEnvFailure;
                const value = tokenizer.next();
                if (value.tag != .string_literal) return error.ZigEnvFailure;
                values[i] = try std.zig.string_literal.parseAlloc(a, source[value.loc.start..value.loc.end]);
                found[i] = true;
            };
        }
        for (found) |ok| if (!ok) return error.ZigEnvFailure;
    }
    return .{ .zig_exe = values[0], .version = values[1], .lib_dir = values[2], .std_dir = values[3], .target = values[4] };
}

const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize });
    const exe = b.addExecutable(.{ .name = "zman", .root_module = module });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    b.step("run", "Run zman").dependOn(&run.step);
    const integration = b.step("integration", "Query the installed Zig standard library");
    for ([_][]const []const u8{
        &.{"--version"}, &.{"std.posix.read"},             &.{"posix.read"},                 &.{"read"},
        &.{"open file"}, &.{ "source", "std.posix.read" }, &.{ "--json", "std.posix.read" },
    }) |args| {
        const check = b.addRunArtifact(exe);
        check.addArgs(args);
        integration.dependOn(&check.step);
    }
    const tests = b.addTest(.{ .root_module = module });
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(tests).step);
}

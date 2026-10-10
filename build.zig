const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize });
    const options = b.addOptions();
    options.addOption([]const u8, "version", @import("build.zig.zon").version);
    module.addOptions("build_options", options);
    const exe = b.addExecutable(.{ .name = "zman", .root_module = module });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    b.step("run", "Run zman").dependOn(&run.step);
    const integration = b.step("integration", "Query the installed Zig standard library");
    var previous: ?*std.Build.Step = null;
    for ([_][]const []const u8{
        &.{"--version"},     &.{"std.posix.read"},             &.{"posix.read"},                        &.{"read"},
        &.{"open file"},     &.{ "source", "std.posix.read" }, &.{ "--json", "std.posix.read" },        &.{"std.ArrayListUnmanaged"},
        &.{"std.ArrayList"}, &.{ "std.posix.read", "--man" },  &.{ "man", "std.posix.read", "--json" },
    }) |args| {
        const check = b.addRunArtifact(exe);
        check.addArgs(args);
        check.setEnvironmentVariable("XDG_CACHE_HOME", ".zig-cache/zman-integration");
        if (previous) |step| check.step.dependOn(step);
        previous = &check.step;
        integration.dependOn(&check.step);
    }
    const semantic_checks = b.addExecutable(.{ .name = "semantic-integration", .root_module = b.createModule(.{ .root_source_file = b.path("src/integration.zig"), .target = target, .optimize = optimize }) });
    integration.dependOn(&b.addRunArtifact(semantic_checks).step);
    const tests = b.addTest(.{ .root_module = module });
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(tests).step);
}

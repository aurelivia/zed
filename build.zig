const std = @import("std");
const view = @import("./view/build.zig");

pub fn build(b: *std.Build) void {
    // view.build(b);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root = b.addModule("root", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });

    // const zg = b.dependency("zg", .{ .target = target, .optimize = optimize });
    // root.addImport("zg-normalize", zg.module("Normalize"));

    const tests = b.addTest(.{ .root_module = root });
    const test_step = b.step("test", "test");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const repl = b.createModule(.{ .root_source_file = b.path("src/repl.zig"), .target = target, .optimize = optimize });
    const exe = b.addExecutable(.{ .name = "repl", .root_module = repl });
    b.installArtifact(exe);
    const step = b.step("run", ".");
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    step.dependOn(&run.step);
}

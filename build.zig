const std = @import("std");
const view = @import("./view/build.zig");

pub fn build(b: *std.Build) void {
    // view.build(b);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root = b.addModule("root", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });

    const main = b.createModule(.{ .root_source_file = b.path("test/main.zig"), .target = target, .optimize = optimize });
    const exe = b.addExecutable(.{ .name = "test", .root_module = main });
    exe.root_module.addImport("self", root);
    b.installArtifact(exe);
    const step = b.step("run", ".");
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    step.dependOn(&run.step);
}

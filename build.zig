const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "inon",
        .root_source_file = .{ .path = "demo.zig" },
        .optimize = optimize,
    });

    exe.addModule("parser-toolkit", b.dependency("parser-toolkit", .{
        .optimize = optimize,
    }).module("parser-toolkit"));

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the demo");
    run_step.dependOn(&b.addRunArtifact(exe).step);

    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/test.zig" },
        .optimize = optimize,
    });
    tests.addModule("parser-toolkit", b.dependency("parser-toolkit", .{
        .optimize = optimize,
    }).module("parser-toolkit"));

    const tests_step = b.step("test", "Run tests");
    tests_step.dependOn(&b.addRunArtifact(tests).step);
}

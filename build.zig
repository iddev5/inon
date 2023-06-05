const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const inon_mod = b.addModule("inon", .{
        .source_file = .{ .path = "src/main.zig" },
        .dependencies = &.{
            .{
                .name = "parser-toolkit",
                .module = b.dependency("parser-toolkit", .{
                    .optimize = optimize,
                }).module("parser-toolkit"),
            },
        },
    });

    const exe = b.addExecutable(.{
        .name = "inon",
        .root_source_file = .{ .path = "demo.zig" },
        .optimize = optimize,
    });
    exe.addModule("inon", inon_mod);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the demo");
    run_step.dependOn(&b.addRunArtifact(exe).step);

    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/test.zig" },
        .optimize = optimize,
    });
    tests.addModule("inon", inon_mod);

    const tests_step = b.step("test", "Run tests");
    tests_step.dependOn(&b.addRunArtifact(tests).step);
}

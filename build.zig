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

    // Demo application
    const demo = b.addExecutable(.{
        .name = "inon-demo",
        .root_source_file = .{ .path = "demo.zig" },
        .optimize = optimize,
    });
    demo.addModule("inon", inon_mod);
    b.installArtifact(demo);

    const run_step = b.step("run-demo", "Run the demo");
    run_step.dependOn(&b.addRunArtifact(demo).step);

    // Repl application
    const repl = b.addExecutable(.{
        .name = "inon-repl",
        .root_source_file = .{ .path = "repl.zig" },
        .optimize = optimize,
    });
    repl.addModule("inon", inon_mod);
    b.installArtifact(repl);

    const repl_step = b.step("run-repl", "Run the repl");
    repl_step.dependOn(&b.addRunArtifact(repl).step);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/test.zig" },
        .optimize = optimize,
    });
    tests.addModule("inon", inon_mod);

    const tests_step = b.step("test", "Run tests");
    tests_step.dependOn(&b.addRunArtifact(tests).step);
}

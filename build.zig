const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "gb",
        .root_module = b.createModule(.{
            .optimize = optimize,
            .target = target,
            .root_source_file = b.path("src/main.zig"),
            .imports = &.{.{
                .name = "sokol",
                .module = sokol.module("sokol"),
            }},
        }),
    });

    const check = b.step("check", "Check step for ZLS");
    check.dependOn(&exe.step);

    b.installArtifact(exe);
}

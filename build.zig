const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const sdl3 = b.dependency("sdl3", .{
        .optimize = optimize,
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "gb",
        .root_module = b.createModule(.{
            .optimize = optimize,
            .target = target,
            .root_source_file = b.path("src/main.zig"),
        }),
    });
    exe.root_module.addImport("sdl3", sdl3.module("sdl3"));
    b.installArtifact(exe);

    const check = b.step("check", "Check step for ZLS");
    check.dependOn(&exe.step);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");

    run_step.dependOn(&run.step);
}

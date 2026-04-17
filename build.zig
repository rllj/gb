const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const sdl3 = b.dependency("sdl3", .{
        .optimize = optimize,
        .target = target,
    });

    const lib_mod = b.addModule("GB", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const emu_mod = b.createModule(.{
        .root_source_file = b.path("emu/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "GB", .module = lib_mod },
            .{ .name = "sdl3", .module = sdl3.module("sdl3") },
        },
    });

    const lib = b.addLibrary(.{
        .root_module = lib_mod,
        .name = "GB",
    });
    const install_lib = b.addInstallArtifact(lib, .{});

    const emu = b.addExecutable(.{
        .name = "emu",
        .root_module = emu_mod,
    });
    const install_emu = b.addInstallArtifact(emu, .{});
    const run_emu = b.addRunArtifact(emu);

    const install_emu_step = b.step("emu", "Compile the emu");
    install_emu_step.dependOn(&install_emu.step);

    const run_step = b.step("run-emu", "Run the emulator");
    run_step.dependOn(&run_emu.step);

    const check = b.step("check", "Check step for ZLS");
    check.dependOn(&install_lib.step);
}

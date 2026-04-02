const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const GB = @import("GB").GB;

const Command = enum {
    @"continue",
    breakpoint,
    step,
};

const CommandError = error{
    InvalidCommand,
};

const commands = std.StaticStringMap(Command).initComptime(.{
    .{ "continue", .@"continue" },
    .{ "breakpoint", .breakpoint },
    .{ "step", .step },
});

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    defer init.arena.deinit();

    var stdout = Io.File.stdout();
    defer stdout.close(init.io);
    var stdout_writer = stdout.writer(init.io, &.{});

    var gb: GB = try .init(arena, @embedFile("roms/06-ld r,r.gb"));
    while (gb.sm83.registers.pc < 0x100) {
        gb.tick_inst();
    }
    try gb.debug_log(&stdout_writer.interface);

    const stdin = Io.File.stdin();
    defer stdin.close(init.io);
    var buffer: [256]u8 = undefined;
    var reader = stdin.reader(init.io, &buffer);

    var breakpoint: ?u16 = null;
    while (true) {
        if ((reader.interface.takeDelimiter('\n') catch null)) |string| {
            var iterator = std.mem.tokenizeScalar(u8, string, ' ');
            const command_string = iterator.next() orelse unreachable;
            const arg_or_null = iterator.next();
            if (commands.get(command_string)) |command| {
                switch (command) {
                    .@"continue" => {},
                    .breakpoint => breakpoint = try std.fmt.parseInt(u16, arg_or_null.?, 16),
                    .step => {
                        gb.tick_inst();
                        try gb.debug_log(&stdout_writer.interface);
                    },
                }
            } else {
                std.debug.print("Invalid command '{s}'\n", .{string});
            }
        }
    }
}

fn read_file_from_args(gpa: std.mem.Allocator, io: Io, args: std.process.Args) ![]const u8 {
    // TODO support Windows
    var args_iter = args.iterate();
    const rom_path = args_iter.next() orelse return error.MissingRom;

    return read_file(gpa, io, rom_path);
}

fn read_file(gpa: std.mem.Allocator, io: Io, file_path: []const u8) ![]const u8 {
    return Io.Dir.readFileAlloc(.cwd(), io, file_path, gpa, .unlimited);
}

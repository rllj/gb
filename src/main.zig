const std = @import("std");
const allocator = std.heap.page_allocator;

const GB = @import("GB.zig");

pub fn main(init: std.process.Init) !void {
    const cartridge = @embedFile("roms/02-interrupts.gb");

    var stdout = std.Io.File.stdout();
    defer stdout.close(init.io);
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(init.io, &buffer);
    defer writer.flush() catch {};

    var gb: GB = try .init(allocator, init.io, cartridge);
    defer gb.deinit(allocator);
    while (true) {
        try gb.tick_debug(&writer.interface);

        if (std.mem.containsAtLeast(u8, gb.serial_input.items, 1, "Passed\n")) {
            break;
        }
    }
}

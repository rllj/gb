const std = @import("std");
const allocator = std.heap.page_allocator;

const CPU = @import("CPU.zig");

pub fn main() !void {
    const cartridge = @embedFile("roms/06-ld r,r.gb");

    var gb: CPU = try .init(allocator, cartridge);
    defer gb.deinit(allocator);
    while (true) {
        gb.tick();
    }
}

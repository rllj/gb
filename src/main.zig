const std = @import("std");
const allocator = std.heap.page_allocator;

const GB = @import("GB.zig");

pub fn main() !void {
    const cartridge = @embedFile("roms/06-ld r,r.gb");

    var gb: GB = try .init(allocator, cartridge);
    defer gb.deinit(allocator);
    while (true) {
        gb.tick();
    }
}

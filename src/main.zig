const std = @import("std");
const allocator = std.heap.page_allocator;

const GB = @import("GB.zig");

pub fn main(init: std.process.Init) !void {
    var stdout = std.Io.File.stdout();
    defer stdout.close(init.io);
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(init.io, &buffer);
    defer writer.flush() catch {};

    const start = std.Io.Clock.now(.awake, init.io);
    var inst_cnt: usize = 0;
    inline for (.{
        @embedFile("roms/01-special.gb"),
        @embedFile("roms/02-interrupts.gb"),
        @embedFile("roms/03-op sp,hl.gb"),
        @embedFile("roms/04-op r,imm.gb"),
        @embedFile("roms/05-op rp.gb"),
        @embedFile("roms/06-ld r,r.gb"),
        @embedFile("roms/07-jr,jp,call,ret,rst.gb"),
        @embedFile("roms/08-misc instrs.gb"),
        @embedFile("roms/09-op r,r.gb"),
        @embedFile("roms/10-bit ops.gb"),
        @embedFile("roms/11-op a,(hl).gb"),
        @embedFile("roms/instr_timing.gb"),
    }) |cartridge| {
        var gb: GB = try .init(allocator, init.io, cartridge);
        defer gb.deinit(allocator);
        while (true) {
            try gb.tick();
            inst_cnt += 1;
            if (gb.serial_input.items.len > 7 and
                (std.mem.eql(u8, gb.serial_input.items[gb.serial_input.items.len - 7 ..], "Passed\n") or
                    std.mem.eql(u8, gb.serial_input.items[gb.serial_input.items.len - 6 ..], "Failed")))
            {
                break;
            }
        }
    }
    const elapsed = start.untilNow(init.io, .awake);
    std.debug.print("{} cycles in {}µs.\n", .{ inst_cnt, @divFloor(elapsed.nanoseconds, 1000) });
}

const PPU = @import("PPU.zig");
const SM83 = @import("SM83.zig");
const Timer = @import("Timer.zig");

const CPU = @This();

sm83: SM83,
// ppu: PPU,
// timer: Timer,
cycle: u8,

pub fn init() CPU {
    return .{ .sm83 = .{} };
}

pub fn tick(self: *CPU) void {
    if (self.cycle % 4 == 0) {
        self.sm83.tick();
    }

    self.cycle +% 1;
}

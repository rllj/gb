const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const SM83 = @import("SM83.zig");
const Pins = SM83.Pins;

const logger = @import("std").log.scoped(.gameboy);

// TODO find a nicer home for these
const IY = 0xFF44;
const SERIAL_TRANSFER = 0xFF01;
const SERIAL_CONTROL = 0xFF02;

// TODO boot rom
// const PPU = @import("PPU.zig");
// const Timer = @import("Timer.zig");
const GB = @This();
sm83: SM83,
memory: []u8,
bus: Pins,
cycle: usize = 0,

io: std.Io,
serial_input: std.ArrayList(u8),

pub fn init(allocator: Allocator, io: std.Io, cartridge: []const u8) !GB {
    const memory: []u8 = try allocator.alloc(u8, 0x10000);
    @memset(memory, 0x0);
    @memcpy(memory[0x0..0x8000], cartridge[0x0..0x8000]);
    const serial_input: std.ArrayList(u8) = try .initCapacity(allocator, 4096);
    return .{
        .sm83 = .{},
        .memory = memory,
        .bus = .{ .abus = 0x100, .dbus = memory[0x100] },
        .io = io,
        .serial_input = serial_input,
    };
}

pub fn deinit(self: *GB, allocator: Allocator) void {
    allocator.free(self.memory);
}

/// To be called at 4.194304 MHz.
pub fn tick(self: *GB) !void {
    if (self.cycle % 4 == 0) {
        const bus = self.sm83.tick(self.bus);
        self.bus = self.handle_cpu_bus(bus);
    }
    self.cycle += 1;
}

pub fn tick_debug(self: *GB, writer: *std.Io.Writer) !void {
    if (self.cycle == 0) {
        try self.debug_log(writer);
    }

    if (self.cycle % 4 == 0) {
        const bus = self.sm83.tick(self.bus);
        self.bus = self.handle_cpu_bus(bus);
        if (self.bus.m1 == 1 and self.bus.prefix_cb == 0) {
            try self.debug_log(writer);
        }
    }

    self.cycle += 1;
}

pub fn handle_cpu_bus(self: *GB, bus: Pins) Pins {
    if (bus.mreq == 1 and bus.wr == 1) {
        switch (bus.abus) {
            0x0000...0x7FFF => @panic("Attempt to write to ROM"),
            0x8000...0x9FFF => self.write_vram(bus.abus, bus.dbus),
            0xA000...0xBFFF => self.write_ram(bus.abus, bus.dbus),
            0xC000...0xDFFF => self.write_ram(bus.abus, bus.dbus),
            0xE000...0xFDFF => @panic("Attempt to write to echo area"), // TODO: not sure what is supposed to happen here
            0xFE00...0xFE9F => self.write_oam(bus.abus, bus.dbus),
            0xFEA0...0xFEFF => @panic("Not usable"),
            0xFF00...0xFF7F => self.write_io(bus.abus, bus.dbus),
            // TODO: I might have to separate this, as HRAM differs ever so slightly from regular RAM by being accessible during a DMA transfer.
            // https://retrocomputing.stackexchange.com/questions/11811/how-does-game-boy-sharp-lr35902-hram-work
            0xFF80...0xFFFE => self.write_ram(bus.abus, bus.dbus),
            0xFFFF => self.write_ie(bus.dbus),
        }
        return bus;
    } else if (bus.mreq == 1 and bus.rd == 1) {
        return switch (bus.abus) {
            0x0000...0x7FFF => self.read_ram(bus),
            0x8000...0x9FFF => self.read_vram(bus),
            0xA000...0xBFFF => self.read_ram(bus),
            0xC000...0xDFFF => self.read_ram(bus),
            0xE000...0xFDFF => self.read_ram(bus.set(.{ .abus = bus.abus - 0x2000 })),
            0xFE00...0xFE9F => self.read_oam(bus),
            0xFEA0...0xFEFF => @panic("Not usable"),
            0xFF00...0xFF7F => self.read_io(bus),
            0xFF80...0xFFFE => self.read_ram(bus),
            0xFFFF => self.read_ie(bus),
        };
    }
    return bus;
}

pub fn write_vram(self: *GB, addr: u16, data: u8) void {
    _ = self;
    _ = addr;
    _ = data;
}

pub fn write_ram(self: *GB, addr: u16, data: u8) void {
    self.memory[addr] = data;
}

pub fn write_oam(self: *GB, addr: u16, data: u8) void {
    _ = self;
    _ = addr;
    _ = data;
}

pub fn write_io(self: *GB, addr: u16, data: u8) void {
    if (addr == SERIAL_TRANSFER) {
        std.debug.print("{c}", .{data});
        self.serial_input.appendBounded(data) catch {
            self.serial_input.clearRetainingCapacity();
            self.serial_input.appendAssumeCapacity(data);
            logger.warn("Ran out of serial storage, overwriting old data.", .{});
        }; // Stupid, but works for now
    }
    self.write_ram(addr, data);
}

pub fn write_ie(self: *GB, data: u8) void {
    self.memory[0xFFFF] = data;
}

pub fn read_vram(self: *GB, bus: Pins) Pins {
    _ = self;
    return bus;
}

pub fn read_ram(self: *GB, bus: Pins) Pins {
    return bus.set(.{ .dbus = self.memory[bus.abus] });
}

pub fn read_oam(self: *GB, bus: Pins) Pins {
    _ = self;
    return bus;
}

pub fn read_io(self: *GB, bus: Pins) Pins {
    return switch (bus.abus) {
        IY => bus.set(.{ .dbus = 0x90 }),
        else => self.read_ram(bus),
    };
}

pub fn read_ie(self: *GB, bus: Pins) Pins {
    return bus.set(.{ .dbus = self.memory[0xFFFF] });
}

fn debug_log(self: *const GB, writer: *std.Io.Writer) !void {
    const pc = self.sm83.registers.pc;
    try writer.print(
        "A:{X:0>2} F:{X:0>2} B:{X:0>2} C:{X:0>2} D:{X:0>2} E:{X:0>2} H:{X:0>2} L:{X:0>2} SP:{X:0>4} PC:{X:0>4} PCMEM:{X:0>2},{X:0>2},{X:0>2},{X:0>2}\n",
        .{
            self.sm83.registers.a,
            @as(u8, @bitCast(self.sm83.registers.flags)),
            self.sm83.registers.b,
            self.sm83.registers.c,
            self.sm83.registers.d,
            self.sm83.registers.e,
            self.sm83.registers.h,
            self.sm83.registers.l,
            self.sm83.registers.sp,
            pc,
            self.memory[pc],
            self.memory[pc + 1],
            self.memory[pc + 2],
            self.memory[pc + 3],
        },
    );
}

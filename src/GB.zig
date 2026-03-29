const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const bootrom = @import("bootrom.zig").bytes;
const PPU = @import("PPU.zig");
const SM83 = @import("SM83.zig");
const Pins = SM83.Pins;
const Timer = @import("timer.zig").Timer;

const logger = @import("std").log.scoped(.gameboy);

const GB = @This();
sm83: SM83,
ppu: PPU,
memory: []u8,
bus: Pins,
cycle: usize = 0,
timer: *Timer,
timer_events: Timer.TimerEvents,
oam_transfer_cycle: u8,

io: std.Io,
serial_input: std.ArrayList(u8),

pub const JOYP = 0xFF00;
pub const SERIAL_TRANSFER = 0xFF01;
pub const SC = 0xFF02;
pub const IF = 0xFF0F;
pub const BANK = 0xFF50;
pub const IE = 0xFFFF;

pub fn init(allocator: Allocator, io: std.Io, cartridge: []const u8) !GB {
    const memory: []u8 = try allocator.alloc(u8, 0x10000);
    @memset(memory, 0x00);
    @memcpy(memory[0x0..0x8000], cartridge[0x0..0x8000]);

    memory[JOYP] = 0xFF;

    const serial_input: std.ArrayList(u8) = try .initCapacity(allocator, 4096);
    return .{
        .sm83 = .{},
        .ppu = .{ .oam = memory[0xFE00..0xFEA0], .vram = memory[0x8000..0xA000] },
        .memory = memory,
        .bus = .{},
        .io = io,
        .serial_input = serial_input,
        .timer = @ptrCast(memory[Timer.SYSCLK_LO .. Timer.TAC + 1]),
        .timer_events = .{},
        .oam_transfer_cycle = 0,
    };
}

pub fn deinit(self: *GB, allocator: Allocator) void {
    allocator.free(self.memory);
}

/// To be called at 4.194304 MHz.
pub fn tick(self: *GB) !void {
    try self.tcycle();
    if (self.cycle % 4 == 0) {
        try self.mcycle();
    }

    self.cycle += 1;
}

fn mcycle(self: *GB) !void {
    const prev_timer = self.timer_from_mmio();

    const has_pending_interrupt = self.sm83.ie.to_byte() & self.bus.int.to_byte() == 0;
    if (self.bus.halt == 0 or !has_pending_interrupt) {
        const bus = self.sm83.tick(self.bus);
        self.bus = self.handle_cpu_bus(bus);
    }
    self.timer_events = self.timer.tick(
        prev_timer,
        self.timer_events.overflow,
        self.bus,
    );
    if (self.timer_events.overflow) {
        self.bus.int.timer = 1;
    }

    if (self.oam_transfer_cycle != 0) {
        const offset: u16 = 160 - self.oam_transfer_cycle;
        const source: u16 = @as(u16, self.memory[PPU.DMA]) << 8 | offset;
        const dest: u16 = PPU.OAM_START + offset;
        self.memory[dest] = self.memory[source];
        self.oam_transfer_cycle -= 1;
    }
}

fn tcycle(self: *GB) !void {
    _ = self;
}

fn handle_cpu_bus(self: *GB, bus: Pins) Pins {
    if (bus.mreq == 1 and bus.wr == 1) {
        switch (bus.abus) {
            0x0000...0x7FFF => std.debug.panic("Attempt to write to ROM at 0x{X:0>4}", .{bus.abus}),
            0x8000...0x9FFF => self.write_vram(bus.abus, bus.dbus),
            0xA000...0xBFFF => self.write_ram(bus.abus, bus.dbus),
            0xC000...0xDFFF => self.write_ram(bus.abus, bus.dbus),
            0xE000...0xFDFF => @panic("Attempt to write to echo area"), // TODO: not sure what is supposed to happen here
            0xFE00...0xFE9F => self.write_oam(bus.abus, bus.dbus),
            0xFEA0...0xFEFF => @panic("Not usable"),
            0xFF0F => return self.write_if(bus),
            0xFF00...0xFF0E, 0xFF10...0xFF7F => self.write_io(bus.abus, bus.dbus),
            0xFF80...0xFFFE => self.write_hram(bus.abus, bus.dbus),
            0xFFFF => self.write_ie(bus.dbus),
        }
    } else if (bus.mreq == 1 and bus.rd == 1) {
        return switch (bus.abus) {
            0x0000...0x00FF => self.read_bootrom(bus),
            0x0100...0x7FFF => self.read_ram(bus),
            0x8000...0x9FFF => self.read_vram(bus),
            0xA000...0xBFFF => self.read_ram(bus),
            0xC000...0xDFFF => self.read_ram(bus),
            0xE000...0xFDFF => self.read_ram(bus.set(.{ .abus = bus.abus - 0x2000 })),
            0xFE00...0xFE9F => self.read_oam(bus),
            0xFEA0...0xFEFF => @panic("Not usable"),
            0xFF0F => self.read_if(bus),
            0xFF00...0xFF0E, 0xFF10...0xFF7F => self.read_io(bus),
            0xFF80...0xFFFE => self.read_ram(bus),
            0xFFFF => self.read_ie(bus),
        };
    }
    return bus;
}

fn write_vram(self: *GB, addr: u16, data: u8) void {
    if (self.oam_transfer_cycle != 0) return;
    if (self.ppu.stat.mode == .draw) return;
    self.memory[addr] = data;
}

fn write_ram(self: *GB, addr: u16, data: u8) void {
    if (self.oam_transfer_cycle != 0) return;
    self.memory[addr] = data;
}

fn write_hram(self: *GB, addr: u16, data: u8) void {
    self.memory[addr] = data;
}

fn write_oam(self: *GB, addr: u16, data: u8) void {
    if (self.oam_transfer_cycle != 0) return;
    if (self.ppu.stat.mode == .draw or self.ppu.stat.mode == .oam_scan) return;
    self.write_ram(addr, data);
}

fn write_if(_: *GB, bus: Pins) Pins {
    return bus.set(.{ .int = @as(SM83.IRMask, @bitCast(bus.dbus)) });
}

fn write_io(self: *GB, addr: u16, data: u8) void {
    if (self.oam_transfer_cycle != 0) return;
    if (addr == SERIAL_TRANSFER) {
        std.debug.print("{c}", .{data});
        self.serial_input.appendBounded(data) catch {
            self.serial_input.clearRetainingCapacity();
            self.serial_input.appendAssumeCapacity(data);
            logger.warn("Ran out of serial storage, overwriting old data.", .{});
        }; // Stupid, but works for now
    }
    switch (addr) {
        Timer.DIV => {
            self.memory[Timer.DIV] = 0;
            self.memory[Timer.SYSCLK_LO] = 0;
        },
        PPU.LCDC => self.ppu.lcdc = @bitCast(data),
        PPU.STAT => self.ppu.stat = @bitCast(data), // TODO implement stat write bug.
        PPU.SCY => self.ppu.scy = data,
        PPU.SCX => self.ppu.scx = data,
        PPU.LY => {},
        PPU.LYC => self.ppu.lyc = data,
        PPU.DMA => self.oam_transfer_cycle = 160, // check later; Might be off-by-one
        // PPU.DMA => self.ppu.dma = data,
        // PPU.BGP => self.ppu.bgp = data,
        // PPU.OBP0 => self.ppu.obp0 = data,
        // PPU.OBP1 => self.ppu.obp1 = data,
        // PPU.WY => self.ppu.wy = data,
        // PPU.WX => self.ppu.wx = data,
        else => self.write_ram(addr, data),
    }
}

fn write_ie(self: *GB, data: u8) void {
    self.sm83.ie = @bitCast(data);
}

fn read_vram(self: *GB, bus: Pins) Pins {
    if (self.oam_transfer_cycle != 0) return bus;
    if (self.ppu.stat.mode == .draw) return bus;
    return bus.set(.{ .dbus = self.memory[bus.abus] });
}

fn read_ram(self: *GB, bus: Pins) Pins {
    if (self.oam_transfer_cycle != 0) return bus;
    return bus.set(.{ .dbus = self.memory[bus.abus] });
}

fn read_bootrom(self: *GB, bus: Pins) Pins {
    if (self.oam_transfer_cycle != 0) return bus;
    if (self.memory[BANK] & 1 == 0) {
        return bus.set(.{ .dbus = bootrom[bus.abus] });
    } else {
        return bus.set(.{ .dbus = self.memory[bus.abus] });
    }
}

fn read_oam(self: *GB, bus: Pins) Pins {
    if (self.oam_transfer_cycle != 0) return bus;
    if (self.ppu.stat.mode == .draw or self.ppu.stat.mode == .oam_scan) return bus;
    return bus.set(.{ .dbus = self.memory[bus.abus] });
}

fn read_io(self: *GB, bus: Pins) Pins {
    if (self.oam_transfer_cycle != 0) return bus;
    return switch (bus.abus) {
        PPU.LCDC => bus.set(.{ .dbus = @as(u8, @bitCast(self.ppu.lcdc)) }),
        PPU.STAT => bus.set(.{ .dbus = @as(u8, @bitCast(self.ppu.stat)) }),
        PPU.SCY => bus.set(.{ .dbus = self.ppu.scy }),
        PPU.SCX => bus.set(.{ .dbus = self.ppu.scx }),
        PPU.LY => bus.set(.{ .dbus = self.ppu.ly }),
        PPU.LYC => bus.set(.{ .dbus = self.ppu.lyc }),
        // PPU.DMA => bus.set(.{ .dbus = self.ppu.dma }),
        // PPU.BGP => bus.set(.{ .dbus = self.ppu.bgp }),
        // PPU.OBP0 => bus.set(.{ .dbus = self.ppu.obp0 }),
        // PPU.OBP1 => bus.set(.{ .dbus = self.ppu.obp1 }),
        // PPU.WY => bus.set(.{ .dbus = self.ppu.wy }),
        // PPU.WX => bus.set(.{ .dbus = self.ppu.wx }),
        else => self.read_ram(bus),
    };
}

fn read_if(self: *GB, bus: Pins) Pins {
    if (self.oam_transfer_cycle != 0) return bus;
    return bus.set(.{ .dbus = @as(u8, @bitCast(bus.int)) });
}

fn read_ie(self: *GB, bus: Pins) Pins {
    return bus.set(.{ .dbus = @as(u8, @bitCast(self.sm83.ie)) });
}

fn timer_from_mmio(self: *GB) Timer {
    return .{
        .sysclk_lo = self.memory[Timer.SYSCLK_LO],
        .div = self.memory[Timer.DIV],
        .tima = self.memory[Timer.TIMA],
        .tma = self.memory[Timer.TMA],
        .tac = @bitCast(self.memory[Timer.TAC]),
    };
}

pub fn debug_log(self: *const GB, writer: *std.Io.Writer) !void {
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
    try writer.flush();
}

//! The emulated SM83 chip.
//! Apparently, we don't actually know if SM83 was the actual codename.
//! https://github.com/Gekkio/gb-research/tree/main/sm83-cpu-core

const std = @import("std");
const assert = std.debug.assert;

const SM83 = @This();

cycle: u8 = 0,
registers: Registers = .{},
z: u8 = 0,
w: u8 = 0,
ime: bool = false,
// Since the gameboy delays the EI instruction by a cycle for some reason.
ei_counter: u2 = 0,
ie: IRMask = .{},

// TODO Eventually remove some the fields here, after figuring out which are actually needed.
/// https://iceboy.a-singer.de/doc/dmg_cpu_connections.html
pub const Pins = packed struct(u64) {
    m1: u1 = 0,
    exec_phase: u2 = 0,
    data_phase: u2 = 0,
    write_phase: u2 = 0,
    pch_phase: u1 = 0,
    clk: u2 = 0,
    halt: u1 = 0,
    sys_reset: u1 = 0,
    pwron_reset: u1 = 0,
    stop: u1 = 0,
    clk_ready: u1 = 0,
    nmi: u1 = 0,
    rd: u1 = 0,
    wr: u1 = 0,
    oe: u1 = 0,
    internal_access: u1 = 0,
    shadow_access: u1 = 0,
    shadow_override: u1 = 0,
    mreq: u1 = 0,
    int: IRMask = .{},
    inta: IRMask = .{},
    prefix_cb: u1 = 0,
    dbus: u8 = 0,
    abus: u16 = 0,

    pub fn set(self: Pins, pins: anytype) Pins {
        var result: Pins = self;
        inline for (@typeInfo(@TypeOf(pins)).@"struct".fields) |field| {
            @field(result, field.name) = @field(pins, field.name);
        }
        return result;
    }
};

pub const IRMask = packed struct(u8) {
    vblank: u1 = 0,
    status: u1 = 0,
    timer: u1 = 0,
    serial: u1 = 0,
    joypad: u1 = 0,
    unused: u3 = 0,

    pub fn to_byte(self: IRMask) u8 {
        return @bitCast(self);
    }

    pub fn set(self: IRMask, mask: anytype) Pins {
        var result: IRMask = self;
        inline for (@typeInfo(@TypeOf(mask)).@"struct".fields) |field| {
            @field(result, field.name) = @field(mask, field.name);
        }
        return result;
    }
};

// Cheat a little by using unused instruction opcodes to handle interrupts.
pub const Interrupts = struct {
    pub const vblank = 0o323;
    pub const status = 0o333;
    pub const timer = 0o343;
    pub const serial = 0o353;
    pub const joypad = 0o344;
};

const Registers = struct {
    const Flags = packed struct {
        unused: u4 = 0,
        c: bool = false,
        h: bool = false,
        n: bool = false,
        z: bool = false,
    };

    ir: u8 = 0x00,

    a: u8 = 0x00,
    flags: Flags = @bitCast(@as(u8, 0x00)),

    b: u8 = 0x00,
    c: u8 = 0x00,
    d: u8 = 0x00,
    e: u8 = 0x00,
    h: u8 = 0x00,
    l: u8 = 0x00,

    sp: u16 = 0x0000,
    pc: u16 = 0x0000,

    pub fn hl(self: Registers) u16 {
        return pair(self.h, self.l);
    }
    pub fn bc(self: Registers) u16 {
        return pair(self.b, self.c);
    }
    pub fn de(self: Registers) u16 {
        return pair(self.d, self.e);
    }
    pub fn af(self: Registers) u16 {
        return pair(self.a, @bitCast(self.flags));
    }
    pub fn sethl(self: *Registers, data: u16) void {
        self.h = msb(data);
        self.l = lsb(data);
    }
    pub fn setbc(self: *Registers, data: u16) void {
        self.b = msb(data);
        self.c = lsb(data);
    }
    pub fn setde(self: *Registers, data: u16) void {
        self.d = msb(data);
        self.e = lsb(data);
    }
    pub fn setaf(self: *Registers, data: u16) void {
        self.a = msb(data);
        self.flags = @bitCast(lsb(data) & 0xF0);
    }
};

pub fn tick(cpu: *SM83, input_bus: Pins) Pins {
    var bus = input_bus.set(.{ .m1 = 0, .wr = 0, .rd = 0, .mreq = 0 });

    if (cpu.ei_counter > 0) {
        cpu.ei_counter -= 1;
        if (cpu.ei_counter == 0) {
            cpu.ime = true;
        }
    }

    if (cpu.cycle == 0) {
        bus = cpu.service_interrupts(input_bus);
        cpu.registers.ir = bus.dbus;
    }

    if (bus.halt == 1) {
        return bus;
    }

    const y: u3 = @truncate(cpu.registers.ir >> 3);
    const z: u3 = @truncate(cpu.registers.ir);
    if (bus.prefix_cb == 1) {
        cpu.decode_cb(&bus);
    } else switch (@as(u11, cpu.cycle) << 8 | cpu.registers.ir) {
        // NOP
        inst_state(0x00, 0) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // LD (imm16), SP
        inst_state(0o10, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o10, 1) => {
            cpu.z = bus.dbus;
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o10, 2) => {
            cpu.w = bus.dbus;
            bus = mem_write(bus, cpu.wz(), lsb(cpu.registers.sp));
            cpu.setwz(cpu.wz() +% 1);
            cpu.cycle += 1;
        },
        inst_state(0o10, 3) => {
            bus = mem_write(bus, cpu.wz(), msb(cpu.registers.sp));
            cpu.cycle += 1;
        },
        inst_state(0o10, 4) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // STOP
        inst_state(0x10, 0) => {
            //TODO
            // Is apparently not used in any licensed ROMs, low priority to implement.
            unreachable;
        },

        // zig fmt: off
        // LD r, r'
        inst_state(0o100, 0)...inst_state(0o105, 0), inst_state(0o107, 0),
        inst_state(0o110, 0)...inst_state(0o115, 0), inst_state(0o117, 0),
        inst_state(0o120, 0)...inst_state(0o125, 0), inst_state(0o127, 0),
        inst_state(0o130, 0)...inst_state(0o135, 0), inst_state(0o137, 0),
        inst_state(0o140, 0)...inst_state(0o145, 0), inst_state(0o147, 0),
        inst_state(0o150, 0)...inst_state(0o155, 0), inst_state(0o157, 0),
        inst_state(0o170, 0)...inst_state(0o175, 0), inst_state(0o177, 0),
        => {
            cpu.reg_decode_set(y, cpu.reg_decode_get(z));
            bus = cpu.fetch_and_decode(bus);
        },

        // LD r, (HL)
        inst_state(0o106, 0), inst_state(0o116, 0),
        inst_state(0o126, 0), inst_state(0o136, 0),
        inst_state(0o146, 0), inst_state(0o156, 0),
        inst_state(0o176, 0) => {
            bus = mem_read(bus, cpu.registers.hl());
            cpu.cycle += 1;
        },
        inst_state(0o106, 1), inst_state(0o116, 1),
        inst_state(0o126, 1), inst_state(0o136, 1),
        inst_state(0o146, 1), inst_state(0o156, 1),
        inst_state(0o176, 1) => {
            cpu.reg_decode_set(y, bus.dbus);
            bus = cpu.fetch_and_decode(bus);
        },
        // zig fmt: on

        // LD (HL), r
        inst_state(0o160, 0)...inst_state(0o165, 0), inst_state(0o167, 0) => {
            const reg = cpu.reg_decode_get(z);
            bus = mem_write(bus, cpu.registers.hl(), reg);
            cpu.cycle += 1;
        },
        inst_state(0o160, 1)...inst_state(0o165, 1), inst_state(0o167, 1) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // LD r, imm8
        inst_state(0o06, 0),
        inst_state(0o16, 0),
        inst_state(0o26, 0),
        inst_state(0o36, 0),
        inst_state(0o46, 0),
        inst_state(0o56, 0),
        inst_state(0o76, 0),
        => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o06, 1),
        inst_state(0o16, 1),
        inst_state(0o26, 1),
        inst_state(0o36, 1),
        inst_state(0o46, 1),
        inst_state(0o56, 1),
        inst_state(0o76, 1),
        => {
            cpu.reg_decode_set(y, bus.dbus);
            bus = cpu.fetch_and_decode(bus);
        },

        // LD (HL), imm8
        inst_state(0o66, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o66, 1) => {
            bus = mem_write(bus, cpu.registers.hl(), bus.dbus);
            cpu.cycle += 1;
        },
        inst_state(0o66, 2) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // HALT
        inst_state(0o166, 0) => {
            bus.halt = 1;
            bus = cpu.fetch_and_decode(bus);
        },

        // LD (BC), A
        inst_state(0o02, 0) => {
            bus = mem_write(bus, cpu.registers.bc(), cpu.registers.a);
            cpu.cycle += 1;
        },
        inst_state(0o02, 1) => {
            bus = cpu.fetch_and_decode(bus);
        },
        // LD A, (BC)
        inst_state(0o12, 0) => {
            bus = mem_read(bus, cpu.registers.bc());
            cpu.cycle += 1;
        },
        inst_state(0o12, 1) => {
            cpu.registers.a = bus.dbus;
            bus = cpu.fetch_and_decode(bus);
        },

        // LD (DE), A
        inst_state(0o22, 0) => {
            bus = mem_write(bus, cpu.registers.de(), cpu.registers.a);
            cpu.cycle += 1;
        },
        inst_state(0o22, 1) => {
            bus = cpu.fetch_and_decode(bus);
        },
        // LD A, (DE)
        inst_state(0o32, 0) => {
            bus = mem_read(bus, cpu.registers.de());
            cpu.cycle += 1;
        },
        inst_state(0o32, 1) => {
            cpu.registers.a = bus.dbus;
            bus = cpu.fetch_and_decode(bus);
        },

        // LD (HL+), A
        inst_state(0o42, 0) => {
            const hl = cpu.registers.hl();
            bus = mem_write(bus, hl, cpu.registers.a);
            cpu.registers.sethl(hl +% 1);
            cpu.cycle += 1;
        },
        inst_state(0o42, 1) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // LD A, (HL+)
        inst_state(0o52, 0) => {
            const hl = cpu.registers.hl();
            bus = mem_read(bus, hl);
            cpu.registers.sethl(hl +% 1);
            cpu.cycle += 1;
        },
        inst_state(0o52, 1) => {
            cpu.registers.a = bus.dbus;
            bus = cpu.fetch_and_decode(bus);
        },

        // LD (HL-), A
        inst_state(0o62, 0) => {
            const hl = cpu.registers.hl();
            bus = mem_write(bus, hl, cpu.registers.a);
            cpu.registers.sethl(hl -% 1);
            cpu.cycle += 1;
        },
        inst_state(0o62, 1) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // LD A, (HL-)
        inst_state(0o72, 0) => {
            const hl = cpu.registers.hl();
            bus = mem_read(bus, hl);
            cpu.registers.sethl(hl -% 1);
            cpu.cycle += 1;
        },
        inst_state(0o72, 1) => {
            cpu.registers.a = bus.dbus;
            bus = cpu.fetch_and_decode(bus);
        },

        // zig fmt: off
        // ALU A, r
        inst_state(0o200, 0)...inst_state(0o205, 0), inst_state(0o207, 0),
        inst_state(0o210, 0)...inst_state(0o215, 0), inst_state(0o217, 0),
        inst_state(0o220, 0)...inst_state(0o225, 0), inst_state(0o227, 0),
        inst_state(0o230, 0)...inst_state(0o235, 0), inst_state(0o237, 0),
        inst_state(0o240, 0)...inst_state(0o245, 0), inst_state(0o247, 0),
        inst_state(0o250, 0)...inst_state(0o255, 0), inst_state(0o257, 0),
        inst_state(0o260, 0)...inst_state(0o265, 0), inst_state(0o267, 0),
        inst_state(0o270, 0)...inst_state(0o275, 0), inst_state(0o277, 0),
        => {
            const reg = cpu.reg_decode_get(z);
            cpu.alu_decode(y, reg);
            bus = cpu.fetch_and_decode(bus);
        },
        // zig fmt: on
        // ALU r, (HL)
        inst_state(0o206, 0),
        inst_state(0o216, 0),
        inst_state(0o226, 0),
        inst_state(0o236, 0),
        inst_state(0o246, 0),
        inst_state(0o256, 0),
        inst_state(0o266, 0),
        inst_state(0o276, 0),
        => {
            bus = mem_read(bus, cpu.registers.hl());
            cpu.cycle += 1;
        },
        inst_state(0o206, 1),
        inst_state(0o216, 1),
        inst_state(0o226, 1),
        inst_state(0o236, 1),
        inst_state(0o246, 1),
        inst_state(0o256, 1),
        inst_state(0o266, 1),
        inst_state(0o276, 1),
        => {
            cpu.alu_decode(y, bus.dbus);
            bus = cpu.fetch_and_decode(bus);
        },

        inst_state(0o306, 0),
        inst_state(0o316, 0),
        inst_state(0o326, 0),
        inst_state(0o336, 0),
        inst_state(0o346, 0),
        inst_state(0o356, 0),
        inst_state(0o366, 0),
        inst_state(0o376, 0),
        => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o306, 1),
        inst_state(0o316, 1),
        inst_state(0o326, 1),
        inst_state(0o336, 1),
        inst_state(0o346, 1),
        inst_state(0o356, 1),
        inst_state(0o366, 1),
        inst_state(0o376, 1),
        => {
            cpu.alu_decode(y, bus.dbus);
            bus = cpu.fetch_and_decode(bus);
        },

        // LDH (C), A
        inst_state(0o342, 0) => {
            bus = mem_write(bus, pair(0xFF, cpu.registers.c), cpu.registers.a);
            cpu.cycle += 1;
        },
        inst_state(0o342, 1) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // LD (imm16), A
        inst_state(0o352, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o352, 1) => {
            cpu.z = bus.dbus;
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o352, 2) => {
            cpu.w = bus.dbus;
            bus = mem_write(bus, cpu.wz(), cpu.registers.a);
            cpu.cycle += 1;
        },
        inst_state(0o352, 3) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // LDH A, (C)
        inst_state(0o362, 0) => {
            bus = mem_read(bus, pair(0xFF, cpu.registers.c));
            cpu.cycle += 1;
        },
        inst_state(0o362, 1) => {
            cpu.registers.a = bus.dbus;
            bus = cpu.fetch_and_decode(bus);
        },

        // LD A, (imm16)
        inst_state(0o372, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o372, 1) => {
            cpu.z = bus.dbus;
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o372, 2) => {
            cpu.w = bus.dbus;
            bus = mem_read(bus, cpu.wz());
            cpu.cycle += 1;
        },
        inst_state(0o372, 3) => {
            cpu.registers.a = bus.dbus;
            bus = cpu.fetch_and_decode(bus);
        },

        // LDH (imm8), A
        inst_state(0o340, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o340, 1) => {
            bus = mem_write(bus, pair(0xFF, bus.dbus), cpu.registers.a);
            cpu.cycle += 1;
        },
        inst_state(0o340, 2) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // ADD SP, e
        inst_state(0o350, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o350, 1) => {
            cpu.z = bus.dbus;
            const result, const carry = @addWithOverflow(lsb(cpu.registers.sp), cpu.z);

            cpu.registers.flags = .{
                .z = false,
                .n = false,
                .h = half_carry_add(cpu.z, lsb(cpu.registers.sp)) == 1,
                .c = carry == 1,
            };
            const adj: u8 = if (cpu.z & 0x80 == 0) 0x00 else 0xFF;
            cpu.z = result;
            cpu.w = msb(cpu.registers.sp) +% adj +% @intFromBool(cpu.registers.flags.c);
            cpu.cycle += 1;
        },
        inst_state(0o350, 2) => {
            cpu.cycle += 1;
        },
        inst_state(0o350, 3) => {
            cpu.registers.sp = cpu.wz();
            bus = cpu.fetch_and_decode(bus);
        },

        // LDH A, (imm8)
        inst_state(0o360, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o360, 1) => {
            bus = mem_read(bus, pair(0xFF, bus.dbus));
            cpu.cycle += 1;
        },
        inst_state(0o360, 2) => {
            cpu.registers.a = bus.dbus;
            bus = cpu.fetch_and_decode(bus);
        },

        // LD HL, SP+e
        inst_state(0o370, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o370, 1) => {
            cpu.z = bus.dbus;
            const lsb_sp = lsb(cpu.registers.sp);
            const hc = half_carry_add(lsb_sp, cpu.z);
            _, const carry = @addWithOverflow(lsb_sp, cpu.z);

            cpu.registers.flags.z = false;
            cpu.registers.flags.n = false;
            cpu.registers.flags.h = hc == 1;
            cpu.registers.flags.c = carry == 1;

            cpu.cycle += 1;
        },
        inst_state(0o370, 2) => {
            cpu.registers.sethl(add_signed(cpu.registers.sp, cpu.z));

            bus = cpu.fetch_and_decode(bus);
        },

        // LD SP, HL
        inst_state(0xF9, 0) => {
            cpu.registers.sp = cpu.registers.hl();
            cpu.cycle += 1;
        },
        inst_state(0xF9, 1) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // LD BC, imm16
        inst_state(0x01, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0x01, 1) => {
            cpu.z = bus.dbus;
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0x01, 2) => {
            cpu.w = bus.dbus;
            cpu.registers.setbc(cpu.wz());
            bus = cpu.fetch_and_decode(bus);
        },

        // LD DE, imm16
        inst_state(0x11, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0x11, 1) => {
            cpu.z = bus.dbus;
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0x11, 2) => {
            cpu.w = bus.dbus;
            cpu.registers.setde(cpu.wz());
            bus = cpu.fetch_and_decode(bus);
        },

        // LD HL, imm16
        inst_state(0x21, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0x21, 1) => {
            cpu.z = bus.dbus;
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0x21, 2) => {
            cpu.w = bus.dbus;
            cpu.registers.sethl(cpu.wz());
            bus = cpu.fetch_and_decode(bus);
        },

        // LD SP, imm16
        inst_state(0x31, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0x31, 1) => {
            cpu.z = bus.dbus;
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0x31, 2) => {
            cpu.w = bus.dbus;
            cpu.registers.sp = cpu.wz();
            bus = cpu.fetch_and_decode(bus);
        },

        // ADD HL, rr
        inst_state(0x09, 0),
        inst_state(0x19, 0),
        inst_state(0x29, 0),
        inst_state(0x39, 0),
        => {
            cpu.add_pair_to_hl(@truncate(cpu.registers.ir >> 4));
            cpu.cycle += 1;
        },
        inst_state(0x09, 1),
        inst_state(0x19, 1),
        inst_state(0x29, 1),
        inst_state(0x39, 1),
        => {
            bus = cpu.fetch_and_decode(bus);
        },

        // DEC rr
        inst_state(0x0B, 0),
        inst_state(0x1B, 0),
        inst_state(0x2B, 0),
        inst_state(0x3B, 0),
        => {
            cpu.dec16(@truncate(cpu.registers.ir >> 4));
            cpu.cycle += 1;
        },
        inst_state(0x0B, 1),
        inst_state(0x1B, 1),
        inst_state(0x2B, 1),
        inst_state(0x3B, 1),
        => {
            bus = cpu.fetch_and_decode(bus);
        },

        // INC bc
        inst_state(0x03, 0),
        inst_state(0x13, 0),
        inst_state(0x23, 0),
        inst_state(0x33, 0),
        => {
            cpu.inc16(@truncate(cpu.registers.ir >> 4));
            cpu.cycle += 1;
        },
        inst_state(0x03, 1),
        inst_state(0x13, 1),
        inst_state(0x23, 1),
        inst_state(0x33, 1),
        => {
            bus = cpu.fetch_and_decode(bus);
        },

        // INC r
        inst_state(0o04, 0),
        inst_state(0o14, 0),
        inst_state(0o24, 0),
        inst_state(0o34, 0),
        inst_state(0o44, 0),
        inst_state(0o54, 0),
        inst_state(0o74, 0),
        => {
            var reg = cpu.reg_decode_get(y);
            cpu.inc(&reg);
            cpu.reg_decode_set(y, reg);
            bus = cpu.fetch_and_decode(bus);
        },

        // DEC r
        inst_state(0o05, 0),
        inst_state(0o15, 0),
        inst_state(0o25, 0),
        inst_state(0o35, 0),
        inst_state(0o45, 0),
        inst_state(0o55, 0),
        inst_state(0o75, 0),
        => {
            var reg = cpu.reg_decode_get(y);
            cpu.dec(&reg);
            cpu.reg_decode_set(y, reg);
            bus = cpu.fetch_and_decode(bus);
        },

        // INC (HL)
        inst_state(0o64, 0) => {
            bus = mem_read(bus, cpu.registers.hl());
            cpu.cycle += 1;
        },
        inst_state(0o64, 1) => {
            cpu.z = bus.dbus;
            cpu.inc(&cpu.z);
            bus = mem_write(bus, cpu.registers.hl(), cpu.z);
            cpu.cycle += 1;
        },
        inst_state(0o64, 2) => {
            bus = cpu.fetch_and_decode(bus);
        },
        // DEC (HL)
        inst_state(0o65, 0) => {
            bus = mem_read(bus, cpu.registers.hl());
            cpu.cycle += 1;
        },
        inst_state(0o65, 1) => {
            cpu.z = bus.dbus;
            cpu.dec(&cpu.z);
            bus = mem_write(bus, cpu.registers.hl(), cpu.z);
            cpu.cycle += 1;
        },
        inst_state(0o65, 2) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // CCF
        inst_state(0x3F, 0) => {
            cpu.registers.flags.n = false;
            cpu.registers.flags.h = false;
            cpu.registers.flags.c = !cpu.registers.flags.c;
            bus = cpu.fetch_and_decode(bus);
        },

        // SCF
        inst_state(0x37, 0) => {
            cpu.registers.flags.n = false;
            cpu.registers.flags.h = false;
            cpu.registers.flags.c = true;
            bus = cpu.fetch_and_decode(bus);
        },

        // DAA
        inst_state(0x27, 0) => {
            var offset: u8 = 0;

            const subtract = cpu.registers.flags.n;

            if ((!subtract and cpu.registers.a & 0xF > 0x09) or cpu.registers.flags.h) {
                offset += 0x06;
            }
            if ((!subtract and cpu.registers.a > 0x99) or cpu.registers.flags.c) {
                offset += 0x60;
                cpu.registers.flags.c = true;
            }

            if (subtract) {
                cpu.registers.a -%= offset;
            } else {
                cpu.registers.a +%= offset;
            }

            cpu.registers.flags.z = cpu.registers.a == 0;
            cpu.registers.flags.h = false;

            bus = cpu.fetch_and_decode(bus);
        },

        // CPL
        inst_state(0x2F, 0) => {
            cpu.registers.a = ~cpu.registers.a;
            cpu.registers.flags.n = true;
            cpu.registers.flags.h = true;
            bus = cpu.fetch_and_decode(bus);
        },

        // RLCA
        inst_state(0x07, 0) => {
            cpu.registers.a = cpu.rlc(cpu.registers.a);
            cpu.registers.flags.z = false;
            bus = cpu.fetch_and_decode(bus);
        },

        // RRCA
        inst_state(0x0F, 0) => {
            cpu.registers.a = cpu.rrc(cpu.registers.a);
            cpu.registers.flags.z = false;
            bus = cpu.fetch_and_decode(bus);
        },

        // RLA
        inst_state(0x17, 0) => {
            cpu.registers.a = cpu.rl(cpu.registers.a);
            cpu.registers.flags.z = false;
            bus = cpu.fetch_and_decode(bus);
        },

        // RRA
        inst_state(0x1F, 0) => {
            cpu.registers.a = cpu.rr(cpu.registers.a);
            cpu.registers.flags.z = false;
            bus = cpu.fetch_and_decode(bus);
        },

        // PUSH rr
        inst_state(0xC5, 0),
        inst_state(0xD5, 0),
        inst_state(0xE5, 0),
        inst_state(0xF5, 0),
        => {
            cpu.registers.sp -%= 1;
            cpu.cycle += 1;
        },
        inst_state(0xC5, 1),
        inst_state(0xD5, 1),
        inst_state(0xE5, 1),
        inst_state(0xF5, 1),
        => {
            cpu.setwz(cpu.reg_decode2(@truncate(cpu.registers.ir >> 4)));
            bus = mem_write(bus, cpu.registers.sp, cpu.w);
            cpu.registers.sp -%= 1;
            cpu.cycle += 1;
        },
        inst_state(0xC5, 2),
        inst_state(0xD5, 2),
        inst_state(0xE5, 2),
        inst_state(0xF5, 2),
        => {
            bus = mem_write(bus, cpu.registers.sp, cpu.z);
            cpu.cycle += 1;
        },
        inst_state(0xC5, 3),
        inst_state(0xD5, 3),
        inst_state(0xE5, 3),
        inst_state(0xF5, 3),
        => {
            bus = cpu.fetch_and_decode(bus);
        },

        // POP rr
        inst_state(0xC1, 0),
        inst_state(0xD1, 0),
        inst_state(0xE1, 0),
        inst_state(0xF1, 0),
        => {
            bus = mem_read(bus, cpu.registers.sp);
            cpu.registers.sp +%= 1;
            cpu.cycle += 1;
        },
        inst_state(0xC1, 1),
        inst_state(0xD1, 1),
        inst_state(0xE1, 1),
        inst_state(0xF1, 1),
        => {
            cpu.z = bus.dbus;
            bus = mem_read(bus, cpu.registers.sp);
            cpu.registers.sp +%= 1;
            cpu.cycle += 1;
        },
        inst_state(0xC1, 2),
        inst_state(0xD1, 2),
        inst_state(0xE1, 2),
        inst_state(0xF1, 2),
        => {
            cpu.w = bus.dbus;
            cpu.set_reg_decode2(@truncate(cpu.registers.ir >> 4), cpu.wz());
            bus = cpu.fetch_and_decode(bus);
        },

        // JP imm16
        inst_state(0xC3, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0xC3, 1) => {
            cpu.z = bus.dbus;
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0xC3, 2) => {
            cpu.w = bus.dbus;
            cpu.registers.pc = cpu.wz();
            cpu.cycle += 1;
        },
        inst_state(0xC3, 3) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // JP HL
        inst_state(0xE9, 0) => {
            cpu.registers.pc = cpu.registers.hl();
            bus = cpu.fetch_and_decode(bus);
        },

        // JP cond, imm16
        inst_state(0o302, 0),
        inst_state(0o312, 0),
        inst_state(0o322, 0),
        inst_state(0o332, 0),
        => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o302, 1),
        inst_state(0o312, 1),
        inst_state(0o322, 1),
        inst_state(0o332, 1),
        => {
            cpu.z = bus.dbus;
            bus = cpu.fetch_pc(bus);
            const cond: Cond = @enumFromInt(@as(u2, @truncate(y)));
            if (!cpu.get_cond(cond)) {
                cpu.cycle += 1;
            }
            cpu.cycle += 1;
        },
        inst_state(0o302, 2),
        inst_state(0o312, 2),
        inst_state(0o322, 2),
        inst_state(0o332, 2),
        => {
            cpu.w = bus.dbus;
            cpu.registers.pc = cpu.wz();
            cpu.cycle += 1;
        },
        inst_state(0o302, 3),
        inst_state(0o312, 3),
        inst_state(0o322, 3),
        inst_state(0o332, 3),
        => {
            bus = cpu.fetch_and_decode(bus);
        },

        // JP e
        inst_state(0o30, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o30, 1) => {
            cpu.registers.pc = add_signed(cpu.registers.pc, bus.dbus);
            cpu.cycle += 1;
        },
        inst_state(0o30, 2) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // JP cond, e
        inst_state(0o40, 0),
        inst_state(0o50, 0),
        inst_state(0o60, 0),
        inst_state(0o70, 0),
        => {
            bus = cpu.fetch_pc(bus);

            const cond: Cond = @enumFromInt(@as(u2, @truncate(y)));
            if (!cpu.get_cond(cond)) {
                cpu.cycle += 1;
            }
            cpu.cycle += 1;
        },
        inst_state(0o40, 1),
        inst_state(0o50, 1),
        inst_state(0o60, 1),
        inst_state(0o70, 1),
        => {
            cpu.z = bus.dbus;
            cpu.registers.pc = add_signed(cpu.registers.pc, cpu.z);
            cpu.cycle += 1;
        },
        inst_state(0o40, 2),
        inst_state(0o50, 2),
        inst_state(0o60, 2),
        inst_state(0o70, 2),
        => {
            bus = cpu.fetch_and_decode(bus);
        },

        // CALL imm16
        inst_state(0o315, 0),
        => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o315, 1),
        => {
            cpu.z = bus.dbus;
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o315, 2),
        => {
            cpu.w = bus.dbus;
            cpu.registers.sp -%= 1;
            cpu.cycle += 1;
        },
        inst_state(0o315, 3),
        => {
            bus = mem_write(bus, cpu.registers.sp, msb(cpu.registers.pc));
            cpu.registers.sp -%= 1;
            cpu.cycle += 1;
        },
        inst_state(0o315, 4),
        => {
            bus = mem_write(bus, cpu.registers.sp, lsb(cpu.registers.pc));
            cpu.registers.pc = cpu.wz();
            cpu.cycle += 1;
        },
        inst_state(0o315, 5),
        => {
            bus = cpu.fetch_and_decode(bus);
        },

        // CALL cond, imm16
        inst_state(0o304, 0),
        inst_state(0o314, 0),
        inst_state(0o324, 0),
        inst_state(0o334, 0),
        => {
            bus = cpu.fetch_pc(bus);
            cpu.cycle += 1;
        },
        inst_state(0o304, 1),
        inst_state(0o314, 1),
        inst_state(0o324, 1),
        inst_state(0o334, 1),
        => {
            cpu.z = bus.dbus;
            bus = cpu.fetch_pc(bus);
            const cond: Cond = @enumFromInt(@as(u2, @truncate(y)));
            if (!cpu.get_cond(cond)) {
                cpu.cycle += 3;
            }
            cpu.cycle += 1;
        },
        inst_state(0o304, 2),
        inst_state(0o314, 2),
        inst_state(0o324, 2),
        inst_state(0o334, 2),
        => {
            cpu.w = bus.dbus;
            cpu.registers.sp -%= 1;
            cpu.cycle += 1;
        },
        inst_state(0o304, 3),
        inst_state(0o314, 3),
        inst_state(0o324, 3),
        inst_state(0o334, 3),
        => {
            bus = mem_write(bus, cpu.registers.sp, msb(cpu.registers.pc));
            cpu.registers.sp -%= 1;
            cpu.cycle += 1;
        },
        inst_state(0o304, 4),
        inst_state(0o314, 4),
        inst_state(0o324, 4),
        inst_state(0o334, 4),
        => {
            bus = mem_write(bus, cpu.registers.sp, lsb(cpu.registers.pc));
            cpu.registers.pc = cpu.wz();
            cpu.cycle += 1;
        },
        inst_state(0o304, 5),
        inst_state(0o314, 5),
        inst_state(0o324, 5),
        inst_state(0o334, 5),
        => {
            bus = cpu.fetch_and_decode(bus);
        },

        // RET
        inst_state(0xC9, 0) => {
            bus = mem_read(bus, cpu.registers.sp);
            cpu.registers.sp +%= 1;
            cpu.cycle += 1;
        },
        inst_state(0xC9, 1) => {
            cpu.z = bus.dbus;
            bus = mem_read(bus, cpu.registers.sp);
            cpu.registers.sp +%= 1;
            cpu.cycle += 1;
        },
        inst_state(0xC9, 2) => {
            cpu.w = bus.dbus;
            cpu.registers.pc = cpu.wz();
            cpu.cycle += 1;
        },
        inst_state(0xC9, 3) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // RET cond
        inst_state(0o300, 0),
        inst_state(0o310, 0),
        inst_state(0o320, 0),
        inst_state(0o330, 0),
        => {
            const cond: Cond = @enumFromInt(@as(u2, @truncate(y)));
            if (!cpu.get_cond(cond)) {
                cpu.cycle += 4;
            } else {
                cpu.cycle += 1;
            }
        },
        inst_state(0o300, 1),
        inst_state(0o310, 1),
        inst_state(0o320, 1),
        inst_state(0o330, 1),
        => {
            bus = mem_read(bus, cpu.registers.sp);
            cpu.registers.sp +%= 1;
            cpu.cycle += 1;
        },
        inst_state(0o300, 2),
        inst_state(0o310, 2),
        inst_state(0o320, 2),
        inst_state(0o330, 2),
        => {
            cpu.z = bus.dbus;
            bus = mem_read(bus, cpu.registers.sp);
            cpu.registers.sp +%= 1;
            cpu.cycle += 1;
        },
        inst_state(0o300, 3),
        inst_state(0o310, 3),
        inst_state(0o320, 3),
        inst_state(0o330, 3),
        => {
            cpu.w = bus.dbus;
            cpu.registers.pc = cpu.wz();
            cpu.cycle += 1;
        },
        inst_state(0o300, 4),
        inst_state(0o310, 4),
        inst_state(0o320, 4),
        inst_state(0o330, 4),
        => {
            bus = cpu.fetch_and_decode(bus);
        },

        // RETI
        inst_state(0xD9, 0) => {
            bus = mem_read(bus, cpu.registers.sp);
            cpu.registers.sp +%= 1;
            cpu.cycle += 1;
        },
        inst_state(0xD9, 1) => {
            cpu.z = bus.dbus;
            bus = mem_read(bus, cpu.registers.sp);
            cpu.registers.sp +%= 1;
            cpu.cycle += 1;
        },
        inst_state(0xD9, 2) => {
            cpu.w = bus.dbus;
            cpu.registers.pc = cpu.wz();
            cpu.ime = true;
            cpu.cycle += 1;
        },
        inst_state(0xD9, 3) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // RST
        inst_state(0o307, 0),
        inst_state(0o317, 0),
        inst_state(0o327, 0),
        inst_state(0o337, 0),
        inst_state(0o347, 0),
        inst_state(0o357, 0),
        inst_state(0o367, 0),
        inst_state(0o377, 0),
        => {
            cpu.registers.sp -%= 1;
            cpu.cycle += 1;
        },
        inst_state(0o307, 1),
        inst_state(0o317, 1),
        inst_state(0o327, 1),
        inst_state(0o337, 1),
        inst_state(0o347, 1),
        inst_state(0o357, 1),
        inst_state(0o367, 1),
        inst_state(0o377, 1),
        => {
            bus = mem_write(bus, cpu.registers.sp, msb(cpu.registers.pc));
            cpu.registers.sp -%= 1;
            cpu.cycle += 1;
        },
        inst_state(0o307, 2),
        inst_state(0o317, 2),
        inst_state(0o327, 2),
        inst_state(0o337, 2),
        inst_state(0o347, 2),
        inst_state(0o357, 2),
        inst_state(0o367, 2),
        inst_state(0o377, 2),
        => {
            bus = mem_write(bus, cpu.registers.sp, lsb(cpu.registers.pc));
            cpu.registers.pc = @as(u8, y) * 8;
            cpu.cycle += 1;
        },
        inst_state(0o307, 3),
        inst_state(0o317, 3),
        inst_state(0o327, 3),
        inst_state(0o337, 3),
        inst_state(0o347, 3),
        inst_state(0o357, 3),
        inst_state(0o367, 3),
        inst_state(0o377, 3),
        => {
            bus = cpu.fetch_and_decode(bus);
        },

        // EI
        inst_state(0xFB, 0) => {
            cpu.ei_counter = 2;
            bus = cpu.fetch_and_decode(bus);
        },

        // DI
        inst_state(0xF3, 0) => {
            cpu.ime = false;
            bus = cpu.fetch_and_decode(bus);
        },

        inst_state(0xCB, 0) => {
            bus = cpu.fetch_and_decode_extended(bus);
        },

        // TODO not sure how accurate this is
        // NOP before ISR https://gist.github.com/SonoSooS/c0055300670d678b5ae8433e20bea595#halt
        inst_state(Interrupts.vblank, 0),
        inst_state(Interrupts.status, 0),
        inst_state(Interrupts.timer, 0),
        inst_state(Interrupts.serial, 0),
        inst_state(Interrupts.joypad, 0),
        => {
            cpu.registers.pc -= 1;
            cpu.cycle += 1;
        },
        inst_state(Interrupts.vblank, 1),
        inst_state(Interrupts.status, 1),
        inst_state(Interrupts.timer, 1),
        inst_state(Interrupts.serial, 1),
        inst_state(Interrupts.joypad, 1),
        => {
            cpu.registers.sp -%= 1;
            cpu.cycle += 1;
        },
        inst_state(Interrupts.vblank, 2),
        inst_state(Interrupts.status, 2),
        inst_state(Interrupts.timer, 2),
        inst_state(Interrupts.serial, 2),
        inst_state(Interrupts.joypad, 2),
        => {
            bus = mem_write(bus, cpu.registers.sp, msb(cpu.registers.pc));
            cpu.registers.sp -%= 1;
            cpu.cycle += 1;
        },
        inline inst_state(Interrupts.vblank, 3),
        inst_state(Interrupts.status, 3),
        inst_state(Interrupts.timer, 3),
        inst_state(Interrupts.serial, 3),
        inst_state(Interrupts.joypad, 3),
        => |interrupt| {
            const irq_addr: u16 = comptime switch (interrupt & 0xFF) {
                Interrupts.vblank => 0x0040,
                Interrupts.status => 0x0048,
                Interrupts.timer => 0x0050,
                Interrupts.serial => 0x0058,
                Interrupts.joypad => 0x0060,
                else => unreachable,
            };

            bus = mem_write(bus, cpu.registers.sp, lsb(cpu.registers.pc));
            cpu.registers.pc = irq_addr;
            cpu.cycle += 1;
        },
        inst_state(Interrupts.vblank, 4),
        inst_state(Interrupts.status, 4),
        inst_state(Interrupts.timer, 4),
        inst_state(Interrupts.serial, 4),
        inst_state(Interrupts.joypad, 4),
        => {
            bus = cpu.fetch_and_decode(bus);
        },

        else => unreachable,
    }

    return bus;
}

fn decode_cb(cpu: *SM83, bus: *Pins) void {
    const op: u5 = @truncate(cpu.registers.ir >> 3);
    const reg_idx: u3 = @truncate(cpu.registers.ir);

    const x: u2 = @truncate(op >> 3);
    const y: u3 = @truncate(op);

    if (reg_idx == 6) {
        // Bit instructions are one cycle faster than other CB-instrutions, so
        // we give them special treatment
        if (x == 1) {
            switch (cpu.cycle) {
                0 => {
                    bus.* = mem_read(bus.*, cpu.registers.hl());
                    cpu.cycle += 1;
                },
                1 => {
                    cpu.bit(bus.dbus, y);
                    bus.* = cpu.fetch_and_decode(bus.*);
                },
                else => unreachable,
            }
        } else switch (cpu.cycle) {
            0 => {
                bus.* = mem_read(bus.*, cpu.registers.hl());
                cpu.cycle += 1;
            },
            1 => {
                const result = cpu.apply_cb_op(op, bus.dbus);
                bus.* = mem_write(bus.*, cpu.registers.hl(), result);
                cpu.cycle += 1;
            },
            2 => {
                bus.* = cpu.fetch_and_decode(bus.*);
            },
            else => unreachable,
        }
    } else {
        const reg = cpu.reg_decode_get(reg_idx);
        const updated_reg = cpu.apply_cb_op(op, reg);
        cpu.reg_decode_set(reg_idx, updated_reg);
        bus.* = cpu.fetch_and_decode(bus.*);
    }
}

fn apply_cb_op(cpu: *SM83, op: u5, reg: u8) u8 {
    return switch (op) {
        0 => cpu.rlc(reg),
        1 => cpu.rrc(reg),
        2 => cpu.rl(reg),
        3 => cpu.rr(reg),
        4 => cpu.sla(reg),
        5 => cpu.sra(reg),
        6 => cpu.swap(reg),
        7 => cpu.srl(reg),
        8...15 => blk: {
            cpu.bit(reg, @truncate(op - 8));
            break :blk reg;
        },
        16...23 => cpu.res(reg, @truncate(op - 16)),
        24...31 => cpu.set(reg, @truncate(op - 24)),
    };
}

fn reg_decode_get(cpu: *SM83, reg_idx: u3) u8 {
    return switch (reg_idx) {
        0b000 => cpu.registers.b,
        0b001 => cpu.registers.c,
        0b010 => cpu.registers.d,
        0b011 => cpu.registers.e,
        0b100 => cpu.registers.h,
        0b101 => cpu.registers.l,
        0b110 => unreachable,
        0b111 => cpu.registers.a,
    };
}

fn reg_decode_set(cpu: *SM83, reg_idx: u3, data: u8) void {
    switch (reg_idx) {
        0b000 => cpu.registers.b = data,
        0b001 => cpu.registers.c = data,
        0b010 => cpu.registers.d = data,
        0b011 => cpu.registers.e = data,
        0b100 => cpu.registers.h = data,
        0b101 => cpu.registers.l = data,
        0b110 => unreachable,
        0b111 => cpu.registers.a = data,
    }
}

fn reg_decode2(cpu: SM83, reg_idx: u2) u16 {
    return switch (reg_idx) {
        0b00 => cpu.registers.bc(),
        0b01 => cpu.registers.de(),
        0b10 => cpu.registers.hl(),
        0b11 => cpu.registers.af(),
    };
}

fn set_reg_decode2(cpu: *SM83, reg_idx: u2, data: u16) void {
    switch (reg_idx) {
        0b00 => cpu.registers.setbc(data),
        0b01 => cpu.registers.setde(data),
        0b10 => cpu.registers.sethl(data),
        0b11 => cpu.registers.setaf(data),
    }
}

const Cond = enum { NZ, Z, NC, C };

fn get_cond(cpu: SM83, cond_idx: Cond) bool {
    return switch (cond_idx) {
        .NZ => !cpu.registers.flags.z,
        .Z => cpu.registers.flags.z,
        .NC => !cpu.registers.flags.c,
        .C => cpu.registers.flags.c,
    };
}

fn alu_decode(cpu: *SM83, alu_op: u3, reg: u8) void {
    switch (alu_op) {
        0 => cpu.add(reg),
        1 => cpu.adc(reg),
        2 => cpu.sub(reg),
        3 => cpu.sbc(reg),
        4 => cpu.@"and"(reg),
        5 => cpu.xor(reg),
        6 => cpu.@"or"(reg),
        7 => cpu.cp(reg),
    }
}

fn pair(ms: u8, ls: u8) u16 {
    const extended: u16 = ms;
    return extended << 8 | ls;
}

fn wz(cpu: *const SM83) u16 {
    return pair(cpu.w, cpu.z);
}
fn setwz(cpu: *SM83, data: u16) void {
    cpu.w = msb(data);
    cpu.z = lsb(data);
}

fn half_carry_add(reg: u8, num: u8) u1 {
    return @intFromBool((num & 0xF) + (reg & 0xF) > 0xF);
}

fn half_carry_sub(reg: u8, num: u8) u1 {
    return @intFromBool(reg & 0xF < num & 0xF);
}

fn add_signed(dreg: u16, e: u8) u16 {
    const signed_e: i8 = @bitCast(e);
    const sign_extended: u16 = @bitCast(@as(i16, signed_e));
    return dreg +% sign_extended;
}

fn mem_read(bus: Pins, addr: u16) Pins {
    return bus.set(.{
        .abus = addr,
        .rd = 1,
        .mreq = 1,
    });
}

fn mem_write(bus: Pins, addr: u16, data: u8) Pins {
    return bus.set(.{
        .abus = addr,
        .dbus = data,
        .wr = 1,
        .mreq = 1,
    });
}

/// Fetches the next instruction opcode, and resets the cycle counter.
fn fetch_and_decode(cpu: *SM83, bus: Pins) Pins {
    cpu.cycle = 0;
    defer cpu.registers.pc +%= 1;
    return bus.set(.{
        .abus = cpu.registers.pc,
        .mreq = 1,
        .rd = 1,
        .m1 = 1,
        .prefix_cb = 0,
    });
}

// TODO Halt bug
fn service_interrupts(cpu: *SM83, input_bus: Pins) Pins {
    var bus = input_bus;
    if (bus.int.to_byte() & cpu.ie.to_byte() & 0x1F != 0) {
        bus.halt = 0;
    }
    if (cpu.ime) {
        inline for (@typeInfo(IRMask).@"struct".fields) |struct_field| {
            const name = struct_field.name;
            if (comptime std.mem.eql(u8, name, "unused")) continue;
            const if_field = @field(bus.int, name);
            const ie_field = @field(cpu.ie, name);
            if (if_field & ie_field == 1) {
                const interrupt = @field(Interrupts, name);
                @field(bus.int, name) = 0;
                cpu.ime = false;
                return bus.set(.{
                    .dbus = interrupt,
                    .mreq = 0,
                    .wr = 0,
                    .rd = 0,
                    .m1 = 0,
                    .prefix_cb = 0,
                });
            }
        }
    }
    return bus;
}

fn fetch_and_decode_extended(cpu: *SM83, bus: Pins) Pins {
    cpu.cycle = 0;
    defer cpu.registers.pc +%= 1;
    return bus.set(.{
        .abus = cpu.registers.pc,
        .mreq = 1,
        .rd = 1,
        .m1 = 1,
        .prefix_cb = 1,
    });
}

fn fetch_pc(cpu: *SM83, bus: Pins) Pins {
    defer cpu.registers.pc += 1;
    return mem_read(bus, cpu.registers.pc);
}

fn add(cpu: *SM83, operand: u8) void {
    const a = cpu.registers.a;
    const result, const carry = @addWithOverflow(a, operand);
    cpu.registers.a = result;
    cpu.registers.flags = .{
        .z = result == 0,
        .n = false,
        .h = (a & 0x0F) + (operand & 0x0F) > 0x0F,
        .c = carry == 1,
    };
}

fn adc(cpu: *SM83, operand: u8) void {
    const a: u16 = cpu.registers.a;
    const carry = @intFromBool(cpu.registers.flags.c);
    const result: u16 = a +% operand +% carry;
    cpu.registers.a = @truncate(result);
    cpu.registers.flags = .{
        .z = cpu.registers.a == 0,
        .n = false,
        .h = (a & 0x0F) + (operand & 0x0F) + carry > 0x0F,
        .c = result > 0xFF,
    };
}

fn sub(cpu: *SM83, operand: u8) void {
    const a = cpu.registers.a;
    const result = a -% operand;
    cpu.registers.a = result;
    cpu.registers.flags = .{
        .z = result == 0,
        .n = true,
        .h = (a & 0x0F) < (operand & 0x0F),
        .c = a < operand,
    };
}

fn sbc(cpu: *SM83, operand: u8) void {
    const a: u16 = cpu.registers.a;
    const carry = @intFromBool(cpu.registers.flags.c);
    const result = a -% operand -% carry;
    cpu.registers.a = @truncate(result);
    cpu.registers.flags = .{
        .z = cpu.registers.a == 0,
        .n = true,
        .h = (a & 0x0F) < (operand & 0x0F) + carry,
        .c = a < @as(u16, operand) + carry,
    };
}

fn cp(cpu: *SM83, comparand: u8) void {
    const a = cpu.registers.a;
    const result = a -% comparand;
    cpu.registers.flags = .{
        .z = result == 0,
        .n = true,
        .h = (a & 0x0F) < (comparand & 0x0F),
        .c = a < comparand,
    };
}

fn @"and"(cpu: *SM83, operand: u8) void {
    cpu.registers.a &= operand;
    cpu.registers.flags = .{
        .z = cpu.registers.a == 0,
        .n = false,
        .h = true,
        .c = false,
    };
}

fn @"or"(cpu: *SM83, operand: u8) void {
    cpu.registers.a |= operand;
    cpu.registers.flags = .{
        .z = cpu.registers.a == 0,
        .n = false,
        .h = false,
        .c = false,
    };
}

fn xor(cpu: *SM83, operand: u8) void {
    cpu.registers.a ^= operand;
    cpu.registers.flags = .{
        .z = cpu.registers.a == 0,
        .n = false,
        .h = false,
        .c = false,
    };
}

fn inc(cpu: *SM83, reg: *u8) void {
    const hc = half_carry_add(reg.*, 1);
    reg.* +%= 1;
    cpu.registers.flags.z = reg.* == 0;
    cpu.registers.flags.n = false;
    cpu.registers.flags.h = hc == 1;
}

fn dec(cpu: *SM83, reg: *u8) void {
    const hc = half_carry_sub(reg.*, 1);
    reg.* -%= 1;
    cpu.registers.flags.z = reg.* == 0;
    cpu.registers.flags.n = true;
    cpu.registers.flags.h = hc == 1;
}

fn rlc(cpu: *SM83, reg: u8) u8 {
    var result, const carry = @shlWithOverflow(reg, 1);
    result |= carry;
    cpu.registers.flags = .{
        .z = result == 0,
        .n = false,
        .h = false,
        .c = carry == 1,
    };
    return result;
}

fn rrc(cpu: *SM83, reg: u8) u8 {
    const carry: u8 = reg & 1;
    const result = (reg >> 1) | (carry << 7);
    cpu.registers.flags = .{
        .z = result == 0,
        .n = false,
        .h = false,
        .c = carry == 1,
    };
    return result;
}

fn rl(cpu: *SM83, reg: u8) u8 {
    var result, const carry = @shlWithOverflow(reg, 1);
    result |= @intFromBool(cpu.registers.flags.c);
    cpu.registers.flags = .{
        .z = result == 0,
        .n = false,
        .h = false,
        .c = carry == 1,
    };
    return result;
}

fn rr(cpu: *SM83, reg: u8) u8 {
    const carry: u8 = reg & 1;
    const old_carry: u8 = @intFromBool(cpu.registers.flags.c);
    const result = (reg >> 1) | (old_carry << 7);
    cpu.registers.flags = .{
        .z = result == 0,
        .n = false,
        .h = false,
        .c = carry == 1,
    };
    return result;
}

fn bit(cpu: *SM83, r: u8, idx: u3) void {
    cpu.registers.flags.z = (r >> idx) & 1 == 0;
    cpu.registers.flags.n = false;
    cpu.registers.flags.h = true;
}

fn res(_: *SM83, r: u8, idx: u3) u8 {
    return r & ~(@as(u8, 1) << idx);
}

fn set(_: *SM83, r: u8, idx: u3) u8 {
    return r | (@as(u8, 1)) << idx;
}

fn sla(cpu: *SM83, r: u8) u8 {
    const result, const carry = @shlWithOverflow(r, 1);
    cpu.registers.flags = .{
        .z = result == 0,
        .n = false,
        .h = false,
        .c = carry == 1,
    };
    return result;
}

fn sra(cpu: *SM83, r: u8) u8 {
    const signed_r: i8 = @bitCast(r);
    const carry = r & 1;
    const result: u8 = @bitCast(signed_r >> 1);
    cpu.registers.flags = .{
        .z = result == 0,
        .n = false,
        .h = false,
        .c = carry == 1,
    };
    return result;
}

fn swap(cpu: *SM83, r: u8) u8 {
    const ls_nibble: u8 = r & 0x0F;
    const ms_nibble: u8 = r & 0xF0;
    const result = (ms_nibble >> 4) | (ls_nibble << 4);
    cpu.registers.flags = .{
        .z = result == 0,
        .n = false,
        .h = false,
        .c = false,
    };
    return result;
}

fn srl(cpu: *SM83, r: u8) u8 {
    const carry = r & 1;
    const result = r >> 1;
    cpu.registers.flags = .{
        .z = result == 0,
        .n = false,
        .h = false,
        .c = carry == 1,
    };
    return result;
}

fn inc16(cpu: *SM83, reg_pair_idx: u2) void {
    switch (reg_pair_idx) {
        0 => {
            cpu.registers.setbc(cpu.registers.bc() +% 1);
        },
        1 => {
            cpu.registers.setde(cpu.registers.de() +% 1);
        },
        2 => {
            cpu.registers.sethl(cpu.registers.hl() +% 1);
        },
        3 => {
            cpu.registers.sp +%= 1;
        },
    }
}

fn dec16(cpu: *SM83, reg_pair_idx: u2) void {
    switch (reg_pair_idx) {
        0 => cpu.registers.setbc(cpu.registers.bc() -% 1),
        1 => cpu.registers.setde(cpu.registers.de() -% 1),
        2 => cpu.registers.sethl(cpu.registers.hl() -% 1),
        3 => cpu.registers.sp -%= 1,
    }
}

fn add_pair_to_hl(cpu: *SM83, reg_pair_idx: u2) void {
    const reg = switch (reg_pair_idx) {
        0 => cpu.registers.bc(),
        1 => cpu.registers.de(),
        2 => cpu.registers.hl(),
        3 => cpu.registers.sp,
    };
    const hl = cpu.registers.hl();
    const result, const carry = @addWithOverflow(reg, hl);
    cpu.registers.sethl(result);

    cpu.registers.flags.n = false;
    cpu.registers.flags.h = (reg & 0x0FFF) +% (hl & 0x0FFF) > 0x0FFF;
    cpu.registers.flags.c = carry == 1;
}

fn inst_state(comptime inst: u8, comptime cycle: u3) u11 {
    return @as(u11, cycle) << 8 | inst;
}

fn msb(data: u16) u8 {
    return @truncate(data >> 8);
}
fn lsb(data: u16) u8 {
    return @truncate(data);
}

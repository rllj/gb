//! The emulated SM83 chip.
//! Apparently, we don't actually know if SM83 was the actual codename.
//! https://github.com/Gekkio/gb-research/tree/main/sm83-cpu-core

const assert = @import("std").debug.assert;

const SM83 = @This();

state: State,
registers: Registers,
z: u8 = 0,
w: u8 = 0,
ime: bool = false,
// Since the gameboy delays the IE instruction by a cycle for some reason.
should_set_ime: bool = false,

const Bus = u64;

/// https://iceboy.a-singer.de/doc/dmg_cpu_connections.html
const Pins = packed struct(u64) {
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
    int: u8 = 0,
    inta: u8 = 0,
    prefix_cb: u1 = 0,
    dbus: u8 = 0,
    abus: u16 = 0,

    pub fn set(self: Pins, comptime pins: Pins) Pins {
        var result: Pins = self;
        inline for (@typeInfo(Pins).@"struct".fields) |field| {
            @field(result, field.name) = @field(pins, field);
        }
    }
};

const Registers = packed struct {
    const Flags = packed struct {
        unused: u4 = 0,
        c: bool,
        h: bool,
        n: bool,
        z: bool,
    };

    ir: u8,

    a: u8 = 0x01,
    flags: Flags = @bitCast(@as(u8, 0xB0)),

    b: u8 = 0x00,
    c: u8 = 0x13,
    d: u8 = 0x00,
    e: u8 = 0xD8,
    h: u8 = 0x01,
    l: u8 = 0x4D,

    sp: u16 = 0xFFFE,
    pc: u16 = 0x0100,

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

const State = struct { opcode: u8, cycle: u8, is_cb_inst: bool };

const IF = 0xFF0F;
const IE = 0xFFFF;

pub fn tick(cpu: *SM83, input_bus: Pins) Pins {
    var bus = input_bus;
    _ = &bus;
    if (cpu.should_set_ime) {
        cpu.ime = true;
        cpu.should_set_ime = false;
    }

    const x: u2 = @truncate(cpu.state.opcode >> 6);
    _ = x;
    const y: u3 = @truncate(cpu.state.opcode >> 3);
    const z: u3 = @truncate(cpu.state.opcode);
    if (cpu.state.is_cb_inst) {
        cpu.decode_cb(&bus);
    } else switch (@as(u11, cpu.state.cycle) << 8 | cpu.state.opcode) {
        // NOP
        inst_state(0x00, 0) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // LD (imm16), SP
        inst_state(0o10, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.state.cycle += 1;
        },
        inst_state(0o10, 1) => {
            cpu.z = bus.dbus;
            bus = cpu.fetch_pc(bus);
            cpu.state.cycle += 1;
        },
        inst_state(0o10, 2) => {
            cpu.w = bus.dbus;
            bus = mem_write(bus, cpu.wz(), lsb(cpu.registers.sp));
            cpu.setwz(cpu.wz() +% 1);
            cpu.state.cycle += 1;
        },
        inst_state(0o10, 3) => {
            bus = mem_write(bus, cpu.wz(), msb(cpu.registers.sp));
            cpu.state.cycle += 1;
        },
        inst_state(0o10, 4) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // STOP
        inst_state(0x10, 0) => {
            //TODO
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
            assert(cpu.state.cycle == 0);
            cpu.reg_decode(y).* = cpu.reg_decode(z).*;
            bus = cpu.fetch_and_decode(bus);
        },

        // LD r, (HL)
        inst_state(0o106, 0), inst_state(0o116, 0),
        inst_state(0o126, 0), inst_state(0o136, 0),
        inst_state(0o146, 0), inst_state(0o156, 0),
        inst_state(0o176, 0) => {
            bus = mem_read(bus, cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0o106, 1), inst_state(0o116, 1),
        inst_state(0o126, 1), inst_state(0o136, 1),
        inst_state(0o146, 1), inst_state(0o156, 1),
        inst_state(0o176, 1) => {
            const reg = cpu.reg_decode(y);
            reg.* = bus.dbus;
            bus = cpu.fetch_and_decode(bus);
        },
        // zig fmt: on

        // LD (HL), r
        inst_state(0o160, 0)...inst_state(0o165, 0), inst_state(0o167, 0) => {
            const reg = cpu.reg_decode(z).*;
            bus = mem_write(bus, cpu.registers.hl(), reg);
            cpu.state.cycle += 1;
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
            cpu.state.cycle += 1;
        },
        inst_state(0o06, 1),
        inst_state(0o16, 1),
        inst_state(0o26, 1),
        inst_state(0o36, 1),
        inst_state(0o46, 1),
        inst_state(0o56, 1),
        inst_state(0o76, 1),
        => {
            const reg = cpu.reg_decode(y);
            reg.* = bus.dbus;
            bus = cpu.fetch_and_decode(bus);
        },

        // LD (HL), imm8
        inst_state(0o66, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.state.cycle += 1;
        },
        inst_state(0o66, 1) => {
            bus = mem_write(bus, cpu.registers.hl(), bus.dbus);
            cpu.state.cycle += 1;
        },
        inst_state(0o66, 2) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // HALT
        inst_state(0o166, 0) => {
            //TODO
        },

        // LD (BC), A
        inst_state(0o02, 0) => {
            bus = mem_write(bus, cpu.registers.bc(), cpu.registers.a);
            cpu.state.cycle += 1;
        },
        inst_state(0o02, 1) => {
            cpu.fetch_and_decode();
        },
        // LD A, (BC)
        inst_state(0o12, 0) => {
            bus = mem_read(bus, cpu.registers.bc());
            cpu.state.cycle += 1;
        },
        inst_state(0o12, 1) => {
            cpu.registers.a = bus.dbus;
            cpu.fetch_and_decode();
        },

        // LD (DE), A
        inst_state(0o22, 0) => {
            bus = mem_write(bus, cpu.registers.de(), cpu.registers.a);
            cpu.state.cycle += 1;
        },
        inst_state(0o22, 1) => {
            cpu.fetch_and_decode();
        },
        // LD A, (DE)
        inst_state(0o32, 0) => {
            bus = mem_read(bus, cpu.registers.de());
            cpu.state.cycle += 1;
        },
        inst_state(0o32, 1) => {
            cpu.registers.a = bus.dbus;
            cpu.fetch_and_decode();
        },

        // LD (HL+), A
        inst_state(0o42, 0) => {
            const hl = cpu.registers.hl();
            bus = mem_write(bus, hl, cpu.registers.a);
            cpu.registers.sethl(hl +% 1);
            cpu.state.cycle += 1;
        },
        inst_state(0o42, 1) => {
            cpu.fetch_and_decode();
        },

        // LD A, (HL+)
        inst_state(0o52, 0) => {
            const hl = cpu.registers.hl();
            bus = mem_read(bus, hl);
            cpu.registers.sethl(hl +% 1);
            cpu.state.cycle += 1;
        },
        inst_state(0o52, 1) => {
            cpu.registers.a = bus.dbus;
            cpu.fetch_and_decode();
        },

        // LD (HL-), A
        inst_state(0o62, 0) => {
            const hl = cpu.registers.hl();
            bus = mem_write(bus, hl, cpu.registers.a);
            cpu.registers.sethl(hl -% 1);
            cpu.state.cycle += 1;
        },
        inst_state(0o62, 1) => {
            cpu.fetch_and_decode();
        },

        // LD A, (HL-)
        inst_state(0o72, 0) => {
            const hl = cpu.registers.hl();
            bus = mem_read(bus, hl);
            cpu.registers.sethl(hl -% 1);
            cpu.state.cycle += 1;
        },
        inst_state(0o72, 1) => {
            cpu.registers.a = bus.dbus;
            cpu.fetch_and_decode();
        },

        // zig fmt: off
        // Add A, r
        inst_state(0o200, 0)...inst_state(0o205), inst_state(0o207),
        inst_state(0o210, 0)...inst_state(0o215), inst_state(0o217),
        inst_state(0o220, 0)...inst_state(0o225), inst_state(0o227),
        inst_state(0o230, 0)...inst_state(0o235), inst_state(0o237),
        inst_state(0o240, 0)...inst_state(0o245), inst_state(0o247),
        inst_state(0o250, 0)...inst_state(0o255), inst_state(0o257),
        inst_state(0o260, 0)...inst_state(0o265), inst_state(0o267),
        inst_state(0o270, 0)...inst_state(0o275), inst_state(0o277),
        => {
            const reg = cpu.reg_decode(z).*;
            cpu.alu_decode(y, reg);
            bus = cpu.fetch_and_decode(bus);
        },
        // zig fmt: on
        // Add r, (HL)
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
            cpu.state.cycle += 1;
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
            cpu.state.cycle += 1;
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
        inst_state(0x342, 0) => {
            bus = mem_write(bus, pair(0xFF, cpu.registers.c), cpu.registers.a);
            cpu.state.cycle += 1;
        },
        inst_state(0x342, 1) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // LD (imm16), A
        inst_state(0o352, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.state.cycle += 1;
        },
        inst_state(0o352, 1) => {
            cpu.z = bus.dbus;
            bus = cpu.fetch_pc(bus);
            cpu.state.cycle += 1;
        },
        inst_state(0o352, 2) => {
            cpu.w = bus.dbus;
            bus = mem_write(bus, cpu.wz(), cpu.registers.a);
            cpu.state.cycle += 1;
        },
        inst_state(0o352, 3) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // LDH A, (C)
        inst_state(0o362, 0) => {
            bus = mem_read(bus, pair(0xFF, cpu.registers.c));
            cpu.state.cycle += 1;
        },
        inst_state(0o362, 1) => {
            cpu.registers.a = bus.dbus;
            cpu.fetch_and_decode();
        },

        // LD A, (imm16)
        inst_state(0o372, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.state.cycle += 1;
        },
        inst_state(0o372, 1) => {
            cpu.z = bus.dbus;
            bus = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0o372, 2) => {
            cpu.w = bus.dbus;
            bus = mem_read(bus, cpu.wz());
            cpu.state.cycle += 1;
        },
        inst_state(0o372, 3) => {
            cpu.registers.a = bus.dbus;
            cpu.fetch_and_decode();
        },

        // LDH (imm8), A
        inst_state(0o340, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.state.cycle += 1;
        },
        inst_state(0o340, 1) => {
            bus = mem_write(bus, pair(0xFF, bus.dbus), cpu.registers.a);
            cpu.state.cycle += 1;
        },
        inst_state(0o340, 2) => {
            bus = cpu.fetch_and_decode(bus);
        },

        // ADD SP, e
        inst_state(0o350, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.state.cycle += 1;
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
            cpu.state.cycle += 1;
        },
        inst_state(0o350, 2) => {
            cpu.state.cycle += 1;
        },
        inst_state(0o350, 3) => {
            cpu.registers.sp = cpu.wz();
            bus = cpu.fetch_and_decode(bus);
        },

        // LDH A, (imm8)
        inst_state(0o360, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.state.cycle += 1;
        },
        inst_state(0o360, 1) => {
            bus = mem_read(bus, pair(0xFF, bus.dbus));
            cpu.state.cycle += 1;
        },
        inst_state(0o360, 2) => {
            cpu.registers.a = bus.dbus;
            bus = cpu.fetch_and_decode(bus);
        },

        // LD HL, SP+e
        inst_state(0o370, 0) => {
            bus = cpu.fetch_pc(bus);
            cpu.state.cycle += 1;
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

            cpu.state.cycle += 1;
        },
        inst_state(0o370, 2) => {
            cpu.registers.sethl(add_signed(cpu.registers.sp, cpu.z));

            bus = cpu.fetch_and_decode(bus);
        },

        // LD SP, HL
        inst_state(0xF9, 0) => {
            cpu.registers.sp = cpu.registers.hl();
            cpu.state.cycle += 1;
        },
        inst_state(0xF9, 1) => {
            cpu.fetch_and_decode();
        },

        // LD BC, imm16
        inst_state(0x01, 0) => {
            cpu.z = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0x01, 1) => {
            cpu.w = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0x01, 2) => {
            cpu.registers.setbc(cpu.wz());
            cpu.fetch_and_decode();
        },

        // LD DE, imm16
        inst_state(0x11, 0) => {
            cpu.z = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0x11, 1) => {
            cpu.w = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0x11, 2) => {
            cpu.registers.setde(cpu.wz());
            cpu.fetch_and_decode();
        },

        // LD HL, imm16
        inst_state(0x21, 0) => {
            cpu.z = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0x21, 1) => {
            cpu.w = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0x21, 2) => {
            cpu.registers.sethl(cpu.wz());
            cpu.fetch_and_decode();
        },

        // LD SP, imm16
        inst_state(0x31, 0) => {
            cpu.z = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0x31, 1) => {
            cpu.w = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0x31, 2) => {
            cpu.registers.sp = cpu.wz();
            cpu.fetch_and_decode();
        },

        // ADD HL, BC
        inst_state(0x09, 0) => {
            cpu.add_pair_to_hl(.bc);
            cpu.state.cycle += 1;
        },
        inst_state(0x09, 1) => {
            cpu.fetch_and_decode();
        },
        // ADD HL, DE
        inst_state(0x19, 0) => {
            cpu.add_pair_to_hl(.de);
            cpu.state.cycle += 1;
        },
        inst_state(0x19, 1) => {
            cpu.fetch_and_decode();
        },
        // ADD HL, HL
        inst_state(0x29, 0) => {
            cpu.add_pair_to_hl(.hl);
            cpu.state.cycle += 1;
        },
        inst_state(0x29, 1) => {
            cpu.fetch_and_decode();
        },
        // ADD HL, SP
        inst_state(0x39, 0) => {
            cpu.add_pair_to_hl(.sp);
            cpu.state.cycle += 1;
        },
        inst_state(0x39, 1) => {
            cpu.fetch_and_decode();
        },

        // DEC bc
        inst_state(0x0B, 0) => {
            cpu.dec16(.bc);
            cpu.state.cycle += 1;
        },
        inst_state(0x0B, 1) => {
            cpu.fetch_and_decode();
        },

        // DEC de
        inst_state(0x1B, 0) => {
            cpu.dec16(.de);
            cpu.state.cycle += 1;
        },
        inst_state(0x1B, 1) => {
            cpu.fetch_and_decode();
        },

        // DEC hl
        inst_state(0x2B, 0) => {
            cpu.dec16(.hl);
            cpu.state.cycle += 1;
        },
        inst_state(0x2B, 1) => {
            cpu.fetch_and_decode();
        },

        // DEC sp
        inst_state(0x3B, 0) => {
            cpu.dec16(.sp);
            cpu.state.cycle += 1;
        },
        inst_state(0x3B, 1) => {
            cpu.fetch_and_decode();
        },

        // INC bc
        inst_state(0x03, 0) => {
            cpu.inc16(.bc);
            cpu.state.cycle += 1;
        },
        inst_state(0x03, 1) => {
            cpu.fetch_and_decode();
        },

        // INC de
        inst_state(0x13, 0) => {
            cpu.inc16(.de);
            cpu.state.cycle += 1;
        },
        inst_state(0x13, 1) => {
            cpu.fetch_and_decode();
        },

        // INC hl
        inst_state(0x23, 0) => {
            cpu.inc16(.hl);
            cpu.state.cycle += 1;
        },
        inst_state(0x23, 1) => {
            cpu.fetch_and_decode();
        },

        // INC sp
        inst_state(0x33, 0) => {
            cpu.inc16(.sp);
            cpu.state.cycle += 1;
        },
        inst_state(0x33, 1) => {
            cpu.fetch_and_decode();
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
            cpu.inc(cpu.reg_decode(y));
            cpu.fetch_and_decode();
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
            cpu.dec(cpu.reg_decode(y));
            cpu.fetch_and_decode();
        },

        // INC (HL)
        inst_state(0o64, 0) => {
            cpu.z = mem_read(bus, cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0o64, 1) => {
            cpu.inc(&cpu.z);
            mem_write(bus, cpu.registers.hl(), cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0o64, 2) => {
            cpu.fetch_and_decode();
        },
        // DEC (HL)
        inst_state(0o65, 0) => {
            cpu.z = mem_read(bus, cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0o65, 1) => {
            cpu.dec(&cpu.z);
            mem_write(bus, cpu.registers.hl(), cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0o65, 2) => {
            cpu.fetch_and_decode();
        },

        // CCF
        inst_state(0x3F, 0) => {
            cpu.registers.flags.n = false;
            cpu.registers.flags.h = false;
            cpu.registers.flags.c = !cpu.registers.flags.c;
            cpu.fetch_and_decode();
        },

        // SCF
        inst_state(0x37, 0) => {
            cpu.registers.flags.n = false;
            cpu.registers.flags.h = false;
            cpu.registers.flags.c = true;
            cpu.fetch_and_decode();
        },

        // DAA
        inst_state(0x27, 0) => {
            // TODO
            unreachable;
        },

        // CPL
        inst_state(0x2F, 0) => {
            cpu.registers.a = ~cpu.registers.a;
            cpu.registers.flags.n = true;
            cpu.registers.flags.h = true;
            cpu.fetch_and_decode();
        },

        // RLCA
        inst_state(0x07, 0) => {
            cpu.rlc(&cpu.registers.a);
            cpu.registers.flags.z = false;
            cpu.fetch_and_decode();
        },

        // RRCA
        inst_state(0x0F, 0) => {
            cpu.rrc(&cpu.registers.a);
            cpu.registers.flags.z = false;
            cpu.fetch_and_decode();
        },

        // RLA
        inst_state(0x17, 0) => {
            cpu.rl(&cpu.registers.a);
            cpu.registers.flags.z = false;
            cpu.fetch_and_decode();
        },

        // RRA
        inst_state(0x1F, 0) => {
            cpu.rr(&cpu.registers.a);
            cpu.registers.flags.z = false;
            cpu.fetch_and_decode();
        },

        // PUSH bc
        inst_state(0xC5, 0) => {
            cpu.state.cycle += 1;
        },
        inst_state(0xC5, 1) => {
            cpu.push(msb(cpu.registers.bc()));
            cpu.state.cycle += 1;
        },
        inst_state(0xC5, 2) => {
            cpu.push(lsb(cpu.registers.bc()));
            cpu.state.cycle += 1;
        },
        inst_state(0xC5, 3) => {
            cpu.fetch_and_decode();
        },

        // PUSH de
        inst_state(0xD5, 0) => {
            cpu.state.cycle += 1;
        },
        inst_state(0xD5, 1) => {
            cpu.push(msb(cpu.registers.de()));
            cpu.state.cycle += 1;
        },
        inst_state(0xD5, 2) => {
            cpu.push(lsb(cpu.registers.de()));
            cpu.state.cycle += 1;
        },
        inst_state(0xD5, 3) => {
            cpu.fetch_and_decode();
        },

        // PUSH hl
        inst_state(0xE5, 0) => {
            cpu.state.cycle += 1;
        },
        inst_state(0xE5, 1) => {
            cpu.push(msb(cpu.registers.hl()));
            cpu.state.cycle += 1;
        },
        inst_state(0xE5, 2) => {
            cpu.push(lsb(cpu.registers.hl()));
            cpu.state.cycle += 1;
        },
        inst_state(0xE5, 3) => {
            cpu.fetch_and_decode();
        },

        // PUSH af
        inst_state(0xF5, 0) => {
            cpu.state.cycle += 1;
        },
        inst_state(0xF5, 1) => {
            cpu.push(msb(cpu.registers.af()));
            cpu.state.cycle += 1;
        },
        inst_state(0xF5, 2) => {
            cpu.push(lsb(cpu.registers.af()));
            cpu.state.cycle += 1;
        },
        inst_state(0xF5, 3) => {
            cpu.fetch_and_decode();
        },

        // POP bc
        inst_state(0xC1, 0) => {
            cpu.z = cpu.pop();
            cpu.state.cycle += 1;
        },
        inst_state(0xC1, 1) => {
            cpu.w = cpu.pop();
            cpu.state.cycle += 1;
        },
        inst_state(0xC1, 2) => {
            cpu.registers.setbc(cpu.wz());
            cpu.fetch_and_decode();
        },

        // POP de
        inst_state(0xD1, 0) => {
            cpu.z = cpu.pop();
            cpu.state.cycle += 1;
        },
        inst_state(0xD1, 1) => {
            cpu.w = cpu.pop();
            cpu.state.cycle += 1;
        },
        inst_state(0xD1, 2) => {
            cpu.registers.setde(cpu.wz());
            cpu.fetch_and_decode();
        },

        // POP hl
        inst_state(0xE1, 0) => {
            cpu.z = cpu.pop();
            cpu.state.cycle += 1;
        },
        inst_state(0xE1, 1) => {
            cpu.w = cpu.pop();
            cpu.state.cycle += 1;
        },
        inst_state(0xE1, 2) => {
            cpu.registers.sethl(cpu.wz());
            cpu.fetch_and_decode();
        },

        // POP af
        inst_state(0xF1, 0) => {
            cpu.z = cpu.pop();
            cpu.state.cycle += 1;
        },
        inst_state(0xF1, 1) => {
            cpu.w = cpu.pop();
            cpu.state.cycle += 1;
        },
        inst_state(0xF1, 2) => {
            cpu.registers.setaf(cpu.wz());
            cpu.fetch_and_decode();
        },

        // JP imm16
        inst_state(0xC3, 0) => {
            cpu.z = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0xC3, 1) => {
            cpu.w = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0xC3, 2) => {
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xC3, 3) => {
            cpu.fetch_and_decode();
        },

        inst_state(0xE9, 0) => {
            cpu.registers.pc = cpu.registers.hl();
            cpu.fetch_and_decode();
        },

        // JP NZ, imm16
        inst_state(0xC2, 0) => {
            cpu.z = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0xC2, 1) => {
            cpu.w = cpu.fetch_pc();
            if (cpu.registers.flags.z) {
                cpu.state.cycle += 1;
            }
            cpu.state.cycle += 1;
        },
        inst_state(0xC2, 2) => {
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xC2, 3) => {
            cpu.fetch_and_decode();
        },

        // JP NC, imm16
        inst_state(0xD2, 0) => {
            cpu.z = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0xD2, 1) => {
            cpu.w = cpu.fetch_pc();
            if (cpu.registers.flags.c) {
                cpu.state.cycle += 1;
            }
            cpu.state.cycle += 1;
        },
        inst_state(0xD2, 2) => {
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xD2, 3) => {
            cpu.fetch_and_decode();
        },

        // JP Z, imm16
        inst_state(0xCA, 0) => {
            cpu.z = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0xCA, 1) => {
            cpu.w = cpu.fetch_pc();
            if (!cpu.registers.flags.z) {
                cpu.state.cycle += 1;
            }
            cpu.state.cycle += 1;
        },
        inst_state(0xCA, 2) => {
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xCA, 3) => {
            cpu.fetch_and_decode();
        },

        // JP C, imm16
        inst_state(0xDA, 0) => {
            cpu.z = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0xDA, 1) => {
            cpu.w = cpu.fetch_pc();
            if (!cpu.registers.flags.c) {
                cpu.state.cycle += 1;
            }
            cpu.state.cycle += 1;
        },
        inst_state(0xDA, 2) => {
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xDA, 3) => {
            cpu.fetch_and_decode();
        },

        // JP e
        inst_state(0x18, 0) => {
            cpu.z = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0x18, 1) => {
            cpu.registers.pc = add_signed(cpu.registers.pc, cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0x18, 2) => {
            cpu.fetch_and_decode();
        },

        // JP NZ, e
        inst_state(0x20, 0) => {
            cpu.z = cpu.fetch_pc();

            if (cpu.registers.flags.z) {
                cpu.state.cycle += 1;
            }
            cpu.state.cycle += 1;
        },
        inst_state(0x20, 1) => {
            cpu.registers.pc = add_signed(cpu.registers.pc, cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0x20, 2) => {
            cpu.fetch_and_decode();
        },

        // JP NC, e
        inst_state(0x30, 0) => {
            cpu.z = cpu.fetch_pc();

            if (cpu.registers.flags.c) {
                cpu.state.cycle += 1;
            }
            cpu.state.cycle += 1;
        },
        inst_state(0x30, 1) => {
            cpu.registers.pc = add_signed(cpu.registers.pc, cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0x30, 2) => {
            cpu.fetch_and_decode();
        },

        // JP Z, e
        inst_state(0x28, 0) => {
            cpu.z = cpu.fetch_pc();

            if (!cpu.registers.flags.z) {
                cpu.state.cycle += 1;
            }
            cpu.state.cycle += 1;
        },
        inst_state(0x28, 1) => {
            cpu.registers.pc = add_signed(cpu.registers.pc, cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0x28, 2) => {
            cpu.fetch_and_decode();
        },
        // JP C, e
        inst_state(0x38, 0) => {
            cpu.z = cpu.fetch_pc();

            if (!cpu.registers.flags.c) {
                cpu.state.cycle += 1;
            }
            cpu.state.cycle += 1;
        },
        inst_state(0x38, 1) => {
            cpu.registers.pc = add_signed(cpu.registers.pc, cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0x38, 2) => {
            cpu.fetch_and_decode();
        },

        // CALL imm16
        inst_state(0xCD, 0) => {
            cpu.z = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0xCD, 1) => {
            cpu.w = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0xCD, 2) => {
            cpu.registers.sp -%= 1;
            cpu.state.cycle += 1;
        },
        inst_state(0xCD, 3) => {
            mem_write(bus, cpu.registers.sp, msb(cpu.registers.pc));
            cpu.registers.sp -%= 1;
            cpu.state.cycle += 1;
        },
        inst_state(0xCD, 4) => {
            mem_write(bus, cpu.registers.sp, lsb(cpu.registers.pc));
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xCD, 5) => {
            cpu.fetch_and_decode();
        },

        // CALL NZ, imm16
        inst_state(0xC4, 0) => {
            cpu.z = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0xC4, 1) => {
            cpu.w = cpu.fetch_pc();
            if (cpu.registers.flags.z) {
                cpu.state.cycle += 3;
            }
            cpu.state.cycle += 1;
        },
        inst_state(0xC4, 2) => {
            cpu.registers.sp -%= 1;
            cpu.state.cycle += 1;
        },
        inst_state(0xC4, 3) => {
            mem_write(bus, cpu.registers.sp, msb(cpu.registers.pc));
            cpu.registers.sp -%= 1;
            cpu.state.cycle += 1;
        },
        inst_state(0xC4, 4) => {
            mem_write(bus, cpu.registers.sp, lsb(cpu.registers.pc));
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xC4, 5) => {
            cpu.fetch_and_decode();
        },

        // CALL NC, imm16
        inst_state(0xD4, 0) => {
            cpu.z = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0xD4, 1) => {
            cpu.w = cpu.fetch_pc();
            if (cpu.registers.flags.c) {
                cpu.state.cycle += 3;
            }
            cpu.state.cycle += 1;
        },
        inst_state(0xD4, 2) => {
            cpu.registers.sp -%= 1;
            cpu.state.cycle += 1;
        },
        inst_state(0xD4, 3) => {
            mem_write(bus, cpu.registers.sp, msb(cpu.registers.pc));
            cpu.registers.sp -%= 1;
            cpu.state.cycle += 1;
        },
        inst_state(0xD4, 4) => {
            mem_write(bus, cpu.registers.sp, lsb(cpu.registers.pc));
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xD4, 5) => {
            cpu.fetch_and_decode();
        },

        // CALL Z, imm16
        inst_state(0xCC, 0) => {
            cpu.z = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0xCC, 1) => {
            cpu.w = cpu.fetch_pc();
            if (!cpu.registers.flags.z) {
                cpu.state.cycle += 3;
            }
            cpu.state.cycle += 1;
        },
        inst_state(0xCC, 2) => {
            cpu.registers.sp -%= 1;
            cpu.state.cycle += 1;
        },
        inst_state(0xCC, 3) => {
            mem_write(bus, cpu.registers.sp, msb(cpu.registers.pc));
            cpu.registers.sp -%= 1;
            cpu.state.cycle += 1;
        },
        inst_state(0xCC, 4) => {
            mem_write(bus, cpu.registers.sp, lsb(cpu.registers.pc));
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xCC, 5) => {
            cpu.fetch_and_decode();
        },

        // CALL C, imm16
        inst_state(0xDC, 0) => {
            cpu.z = cpu.fetch_pc();
            cpu.state.cycle += 1;
        },
        inst_state(0xDC, 1) => {
            cpu.w = cpu.fetch_pc();
            if (!cpu.registers.flags.c) {
                cpu.state.cycle += 3;
            }
            cpu.state.cycle += 1;
        },
        inst_state(0xDC, 2) => {
            cpu.registers.sp -%= 1;
            cpu.state.cycle += 1;
        },
        inst_state(0xDC, 3) => {
            mem_write(bus, cpu.registers.sp, msb(cpu.registers.pc));
            cpu.registers.sp -%= 1;
            cpu.state.cycle += 1;
        },
        inst_state(0xDC, 4) => {
            mem_write(bus, cpu.registers.sp, lsb(cpu.registers.pc));
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xDC, 5) => {
            cpu.fetch_and_decode();
        },

        // RET
        inst_state(0xC9, 0) => {
            cpu.z = cpu.pop();
            cpu.state.cycle += 1;
        },
        inst_state(0xC9, 1) => {
            cpu.w = cpu.pop();
            cpu.state.cycle += 1;
        },
        inst_state(0xC9, 2) => {
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xC9, 3) => {
            cpu.fetch_and_decode();
        },

        // RET NZ
        inst_state(0xC0, 0) => {
            if (cpu.registers.flags.z) {
                cpu.state.cycle += 2;
            } else {
                cpu.z = cpu.pop();
            }
            cpu.state.cycle += 1;
        },
        inst_state(0xC0, 1) => {
            cpu.w = cpu.pop();
            cpu.state.cycle += 1;
        },
        inst_state(0xC0, 2) => {
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xC0, 3) => {
            cpu.fetch_and_decode();
        },

        // RET NC
        inst_state(0xD0, 0) => {
            if (cpu.registers.flags.c) {
                cpu.state.cycle += 2;
            } else {
                cpu.z = cpu.pop();
            }
            cpu.state.cycle += 1;
        },
        inst_state(0xD0, 1) => {
            cpu.w = cpu.pop();
            cpu.state.cycle += 1;
        },
        inst_state(0xD0, 2) => {
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xD0, 3) => {
            cpu.fetch_and_decode();
        },

        // RET Z
        inst_state(0xC8, 0) => {
            if (!cpu.registers.flags.z) {
                cpu.state.cycle += 2;
            } else {
                cpu.z = cpu.pop();
            }
            cpu.state.cycle += 1;
        },
        inst_state(0xC8, 1) => {
            cpu.w = cpu.pop();
            cpu.state.cycle += 1;
        },
        inst_state(0xC8, 2) => {
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xC8, 3) => {
            cpu.fetch_and_decode();
        },

        // RET C
        inst_state(0xD8, 0) => {
            if (!cpu.registers.flags.c) {
                cpu.state.cycle += 2;
            } else {
                cpu.z = cpu.pop();
            }
            cpu.state.cycle += 1;
        },
        inst_state(0xD8, 1) => {
            cpu.w = cpu.pop();
            cpu.state.cycle += 1;
        },
        inst_state(0xD8, 2) => {
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xD8, 3) => {
            cpu.fetch_and_decode();
        },

        // RETI
        inst_state(0xD9, 0) => {
            cpu.z = cpu.pop();
            cpu.state.cycle += 1;
        },
        inst_state(0xD9, 1) => {
            cpu.w = cpu.pop();
            cpu.state.cycle += 1;
        },
        inst_state(0xD9, 2) => {
            cpu.registers.pc = cpu.wz();
            cpu.ime = true;
            cpu.state.cycle += 1;
        },
        inst_state(0xD9, 3) => {
            cpu.fetch_and_decode();
        },

        // RST 0x00
        inst_state(0xC7, 0) => {
            cpu.state.cycle += 1;
        },
        inst_state(0xC7, 1) => {
            cpu.push(msb(cpu.registers.pc));
            cpu.state.cycle += 1;
        },
        inst_state(0xC7, 2) => {
            cpu.push(lsb(cpu.registers.pc));
            cpu.registers.pc = 0x00;
            cpu.state.cycle += 1;
        },
        inst_state(0xC7, 3) => {
            cpu.fetch_and_decode();
        },

        // RST 0x08
        inst_state(0xCF, 0) => {
            cpu.state.cycle += 1;
        },
        inst_state(0xCF, 1) => {
            cpu.push(msb(cpu.registers.pc));
            cpu.state.cycle += 1;
        },
        inst_state(0xCF, 2) => {
            cpu.push(lsb(cpu.registers.pc));
            cpu.registers.pc = 0x08;
            cpu.state.cycle += 1;
        },
        inst_state(0xCF, 3) => {
            cpu.fetch_and_decode();
        },

        // RST 0x10
        inst_state(0xD7, 0) => {
            cpu.state.cycle += 1;
        },
        inst_state(0xD7, 1) => {
            cpu.push(msb(cpu.registers.pc));
            cpu.state.cycle += 1;
        },
        inst_state(0xD7, 2) => {
            cpu.push(lsb(cpu.registers.pc));
            cpu.registers.pc = 0x10;
            cpu.state.cycle += 1;
        },
        inst_state(0xD7, 3) => {
            cpu.fetch_and_decode();
        },

        // RST 0x18
        inst_state(0xDF, 0) => {
            cpu.state.cycle += 1;
        },
        inst_state(0xDF, 1) => {
            cpu.push(msb(cpu.registers.pc));
            cpu.state.cycle += 1;
        },
        inst_state(0xDF, 2) => {
            cpu.push(lsb(cpu.registers.pc));
            cpu.registers.pc = 0x18;
            cpu.state.cycle += 1;
        },
        inst_state(0xDF, 3) => {
            cpu.fetch_and_decode();
        },

        // RST 0x20
        inst_state(0xE7, 0) => {
            cpu.state.cycle += 1;
        },
        inst_state(0xE7, 1) => {
            cpu.push(msb(cpu.registers.pc));
            cpu.state.cycle += 1;
        },
        inst_state(0xE7, 2) => {
            cpu.push(lsb(cpu.registers.pc));
            cpu.registers.pc = 0x20;
            cpu.state.cycle += 1;
        },
        inst_state(0xE7, 3) => {
            cpu.fetch_and_decode();
        },

        // RST 0x28
        inst_state(0xEF, 0) => {
            cpu.state.cycle += 1;
        },
        inst_state(0xEF, 1) => {
            cpu.push(msb(cpu.registers.pc));
            cpu.state.cycle += 1;
        },
        inst_state(0xEF, 2) => {
            cpu.push(lsb(cpu.registers.pc));
            cpu.registers.pc = 0x28;
            cpu.state.cycle += 1;
        },
        inst_state(0xEF, 3) => {
            cpu.fetch_and_decode();
        },

        // RST 0x30
        inst_state(0xF7, 0) => {
            cpu.state.cycle += 1;
        },
        inst_state(0xF7, 1) => {
            cpu.push(msb(cpu.registers.pc));
            cpu.state.cycle += 1;
        },
        inst_state(0xF7, 2) => {
            cpu.push(lsb(cpu.registers.pc));
            cpu.registers.pc = 0x30;
            cpu.state.cycle += 1;
        },
        inst_state(0xF7, 3) => {
            cpu.fetch_and_decode();
        },

        // RST 0x38
        inst_state(0xFF, 0) => {
            cpu.state.cycle += 1;
        },
        inst_state(0xFF, 1) => {
            cpu.push(msb(cpu.registers.pc));
            cpu.state.cycle += 1;
        },
        inst_state(0xFF, 2) => {
            cpu.push(lsb(cpu.registers.pc));
            cpu.registers.pc = 0x38;
            cpu.state.cycle += 1;
        },
        inst_state(0xFF, 3) => {
            cpu.fetch_and_decode();
        },

        // EI
        inst_state(0xFB, 0) => {
            cpu.should_set_ime = true;
            cpu.fetch_and_decode();
        },

        // DI
        inst_state(0xF3, 0) => {
            cpu.ime = false;
            cpu.fetch_and_decode();
        },

        inst_state(0xCB, 0) => {
            cpu.fetch_and_decode_extended();
        },

        else => unreachable,
    }

    return bus;
}

fn decode_cb(cpu: *SM83, bus: *Pins) void {
    const op: u5 = @truncate(cpu.state.opcode >> 3);
    const reg_idx: u3 = @truncate(cpu.state.opcode);

    if (reg_idx == 6) {
        switch ((cpu.state.cycle << 5) | op) {
            0b00000...0b11111 => {
                bus.* = mem_read(bus, cpu.registers.hl());
            },
            0b100000...0b100111, 0b110000...0b111111 => {
                const read_data = bus.dbus;
                const result = cpu.apply_cb_op(op, read_data);
                bus.* = mem_write(bus, cpu.registers.hl(), result);
            },
            0b101000...0b1011111 => {
                const read_data = bus.dbus;
                _ = cpu.apply_cb_op(op, read_data);
                bus.* = cpu.fetch_and_decode(bus);
            },
            0b1000000...0b1011111 => {
                bus.* = cpu.fetch_and_decode(bus);
            },
        }
    } else {
        const reg = cpu.reg_decode(reg_idx);
        reg.* = cpu.apply_cb_op(op, reg.*);
        bus.* = cpu.fetch_and_decode(bus);
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
            cpu.bit(reg, op - 8);
            break :blk reg;
        },
        16...23 => cpu.res(reg, op - 16),
        24...31 => cpu.set(reg, op - 24),
    };
}

fn reg_decode(cpu: *SM83, reg_idx: u3) *u8 {
    return switch (reg_idx) {
        0b000 => *cpu.registers.b,
        0b001 => *cpu.registers.c,
        0b010 => *cpu.registers.d,
        0b011 => *cpu.registers.e,
        0b100 => *cpu.registers.h,
        0b101 => *cpu.registers.l,
        0b110 => unreachable,
        0b111 => *cpu.registers.a,
    };
}

fn alu_decode(cpu: *SM83, alu_op: u3, reg: u8) void {
    switch (alu_op) {
        0 => cpu.add(reg),
        1 => cpu.adc(reg),
        2 => cpu.sub(reg),
        3 => cpu.sbc(reg),
        4 => cpu.@"and"(reg),
        5 => cpu.@"or"(reg),
        6 => cpu.xor(reg),
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
    const sign_extended: u16 = @bitCast(@as(i16, @intCast(signed_e)));
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

/// Fetches the next instruction opcode and resets the cycle counter.
fn fetch_and_decode(cpu: *const SM83, bus: Pins) Pins {
    defer cpu.registers.pc += 1;
    cpu.state.cycle = 0;
    return bus.set(.{
        .abus = cpu.registers.pc,
        .mreq = 1,
        .rd = 1,
        .m1 = 1,
    });
}

fn fetch_and_decode_extended(cpu: *SM83) void {
    cpu.state = .{ .opcode = cpu.fetch_pc(), .cycle = 0, .is_cb_inst = true };
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
    var result, const carry = @shlWithOverflow(reg.*, 1);
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
    const result = (reg.* >> 1) | (old_carry << 7);
    cpu.registers.flags = .{
        .z = reg.* == 0,
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

const RegPairs = enum {
    bc,
    de,
    hl,
    sp,
};

fn inc16(cpu: *SM83, comptime reg_pair: RegPairs) void {
    switch (reg_pair) {
        .bc => {
            cpu.registers.setbc(cpu.registers.bc() +% 1);
        },
        .de => {
            cpu.registers.setde(cpu.registers.de() +% 1);
        },
        .hl => {
            cpu.registers.sethl(cpu.registers.hl() +% 1);
        },
        .sp => {
            cpu.registers.sp +%= 1;
        },
    }
}

fn dec16(cpu: *SM83, comptime reg_pair: RegPairs) void {
    switch (reg_pair) {
        .bc => {
            cpu.registers.setbc(cpu.registers.bc() -% 1);
        },
        .de => {
            cpu.registers.setde(cpu.registers.de() -% 1);
        },
        .hl => {
            cpu.registers.sethl(cpu.registers.hl() -% 1);
        },
        .sp => {
            cpu.registers.sp -%= 1;
        },
    }
}

fn add_pair_to_hl(cpu: *SM83, comptime reg_pair: RegPairs) void {
    const reg = switch (reg_pair) {
        .bc => cpu.registers.bc(),
        .de => cpu.registers.de(),
        .hl => cpu.registers.hl(),
        .sp => cpu.registers.sp,
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

test {
    @import("std").testing.refAllDeclsRecursive(SM83);
}

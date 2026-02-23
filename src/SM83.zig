//! The emulated SM83 chip.
//! Apparently, we don't actually know if SM83 was the actual codename.
//! https://github.com/Gekkio/gb-research/tree/main/sm83-cpu-core

const SM83 = @This();

state: State,
registers: Registers,
z: u8 = 0,
w: u8 = 0,
ime: bool = false,
memory: [65535]u8,
pins: Pins,

/// https://iceboy.a-singer.de/doc/dmg_cpu_connections.html
const Pins = packed struct(u64) {
    m1: u1,
    exec_phase: u2,
    data_phase: u2,
    write_phase: u2,
    pch_phase: u1,
    clk: u2,
    halt: u1,
    sys_reset: u1,
    pwron_reset: u1,
    stop: u1,
    clk_ready: u1,
    nmi: u1,
    rd: u1,
    wr: u1,
    oe: u1,
    internal_access: u1,
    shadow_access: u1,
    shadow_override: u1,
    mreq: u1,
    int: u8,
    inta: u8,
    prefix_cb: u1,
    dbus: u8,
    abus: u16,
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

    a: u8,
    flags: Flags,

    b: u8,
    c: u8,
    d: u8,
    e: u8,
    h: u8,
    l: u8,

    pc: u16,
    sp: u16,

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

const State = struct { inst: u8, cycle: u8, is_cb_inst: bool };

pub fn tick(cpu: *SM83) void {
    if (cpu.state.is_cb_inst) {
        cpu.decode_cb();
    } else switch (@as(u16, cpu.state.inst) << 3 | cpu.state.cycle) {
        // NOP
        inst_state(0x00, 0) => {
            cpu.fetch_and_decode();
        },

        // HALT
        inst_state(0x76, 0) => {
            //TODO
        },

        // STOP
        inst_state(0x10, 0) => {
            //TODO
        },

        // LD b, b
        inst_state(0x40, 0) => {
            cpu.registers.b = cpu.registers.b;
            cpu.fetch_and_decode();
        },

        // LD b, c
        inst_state(0x41, 0) => {
            cpu.registers.b = cpu.registers.c;
            cpu.fetch_and_decode();
        },

        // LD b, d
        inst_state(0x42, 0) => {
            cpu.registers.b = cpu.registers.d;
            cpu.fetch_and_decode();
        },

        // LD b, e
        inst_state(0x43, 0) => {
            cpu.registers.b = cpu.registers.e;
            cpu.fetch_and_decode();
        },

        // LD b, h
        inst_state(0x44, 0) => {
            cpu.registers.b = cpu.registers.h;
            cpu.fetch_and_decode();
        },

        // LD b, l
        inst_state(0x45, 0) => {
            cpu.registers.b = cpu.registers.l;
            cpu.fetch_and_decode();
        },

        // LD b, a
        inst_state(0x47, 0) => {
            cpu.registers.b = cpu.registers.a;
            cpu.fetch_and_decode();
        },

        // LD c, b
        inst_state(0x48, 0) => {
            cpu.registers.c = cpu.registers.b;
            cpu.fetch_and_decode();
        },

        // LD c, c
        inst_state(0x49, 0) => {
            cpu.registers.c = cpu.registers.c;
            cpu.fetch_and_decode();
        },

        // LD c, d
        inst_state(0x4A, 0) => {
            cpu.registers.c = cpu.registers.d;
            cpu.fetch_and_decode();
        },

        // LD c, e
        inst_state(0x4B, 0) => {
            cpu.registers.c = cpu.registers.e;
            cpu.fetch_and_decode();
        },

        // LD c, h
        inst_state(0x4C, 0) => {
            cpu.registers.c = cpu.registers.h;
            cpu.fetch_and_decode();
        },

        // LD c, l
        inst_state(0x4D, 0) => {
            cpu.registers.c = cpu.registers.l;
            cpu.fetch_and_decode();
        },

        // LD c, a
        inst_state(0x4F, 0) => {
            cpu.registers.c = cpu.registers.a;
            cpu.fetch_and_decode();
        },

        // LD d, b
        inst_state(0x50, 0) => {
            cpu.registers.d = cpu.registers.b;
            cpu.fetch_and_decode();
        },

        // LD d, c
        inst_state(0x51, 0) => {
            cpu.registers.d = cpu.registers.c;
            cpu.fetch_and_decode();
        },

        // LD d, d
        inst_state(0x52, 0) => {
            cpu.registers.d = cpu.registers.d;
            cpu.fetch_and_decode();
        },

        // LD d, e
        inst_state(0x53, 0) => {
            cpu.registers.d = cpu.registers.e;
            cpu.fetch_and_decode();
        },

        // LD d, h
        inst_state(0x54, 0) => {
            cpu.registers.d = cpu.registers.h;
            cpu.fetch_and_decode();
        },

        // LD d, l
        inst_state(0x55, 0) => {
            cpu.registers.d = cpu.registers.l;
            cpu.fetch_and_decode();
        },

        // LD d, a
        inst_state(0x57, 0) => {
            cpu.registers.d = cpu.registers.a;
            cpu.fetch_and_decode();
        },

        // LD e, b
        inst_state(0x58, 0) => {
            cpu.registers.e = cpu.registers.b;
            cpu.fetch_and_decode();
        },

        // LD e, c
        inst_state(0x59, 0) => {
            cpu.registers.e = cpu.registers.c;
            cpu.fetch_and_decode();
        },

        // LD e, d
        inst_state(0x5A, 0) => {
            cpu.registers.e = cpu.registers.d;
            cpu.fetch_and_decode();
        },

        // LD e, e
        inst_state(0x5B, 0) => {
            cpu.registers.e = cpu.registers.e;
            cpu.fetch_and_decode();
        },

        // LD e, h
        inst_state(0x5C, 0) => {
            cpu.registers.e = cpu.registers.h;
            cpu.fetch_and_decode();
        },

        // LD e, l
        inst_state(0x5D, 0) => {
            cpu.registers.e = cpu.registers.l;
            cpu.fetch_and_decode();
        },

        // LD e, a
        inst_state(0x5F, 0) => {
            cpu.registers.e = cpu.registers.a;
            cpu.fetch_and_decode();
        },

        // LD h, b
        inst_state(0x60, 0) => {
            cpu.registers.h = cpu.registers.b;
            cpu.fetch_and_decode();
        },

        // LD h, c
        inst_state(0x61, 0) => {
            cpu.registers.h = cpu.registers.c;
            cpu.fetch_and_decode();
        },

        // LD h, d
        inst_state(0x62, 0) => {
            cpu.registers.h = cpu.registers.d;
            cpu.fetch_and_decode();
        },

        // LD h, e
        inst_state(0x63, 0) => {
            cpu.registers.h = cpu.registers.e;
            cpu.fetch_and_decode();
        },

        // LD h, h
        inst_state(0x64, 0) => {
            cpu.registers.h = cpu.registers.h;
            cpu.fetch_and_decode();
        },

        // LD h, l
        inst_state(0x65, 0) => {
            cpu.registers.h = cpu.registers.l;
            cpu.fetch_and_decode();
        },

        // LD h, a
        inst_state(0x67, 0) => {
            cpu.registers.h = cpu.registers.a;
            cpu.fetch_and_decode();
        },

        // LD l, b
        inst_state(0x68, 0) => {
            cpu.registers.l = cpu.registers.b;
            cpu.fetch_and_decode();
        },

        // LD l, c
        inst_state(0x69, 0) => {
            cpu.registers.l = cpu.registers.c;
            cpu.fetch_and_decode();
        },

        // LD l, d
        inst_state(0x6A, 0) => {
            cpu.registers.l = cpu.registers.d;
            cpu.fetch_and_decode();
        },

        // LD l, e
        inst_state(0x6B, 0) => {
            cpu.registers.l = cpu.registers.e;
            cpu.fetch_and_decode();
        },

        // LD l, h
        inst_state(0x6C, 0) => {
            cpu.registers.l = cpu.registers.h;
            cpu.fetch_and_decode();
        },

        // LD l, l
        inst_state(0x6D, 0) => {
            cpu.registers.l = cpu.registers.l;
            cpu.fetch_and_decode();
        },

        // LD l, a
        inst_state(0x6F, 0) => {
            cpu.registers.l = cpu.registers.a;
            cpu.fetch_and_decode();
        },

        // LD a, b
        inst_state(0x78, 0) => {
            cpu.registers.a = cpu.registers.b;
            cpu.fetch_and_decode();
        },

        // LD a, c
        inst_state(0x79, 0) => {
            cpu.registers.a = cpu.registers.c;
            cpu.fetch_and_decode();
        },

        // LD a, d
        inst_state(0x7A, 0) => {
            cpu.registers.a = cpu.registers.d;
            cpu.fetch_and_decode();
        },

        // LD a, e
        inst_state(0x7B, 0) => {
            cpu.registers.a = cpu.registers.e;
            cpu.fetch_and_decode();
        },

        // LD a, h
        inst_state(0x7C, 0) => {
            cpu.registers.a = cpu.registers.h;
            cpu.fetch_and_decode();
        },

        // LD a, l
        inst_state(0x7D, 0) => {
            cpu.registers.a = cpu.registers.l;
            cpu.fetch_and_decode();
        },

        // LD a, a
        inst_state(0x7F, 0) => {
            cpu.registers.a = cpu.registers.a;
            cpu.fetch_and_decode();
        },

        // LD (HL), imm8
        inst_state(0x36, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x36, 1) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0x36, 2) => {
            cpu.fetch_and_decode();
        },

        // LD A, (BC)
        inst_state(0x0A, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.bc());
            cpu.state.cycle += 1;
        },
        inst_state(0x0A, 1) => {
            cpu.registers.a = cpu.z;
            cpu.fetch_and_decode();
        },
        // LD A, (DE)
        inst_state(0x1A, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.de());
            cpu.state.cycle += 1;
        },
        inst_state(0x1A, 1) => {
            cpu.registers.a = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD (BC), A
        inst_state(0x02, 0) => {
            cpu.mem_write(cpu.registers.bc(), cpu.registers.a);
            cpu.state.cycle += 1;
        },
        inst_state(0x02, 1) => {
            cpu.fetch_and_decode();
        },

        // LD (DE), A
        inst_state(0x12, 0) => {
            cpu.mem_write(cpu.registers.de(), cpu.registers.a);
            cpu.state.cycle += 1;
        },
        inst_state(0x12, 1) => {
            cpu.fetch_and_decode();
        },

        // LD A, (nn)
        inst_state(0xFA, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xFA, 1) => {
            cpu.w = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xFA, 2) => {
            cpu.z = cpu.mem_read(cpu.wz());
            cpu.state.cycle += 1;
        },
        inst_state(0xFA, 3) => {
            cpu.registers.a = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD (nn), A
        inst_state(0xEA, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xEA, 1) => {
            cpu.w = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xEA, 2) => {
            cpu.mem_write(cpu.wz(), cpu.registers.a);
            cpu.state.cycle += 1;
        },
        inst_state(0xEA, 3) => {
            cpu.fetch_and_decode();
        },

        // LDH A, (C)
        inst_state(0xF2, 0) => {
            cpu.z = cpu.mem_read(pair(0xFF, cpu.registers.c));
            cpu.state.cycle += 1;
        },
        inst_state(0xF2, 1) => {
            cpu.registers.a = cpu.z;
            cpu.fetch_and_decode();
        },

        // LDH (C), A
        inst_state(0xE2, 0) => {
            cpu.mem_write(pair(0xFF, cpu.registers.c), cpu.registers.a);
            cpu.state.cycle += 1;
        },
        inst_state(0xE2, 1) => {
            cpu.fetch_and_decode();
        },

        // LDH A, (n)
        inst_state(0xF0, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xF0, 1) => {
            cpu.z = cpu.mem_read(pair(0xFF, cpu.z));
            cpu.state.cycle += 1;
        },
        inst_state(0xF0, 2) => {
            cpu.registers.a = cpu.z;
            cpu.fetch_and_decode();
        },

        // LDH (n), A
        inst_state(0xE0, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xE0, 1) => {
            cpu.mem_write(pair(0xFF, cpu.z), cpu.registers.a);
            cpu.state.cycle += 1;
        },
        inst_state(0xE0, 2) => {
            cpu.fetch_and_decode();
        },

        // LD A, (HL-)
        inst_state(0x3A, 0) => {
            const hl = cpu.registers.hl();
            cpu.z = cpu.mem_read(hl);
            cpu.registers.sethl(hl -% 1);
            cpu.state.cycle += 1;
        },
        inst_state(0x3A, 1) => {
            cpu.registers.a = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD (HL-), A
        inst_state(0x32, 0) => {
            const hl = cpu.registers.hl();
            cpu.mem_write(hl, cpu.registers.a);
            cpu.registers.sethl(hl -% 1);
            cpu.state.cycle += 1;
        },
        inst_state(0x32, 1) => {
            cpu.fetch_and_decode();
        },

        // LD A, (HL+)
        inst_state(0x2A, 0) => {
            const hl = cpu.registers.hl();
            cpu.z = cpu.mem_read(hl);
            cpu.registers.sethl(hl +% 1);
            cpu.state.cycle += 1;
        },
        inst_state(0x2A, 1) => {
            cpu.registers.a = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD (HL+), A
        inst_state(0x22, 0) => {
            const hl = cpu.registers.hl();
            cpu.mem_write(hl, cpu.registers.a);
            cpu.registers.sethl(hl +% 1);
            cpu.state.cycle += 1;
        },
        inst_state(0x22, 1) => {
            cpu.fetch_and_decode();
        },

        // LD (nn), SP
        inst_state(0x08, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x08, 1) => {
            cpu.w = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x08, 2) => {
            cpu.mem_write(cpu.wz(), lsb(cpu.registers.sp));
            cpu.setwz(cpu.wz() +% 1);
            cpu.state.cycle += 1;
        },
        inst_state(0x08, 3) => {
            cpu.mem_write(cpu.wz(), msb(cpu.registers.sp));
            cpu.state.cycle += 1;
        },
        inst_state(0x08, 4) => {
            cpu.fetch_and_decode();
        },

        // LD SP, HL
        inst_state(0xF9, 0) => {
            cpu.registers.sp = cpu.registers.hl();
            cpu.state.cycle += 1;
        },
        inst_state(0xF9, 1) => {
            cpu.fetch_and_decode();
        },

        // LD HL, SP+e
        inst_state(0xF8, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xF8, 1) => {
            const lsb_sp = lsb(cpu.registers.sp);
            const hc = half_carry_add(lsb_sp, cpu.z);
            _, const carry = @addWithOverflow(lsb_sp, cpu.z);

            cpu.registers.flags.z = false;
            cpu.registers.flags.n = false;
            cpu.registers.flags.h = hc == 1;
            cpu.registers.flags.c = carry == 1;

            cpu.state.cycle += 1;
        },
        inst_state(0xF8, 2) => {
            cpu.registers.sethl(add_signed(cpu.registers.sp, cpu.z));

            cpu.fetch_and_decode();
        },

        // LD BC, imm16
        inst_state(0x01, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x01, 1) => {
            cpu.w = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x01, 2) => {
            cpu.registers.setbc(cpu.wz());
            cpu.fetch_and_decode();
        },

        // LD DE, imm16
        inst_state(0x11, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x11, 1) => {
            cpu.w = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x11, 2) => {
            cpu.registers.setde(cpu.wz());
            cpu.fetch_and_decode();
        },

        // LD HL, imm16
        inst_state(0x21, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x21, 1) => {
            cpu.w = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x21, 2) => {
            cpu.registers.sethl(cpu.wz());
            cpu.fetch_and_decode();
        },

        // LD SP, imm16
        inst_state(0x31, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x31, 1) => {
            cpu.w = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x31, 2) => {
            cpu.registers.sp = cpu.wz();
            cpu.fetch_and_decode();
        },

        // LD (HL), b
        inst_state(0x70, 0) => {
            cpu.mem_write(cpu.registers.hl(), cpu.registers.b);
            cpu.state.cycle += 1;
        },
        inst_state(0x70, 1) => {
            cpu.fetch_and_decode();
        },

        // LD (HL), c
        inst_state(0x71, 0) => {
            cpu.mem_write(cpu.registers.hl(), cpu.registers.c);
            cpu.state.cycle += 1;
        },
        inst_state(0x71, 1) => {
            cpu.fetch_and_decode();
        },

        // LD (HL), d
        inst_state(0x72, 0) => {
            cpu.mem_write(cpu.registers.hl(), cpu.registers.d);
            cpu.state.cycle += 1;
        },
        inst_state(0x72, 1) => {
            cpu.fetch_and_decode();
        },

        // LD (HL), e
        inst_state(0x73, 0) => {
            cpu.mem_write(cpu.registers.hl(), cpu.registers.e);
            cpu.state.cycle += 1;
        },
        inst_state(0x73, 1) => {
            cpu.fetch_and_decode();
        },

        // LD (HL), h
        inst_state(0x74, 0) => {
            cpu.mem_write(cpu.registers.hl(), cpu.registers.h);
            cpu.state.cycle += 1;
        },
        inst_state(0x74, 1) => {
            cpu.fetch_and_decode();
        },

        // LD (HL), l
        inst_state(0x75, 0) => {
            cpu.mem_write(cpu.registers.hl(), cpu.registers.l);
            cpu.state.cycle += 1;
        },
        inst_state(0x75, 1) => {
            cpu.fetch_and_decode();
        },

        // LD (HL), a
        inst_state(0x77, 0) => {
            cpu.mem_write(cpu.registers.hl(), cpu.registers.a);
            cpu.state.cycle += 1;
        },
        inst_state(0x77, 1) => {
            cpu.fetch_and_decode();
        },

        // LD b, (HL)
        inst_state(0x46, 0) => {
            cpu.z = cpu.mem_read(pair(cpu.registers.h, cpu.registers.l));
            cpu.state.cycle += 1;
        },
        inst_state(0x46, 1) => {
            cpu.registers.b = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD c, (HL)
        inst_state(0x4E, 0) => {
            cpu.z = cpu.mem_read(pair(cpu.registers.h, cpu.registers.l));
            cpu.state.cycle += 1;
        },
        inst_state(0x4E, 1) => {
            cpu.registers.c = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD d, (HL)
        inst_state(0x56, 0) => {
            cpu.z = cpu.mem_read(pair(cpu.registers.h, cpu.registers.l));
            cpu.state.cycle += 1;
        },
        inst_state(0x56, 1) => {
            cpu.registers.d = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD e, (HL)
        inst_state(0x5E, 0) => {
            cpu.z = cpu.mem_read(pair(cpu.registers.h, cpu.registers.l));
            cpu.state.cycle += 1;
        },
        inst_state(0x5E, 1) => {
            cpu.registers.e = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD h, (HL)
        inst_state(0x66, 0) => {
            cpu.z = cpu.mem_read(pair(cpu.registers.h, cpu.registers.l));
            cpu.state.cycle += 1;
        },
        inst_state(0x66, 1) => {
            cpu.registers.h = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD l, (HL)
        inst_state(0x6E, 0) => {
            cpu.z = cpu.mem_read(pair(cpu.registers.h, cpu.registers.l));
            cpu.state.cycle += 1;
        },
        inst_state(0x6E, 1) => {
            cpu.registers.l = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD a, (HL)
        inst_state(0x7E, 0) => {
            cpu.z = cpu.mem_read(pair(cpu.registers.h, cpu.registers.l));
            cpu.state.cycle += 1;
        },
        inst_state(0x7E, 1) => {
            cpu.registers.a = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD b, imm8
        inst_state(0x06, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x06, 1) => {
            cpu.registers.b = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD c, imm8
        inst_state(0x0E, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x0E, 1) => {
            cpu.registers.c = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD d, imm8
        inst_state(0x16, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x16, 1) => {
            cpu.registers.d = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD e, imm8
        inst_state(0x1E, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x1E, 1) => {
            cpu.registers.e = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD h, imm8
        inst_state(0x26, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x26, 1) => {
            cpu.registers.h = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD l, imm8
        inst_state(0x2E, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x2E, 1) => {
            cpu.registers.l = cpu.z;
            cpu.fetch_and_decode();
        },

        // LD a, imm8
        inst_state(0x3E, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0x3E, 1) => {
            cpu.registers.a = cpu.z;
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

        // ADD a, b
        inst_state(0x80, 0) => {
            cpu.add(cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // ADD a, c
        inst_state(0x81, 0) => {
            cpu.add(cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // ADD a, d
        inst_state(0x82, 0) => {
            cpu.add(cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // ADD a, e
        inst_state(0x83, 0) => {
            cpu.add(cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // ADD a, h
        inst_state(0x84, 0) => {
            cpu.add(cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // ADD a, l
        inst_state(0x85, 0) => {
            cpu.add(cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // ADD a, a
        inst_state(0x87, 0) => {
            cpu.add(cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // ADD (HL)
        inst_state(0x86, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x86, 1) => {
            cpu.add(cpu.z);
            cpu.fetch_and_decode();
        },

        // ADD imm8
        inst_state(0xC6, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xC6, 1) => {
            cpu.add(cpu.z);
            cpu.fetch_and_decode();
        },

        // ADC a, b
        inst_state(0x88, 0) => {
            cpu.adc(cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // ADC a, c
        inst_state(0x89, 0) => {
            cpu.adc(cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // ADC a, d
        inst_state(0x8A, 0) => {
            cpu.adc(cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // ADC a, e
        inst_state(0x8B, 0) => {
            cpu.adc(cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // ADC a, h
        inst_state(0x8C, 0) => {
            cpu.adc(cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // ADC a, l
        inst_state(0x8D, 0) => {
            cpu.adc(cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // ADC a, a
        inst_state(0x8F, 0) => {
            cpu.adc(cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // ADC (HL)
        inst_state(0x8E, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x8E, 1) => {
            cpu.adc(cpu.z);
            cpu.fetch_and_decode();
        },

        // ADC imm8
        inst_state(0xCE, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xCE, 1) => {
            cpu.adc(cpu.z);
            cpu.fetch_and_decode();
        },

        // SUB a, b
        inst_state(0x90, 0) => {
            cpu.sub(cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // SUB a, c
        inst_state(0x91, 0) => {
            cpu.sub(cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // SUB a, d
        inst_state(0x92, 0) => {
            cpu.sub(cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // SUB a, e
        inst_state(0x93, 0) => {
            cpu.sub(cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // SUB a, h
        inst_state(0x94, 0) => {
            cpu.sub(cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // SUB a, l
        inst_state(0x95, 0) => {
            cpu.sub(cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // SUB a, a
        inst_state(0x97, 0) => {
            cpu.sub(cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // SUB (HL)
        inst_state(0x96, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x96, 1) => {
            cpu.sub(cpu.z);
            cpu.fetch_and_decode();
        },

        // SUB imm8
        inst_state(0xD6, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xD6, 1) => {
            cpu.sub(cpu.z);
            cpu.fetch_and_decode();
        },

        // SBC a, b
        inst_state(0x98, 0) => {
            cpu.sbc(cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // SBC a, c
        inst_state(0x99, 0) => {
            cpu.sbc(cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // SBC a, d
        inst_state(0x9A, 0) => {
            cpu.sbc(cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // SBC a, e
        inst_state(0x9B, 0) => {
            cpu.sbc(cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // SBC a, h
        inst_state(0x9C, 0) => {
            cpu.sbc(cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // SBC a, l
        inst_state(0x9D, 0) => {
            cpu.sbc(cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // SBC a, a
        inst_state(0x9F, 0) => {
            cpu.sbc(cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // SBC (HL)
        inst_state(0x9E, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x9E, 1) => {
            cpu.sbc(cpu.z);
            cpu.fetch_and_decode();
        },

        // SBC imm8
        inst_state(0xDE, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xDE, 1) => {
            cpu.sbc(cpu.z);
            cpu.fetch_and_decode();
        },

        // CP b
        inst_state(0xB8, 0) => {
            cpu.cp(cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // CP c
        inst_state(0xB9, 0) => {
            cpu.cp(cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // CP d
        inst_state(0xBA, 0) => {
            cpu.cp(cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // CP e
        inst_state(0xBB, 0) => {
            cpu.cp(cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // CP h
        inst_state(0xBC, 0) => {
            cpu.cp(cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // CP l
        inst_state(0xBD, 0) => {
            cpu.cp(cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // CP a
        inst_state(0xBF, 0) => {
            cpu.cp(cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // CP (HL)
        inst_state(0xBE, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0xBE, 1) => {
            cpu.cp(cpu.z);
            cpu.fetch_and_decode();
        },

        // CP imm8
        inst_state(0xFE, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xFE, 1) => {
            cpu.cp(cpu.z);
            cpu.fetch_and_decode();
        },

        // INC (HL)
        inst_state(0x34, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x34, 1) => {
            cpu.inc(&cpu.z);
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0x34, 2) => {
            cpu.fetch_and_decode();
        },

        // INC b
        inst_state(0x04, 0) => {
            cpu.inc(&cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // INC d
        inst_state(0x14, 0) => {
            cpu.inc(&cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // INC h
        inst_state(0x24, 0) => {
            cpu.inc(&cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // INC c
        inst_state(0x0C, 0) => {
            cpu.inc(&cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // INC e
        inst_state(0x1C, 0) => {
            cpu.inc(&cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // INC l
        inst_state(0x2C, 0) => {
            cpu.inc(&cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // INC a
        inst_state(0x3C, 0) => {
            cpu.inc(&cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // DEC b
        inst_state(0x05, 0) => {
            cpu.dec(&cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // DEC d
        inst_state(0x15, 0) => {
            cpu.dec(&cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // DEC h
        inst_state(0x25, 0) => {
            cpu.dec(&cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // DEC c
        inst_state(0x0D, 0) => {
            cpu.dec(&cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // DEC e
        inst_state(0x1D, 0) => {
            cpu.dec(&cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // DEC l
        inst_state(0x2D, 0) => {
            cpu.dec(&cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // DEC a
        inst_state(0x3D, 0) => {
            cpu.dec(&cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // DEC (HL)
        inst_state(0x35, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x35, 1) => {
            cpu.dec(&cpu.z);
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0x35, 2) => {
            cpu.fetch_and_decode();
        },

        // AND a, b
        inst_state(0xA0, 0) => {
            cpu.@"and"(cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // AND a, c
        inst_state(0xA1, 0) => {
            cpu.@"and"(cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // AND a, d
        inst_state(0xA2, 0) => {
            cpu.@"and"(cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // AND a, e
        inst_state(0xA3, 0) => {
            cpu.@"and"(cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // AND a, h
        inst_state(0xA4, 0) => {
            cpu.@"and"(cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // AND a, l
        inst_state(0xA5, 0) => {
            cpu.@"and"(cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // AND a, a
        inst_state(0xA7, 0) => {
            cpu.@"and"(cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // AND (HL)
        inst_state(0xA6, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0xA6, 1) => {
            cpu.@"and"(cpu.z);
            cpu.fetch_and_decode();
        },

        // AND imm8
        inst_state(0xE6, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xE6, 1) => {
            cpu.@"and"(cpu.z);
            cpu.fetch_and_decode();
        },

        // OR a, b
        inst_state(0xB0, 0) => {
            cpu.@"or"(cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // OR a, c
        inst_state(0xB1, 0) => {
            cpu.@"or"(cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // OR a, d
        inst_state(0xB2, 0) => {
            cpu.@"or"(cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // OR a, e
        inst_state(0xB3, 0) => {
            cpu.@"or"(cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // OR a, h
        inst_state(0xB4, 0) => {
            cpu.@"or"(cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // OR a, l
        inst_state(0xB5, 0) => {
            cpu.@"or"(cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // OR a, a
        inst_state(0xB7, 0) => {
            cpu.@"or"(cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // OR (HL)
        inst_state(0xB6, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0xB6, 1) => {
            cpu.@"or"(cpu.z);
            cpu.fetch_and_decode();
        },

        // OR imm8
        inst_state(0xF6, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xF6, 1) => {
            cpu.@"or"(cpu.z);
            cpu.fetch_and_decode();
        },

        // XOR a, b
        inst_state(0xA8, 0) => {
            cpu.xor(cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // XOR a, c
        inst_state(0xA9, 0) => {
            cpu.xor(cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // XOR a, d
        inst_state(0xAA, 0) => {
            cpu.xor(cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // XOR a, e
        inst_state(0xAB, 0) => {
            cpu.xor(cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // XOR a, h
        inst_state(0xAC, 0) => {
            cpu.xor(cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // XOR a, l
        inst_state(0xAD, 0) => {
            cpu.xor(cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // XOR a, a
        inst_state(0xAF, 0) => {
            cpu.xor(cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // XOR (HL)
        inst_state(0xAE, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0xAE, 1) => {
            cpu.xor(cpu.z);
            cpu.fetch_and_decode();
        },

        // XOR imm8
        inst_state(0xEE, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xEE, 1) => {
            cpu.xor(cpu.z);
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

        // ADD SP, e
        inst_state(0xE8, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xE8, 1) => {
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
        inst_state(0xE8, 2) => {
            cpu.state.cycle += 1;
        },
        inst_state(0xE8, 3) => {
            cpu.registers.sp = cpu.wz();
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
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xC3, 1) => {
            cpu.w = cpu.fetch_next();
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
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xC2, 1) => {
            cpu.w = cpu.fetch_next();
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
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xD2, 1) => {
            cpu.w = cpu.fetch_next();
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
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xCA, 1) => {
            cpu.w = cpu.fetch_next();
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
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xDA, 1) => {
            cpu.w = cpu.fetch_next();
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
            cpu.z = cpu.fetch_next();
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
            cpu.z = cpu.fetch_next();

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
            cpu.z = cpu.fetch_next();

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
            cpu.z = cpu.fetch_next();

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
            cpu.z = cpu.fetch_next();

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
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xCD, 1) => {
            cpu.w = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xCD, 2) => {
            cpu.registers.sp -%= 1;
            cpu.state.cycle += 1;
        },
        inst_state(0xCD, 3) => {
            cpu.mem_write(cpu.registers.sp, msb(cpu.registers.pc));
            cpu.registers.sp -%= 1;
            cpu.state.cycle += 1;
        },
        inst_state(0xCD, 4) => {
            cpu.mem_write(cpu.registers.sp, lsb(cpu.registers.pc));
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xCD, 5) => {
            cpu.fetch_and_decode();
        },

        // CALL NZ, imm16
        inst_state(0xC4, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xC4, 1) => {
            cpu.w = cpu.fetch_next();
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
            cpu.mem_write(cpu.registers.sp, msb(cpu.registers.pc));
            cpu.registers.sp -%= 1;
            cpu.state.cycle += 1;
        },
        inst_state(0xC4, 4) => {
            cpu.mem_write(cpu.registers.sp, lsb(cpu.registers.pc));
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xC4, 5) => {
            cpu.fetch_and_decode();
        },

        // CALL NC, imm16
        inst_state(0xD4, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xD4, 1) => {
            cpu.w = cpu.fetch_next();
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
            cpu.mem_write(cpu.registers.sp, msb(cpu.registers.pc));
            cpu.registers.sp -%= 1;
            cpu.state.cycle += 1;
        },
        inst_state(0xD4, 4) => {
            cpu.mem_write(cpu.registers.sp, lsb(cpu.registers.pc));
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xD4, 5) => {
            cpu.fetch_and_decode();
        },

        // CALL Z, imm16
        inst_state(0xCC, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xCC, 1) => {
            cpu.w = cpu.fetch_next();
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
            cpu.mem_write(cpu.registers.sp, msb(cpu.registers.pc));
            cpu.registers.sp -%= 1;
            cpu.state.cycle += 1;
        },
        inst_state(0xCC, 4) => {
            cpu.mem_write(cpu.registers.sp, lsb(cpu.registers.pc));
            cpu.registers.pc = cpu.wz();
            cpu.state.cycle += 1;
        },
        inst_state(0xCC, 5) => {
            cpu.fetch_and_decode();
        },

        // CALL C, imm16
        inst_state(0xDC, 0) => {
            cpu.z = cpu.fetch_next();
            cpu.state.cycle += 1;
        },
        inst_state(0xDC, 1) => {
            cpu.w = cpu.fetch_next();
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
            cpu.mem_write(cpu.registers.sp, msb(cpu.registers.pc));
            cpu.registers.sp -%= 1;
            cpu.state.cycle += 1;
        },
        inst_state(0xDC, 4) => {
            cpu.mem_write(cpu.registers.sp, lsb(cpu.registers.pc));
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
            cpu.ime = true;
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
}

fn decode_cb(cpu: *SM83) void {
    switch (@as(u16, cpu.state.inst) << 3 | cpu.state.cycle) {
        // RLC b
        inst_state(0x00, 0) => {
            cpu.rlc(&cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // RLC c
        inst_state(0x01, 0) => {
            cpu.rlc(&cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // RLC d
        inst_state(0x02, 0) => {
            cpu.rlc(&cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // RLC e
        inst_state(0x03, 0) => {
            cpu.rlc(&cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // RLC h
        inst_state(0x04, 0) => {
            cpu.rlc(&cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // RLC l
        inst_state(0x05, 0) => {
            cpu.rlc(&cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // rlc, (HL)
        inst_state(0x06, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x06, 1) => {
            cpu.rlc(&cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0x06, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // RLC a
        inst_state(0x07, 0) => {
            cpu.rlc(&cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // RRC b
        inst_state(0x08, 0) => {
            cpu.rrc(&cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // RRC c
        inst_state(0x09, 0) => {
            cpu.rrc(&cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // RRC d
        inst_state(0x0A, 0) => {
            cpu.rrc(&cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // RRC e
        inst_state(0x0B, 0) => {
            cpu.rrc(&cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // RRC h
        inst_state(0x0C, 0) => {
            cpu.rrc(&cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // RRC l
        inst_state(0x0D, 0) => {
            cpu.rrc(&cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // rrc, (HL)
        inst_state(0x0E, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x0E, 1) => {
            cpu.rrc(&cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0x0E, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // RRC a
        inst_state(0x0F, 0) => {
            cpu.rrc(&cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // RL b
        inst_state(0x10, 0) => {
            cpu.rl(&cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // RL c
        inst_state(0x11, 0) => {
            cpu.rl(&cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // RL d
        inst_state(0x12, 0) => {
            cpu.rl(&cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // RL e
        inst_state(0x13, 0) => {
            cpu.rl(&cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // RL h
        inst_state(0x14, 0) => {
            cpu.rl(&cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // RL l
        inst_state(0x15, 0) => {
            cpu.rl(&cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // rl, (HL)
        inst_state(0x16, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x16, 1) => {
            cpu.rl(&cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0x16, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // RL a
        inst_state(0x17, 0) => {
            cpu.rl(&cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // RR b
        inst_state(0x18, 0) => {
            cpu.rr(&cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // RR c
        inst_state(0x19, 0) => {
            cpu.rr(&cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // RR d
        inst_state(0x1A, 0) => {
            cpu.rr(&cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // RR e
        inst_state(0x1B, 0) => {
            cpu.rr(&cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // RR h
        inst_state(0x1C, 0) => {
            cpu.rr(&cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // RR l
        inst_state(0x1D, 0) => {
            cpu.rr(&cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // rr, (HL)
        inst_state(0x1E, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x1E, 1) => {
            cpu.rr(&cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0x1E, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // RR a
        inst_state(0x1F, 0) => {
            cpu.rr(&cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // SLA b
        inst_state(0x20, 0) => {
            cpu.sla(&cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // SLA c
        inst_state(0x21, 0) => {
            cpu.sla(&cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // SLA d
        inst_state(0x22, 0) => {
            cpu.sla(&cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // SLA e
        inst_state(0x23, 0) => {
            cpu.sla(&cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // SLA h
        inst_state(0x24, 0) => {
            cpu.sla(&cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // SLA l
        inst_state(0x25, 0) => {
            cpu.sla(&cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // sla, (HL)
        inst_state(0x26, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x26, 1) => {
            cpu.sla(&cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0x26, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // SLA a
        inst_state(0x27, 0) => {
            cpu.sla(&cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // SRA b
        inst_state(0x28, 0) => {
            cpu.sra(&cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // SRA c
        inst_state(0x29, 0) => {
            cpu.sra(&cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // SRA d
        inst_state(0x2A, 0) => {
            cpu.sra(&cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // SRA e
        inst_state(0x2B, 0) => {
            cpu.sra(&cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // SRA h
        inst_state(0x2C, 0) => {
            cpu.sra(&cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // SRA l
        inst_state(0x2D, 0) => {
            cpu.sra(&cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // sra, (HL)
        inst_state(0x2E, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x2E, 1) => {
            cpu.sra(&cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0x2E, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // SRA a
        inst_state(0x2F, 0) => {
            cpu.sra(&cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // SWAP b
        inst_state(0x30, 0) => {
            cpu.swap(&cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // SWAP c
        inst_state(0x31, 0) => {
            cpu.swap(&cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // SWAP d
        inst_state(0x32, 0) => {
            cpu.swap(&cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // SWAP e
        inst_state(0x33, 0) => {
            cpu.swap(&cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // SWAP h
        inst_state(0x34, 0) => {
            cpu.swap(&cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // SWAP l
        inst_state(0x35, 0) => {
            cpu.swap(&cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // swap, (HL)
        inst_state(0x36, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x36, 1) => {
            cpu.swap(&cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0x36, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // SWAP a
        inst_state(0x37, 0) => {
            cpu.swap(&cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // SRL b
        inst_state(0x38, 0) => {
            cpu.srl(&cpu.registers.b);
            cpu.fetch_and_decode();
        },

        // SRL c
        inst_state(0x39, 0) => {
            cpu.srl(&cpu.registers.c);
            cpu.fetch_and_decode();
        },

        // SRL d
        inst_state(0x3A, 0) => {
            cpu.srl(&cpu.registers.d);
            cpu.fetch_and_decode();
        },

        // SRL e
        inst_state(0x3B, 0) => {
            cpu.srl(&cpu.registers.e);
            cpu.fetch_and_decode();
        },

        // SRL h
        inst_state(0x3C, 0) => {
            cpu.srl(&cpu.registers.h);
            cpu.fetch_and_decode();
        },

        // SRL l
        inst_state(0x3D, 0) => {
            cpu.srl(&cpu.registers.l);
            cpu.fetch_and_decode();
        },

        // SRL, (HL)
        inst_state(0x3E, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x3E, 1) => {
            cpu.srl(&cpu.z);
            cpu.state.cycle += 1;
        },
        inst_state(0x3E, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // SRL a
        inst_state(0x3F, 0) => {
            cpu.srl(&cpu.registers.a);
            cpu.fetch_and_decode();
        },

        // BIT 0, b
        inst_state(0x40, 0) => {
            cpu.bit(cpu.registers.b, 0);
            cpu.fetch_and_decode();
        },

        // BIT 0, c
        inst_state(0x41, 0) => {
            cpu.bit(cpu.registers.c, 0);
            cpu.fetch_and_decode();
        },

        // BIT 0, d
        inst_state(0x42, 0) => {
            cpu.bit(cpu.registers.d, 0);
            cpu.fetch_and_decode();
        },

        // BIT 0, e
        inst_state(0x43, 0) => {
            cpu.bit(cpu.registers.e, 0);
            cpu.fetch_and_decode();
        },

        // BIT 0, h
        inst_state(0x44, 0) => {
            cpu.bit(cpu.registers.h, 0);
            cpu.fetch_and_decode();
        },

        // BIT 0, l
        inst_state(0x45, 0) => {
            cpu.bit(cpu.registers.l, 0);
            cpu.fetch_and_decode();
        },

        // BIT 0, (HL)
        inst_state(0x46, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x46, 1) => {
            cpu.bit(cpu.z, 0);
            cpu.fetch_and_decode();
        },

        // BIT 0, a
        inst_state(0x47, 0) => {
            cpu.bit(cpu.registers.a, 0);
            cpu.fetch_and_decode();
        },

        // BIT 1, b
        inst_state(0x48, 0) => {
            cpu.bit(cpu.registers.b, 1);
            cpu.fetch_and_decode();
        },

        // BIT 1, c
        inst_state(0x49, 0) => {
            cpu.bit(cpu.registers.c, 1);
            cpu.fetch_and_decode();
        },

        // BIT 1, d
        inst_state(0x4A, 0) => {
            cpu.bit(cpu.registers.d, 1);
            cpu.fetch_and_decode();
        },

        // BIT 1, e
        inst_state(0x4B, 0) => {
            cpu.bit(cpu.registers.e, 1);
            cpu.fetch_and_decode();
        },

        // BIT 1, h
        inst_state(0x4C, 0) => {
            cpu.bit(cpu.registers.h, 1);
            cpu.fetch_and_decode();
        },

        // BIT 1, l
        inst_state(0x4D, 0) => {
            cpu.bit(cpu.registers.l, 1);
            cpu.fetch_and_decode();
        },

        // BIT 1, (HL)
        inst_state(0x4E, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x4E, 1) => {
            cpu.bit(cpu.z, 1);
            cpu.fetch_and_decode();
        },

        // BIT 1, a
        inst_state(0x4F, 0) => {
            cpu.bit(cpu.registers.a, 1);
            cpu.fetch_and_decode();
        },

        // BIT 2, b
        inst_state(0x50, 0) => {
            cpu.bit(cpu.registers.b, 2);
            cpu.fetch_and_decode();
        },

        // BIT 2, c
        inst_state(0x51, 0) => {
            cpu.bit(cpu.registers.c, 2);
            cpu.fetch_and_decode();
        },

        // BIT 2, d
        inst_state(0x52, 0) => {
            cpu.bit(cpu.registers.d, 2);
            cpu.fetch_and_decode();
        },

        // BIT 2, e
        inst_state(0x53, 0) => {
            cpu.bit(cpu.registers.e, 2);
            cpu.fetch_and_decode();
        },

        // BIT 2, h
        inst_state(0x54, 0) => {
            cpu.bit(cpu.registers.h, 2);
            cpu.fetch_and_decode();
        },

        // BIT 2, l
        inst_state(0x55, 0) => {
            cpu.bit(cpu.registers.l, 2);
            cpu.fetch_and_decode();
        },

        // BIT 2, (HL)
        inst_state(0x56, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x56, 1) => {
            cpu.bit(cpu.z, 2);
            cpu.fetch_and_decode();
        },

        // BIT 2, a
        inst_state(0x57, 0) => {
            cpu.bit(cpu.registers.a, 2);
            cpu.fetch_and_decode();
        },

        // BIT 3, b
        inst_state(0x58, 0) => {
            cpu.bit(cpu.registers.b, 3);
            cpu.fetch_and_decode();
        },

        // BIT 3, c
        inst_state(0x59, 0) => {
            cpu.bit(cpu.registers.c, 3);
            cpu.fetch_and_decode();
        },

        // BIT 3, d
        inst_state(0x5A, 0) => {
            cpu.bit(cpu.registers.d, 3);
            cpu.fetch_and_decode();
        },

        // BIT 3, e
        inst_state(0x5B, 0) => {
            cpu.bit(cpu.registers.e, 3);
            cpu.fetch_and_decode();
        },

        // BIT 3, h
        inst_state(0x5C, 0) => {
            cpu.bit(cpu.registers.h, 3);
            cpu.fetch_and_decode();
        },

        // BIT 3, l
        inst_state(0x5D, 0) => {
            cpu.bit(cpu.registers.l, 3);
            cpu.fetch_and_decode();
        },

        // BIT 3, (HL)
        inst_state(0x5E, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x5E, 1) => {
            cpu.bit(cpu.z, 3);
            cpu.fetch_and_decode();
        },

        // BIT 3, a
        inst_state(0x5F, 0) => {
            cpu.bit(cpu.registers.a, 3);
            cpu.fetch_and_decode();
        },

        // BIT 4, b
        inst_state(0x60, 0) => {
            cpu.bit(cpu.registers.b, 4);
            cpu.fetch_and_decode();
        },

        // BIT 4, c
        inst_state(0x61, 0) => {
            cpu.bit(cpu.registers.c, 4);
            cpu.fetch_and_decode();
        },

        // BIT 4, d
        inst_state(0x62, 0) => {
            cpu.bit(cpu.registers.d, 4);
            cpu.fetch_and_decode();
        },

        // BIT 4, e
        inst_state(0x63, 0) => {
            cpu.bit(cpu.registers.e, 4);
            cpu.fetch_and_decode();
        },

        // BIT 4, h
        inst_state(0x64, 0) => {
            cpu.bit(cpu.registers.h, 4);
            cpu.fetch_and_decode();
        },

        // BIT 4, l
        inst_state(0x65, 0) => {
            cpu.bit(cpu.registers.l, 4);
            cpu.fetch_and_decode();
        },

        // BIT 4, (HL)
        inst_state(0x66, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x66, 1) => {
            cpu.bit(cpu.z, 4);
            cpu.fetch_and_decode();
        },

        // BIT 4, a
        inst_state(0x67, 0) => {
            cpu.bit(cpu.registers.a, 4);
            cpu.fetch_and_decode();
        },

        // BIT 5, b
        inst_state(0x68, 0) => {
            cpu.bit(cpu.registers.b, 5);
            cpu.fetch_and_decode();
        },

        // BIT 5, c
        inst_state(0x69, 0) => {
            cpu.bit(cpu.registers.c, 5);
            cpu.fetch_and_decode();
        },

        // BIT 5, d
        inst_state(0x6A, 0) => {
            cpu.bit(cpu.registers.d, 5);
            cpu.fetch_and_decode();
        },

        // BIT 5, e
        inst_state(0x6B, 0) => {
            cpu.bit(cpu.registers.e, 5);
            cpu.fetch_and_decode();
        },

        // BIT 5, h
        inst_state(0x6C, 0) => {
            cpu.bit(cpu.registers.h, 5);
            cpu.fetch_and_decode();
        },

        // BIT 5, l
        inst_state(0x6D, 0) => {
            cpu.bit(cpu.registers.l, 5);
            cpu.fetch_and_decode();
        },

        // BIT 5, (HL)
        inst_state(0x6E, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x6E, 1) => {
            cpu.bit(cpu.z, 5);
            cpu.fetch_and_decode();
        },

        // BIT 5, a
        inst_state(0x6F, 0) => {
            cpu.bit(cpu.registers.a, 5);
            cpu.fetch_and_decode();
        },

        // BIT 6, b
        inst_state(0x70, 0) => {
            cpu.bit(cpu.registers.b, 6);
            cpu.fetch_and_decode();
        },

        // BIT 6, c
        inst_state(0x71, 0) => {
            cpu.bit(cpu.registers.c, 6);
            cpu.fetch_and_decode();
        },

        // BIT 6, d
        inst_state(0x72, 0) => {
            cpu.bit(cpu.registers.d, 6);
            cpu.fetch_and_decode();
        },

        // BIT 6, e
        inst_state(0x73, 0) => {
            cpu.bit(cpu.registers.e, 6);
            cpu.fetch_and_decode();
        },

        // BIT 6, h
        inst_state(0x74, 0) => {
            cpu.bit(cpu.registers.h, 6);
            cpu.fetch_and_decode();
        },

        // BIT 6, l
        inst_state(0x75, 0) => {
            cpu.bit(cpu.registers.l, 6);
            cpu.fetch_and_decode();
        },

        // BIT 6, (HL)
        inst_state(0x76, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x76, 1) => {
            cpu.bit(cpu.z, 6);
            cpu.fetch_and_decode();
        },

        // BIT 6, a
        inst_state(0x77, 0) => {
            cpu.bit(cpu.registers.a, 6);
            cpu.fetch_and_decode();
        },

        // BIT 7, b
        inst_state(0x78, 0) => {
            cpu.bit(cpu.registers.b, 7);
            cpu.fetch_and_decode();
        },

        // BIT 7, c
        inst_state(0x79, 0) => {
            cpu.bit(cpu.registers.c, 7);
            cpu.fetch_and_decode();
        },

        // BIT 7, d
        inst_state(0x7A, 0) => {
            cpu.bit(cpu.registers.d, 7);
            cpu.fetch_and_decode();
        },

        // BIT 7, e
        inst_state(0x7B, 0) => {
            cpu.bit(cpu.registers.e, 7);
            cpu.fetch_and_decode();
        },

        // BIT 7, h
        inst_state(0x7C, 0) => {
            cpu.bit(cpu.registers.h, 7);
            cpu.fetch_and_decode();
        },

        // BIT 7, l
        inst_state(0x7D, 0) => {
            cpu.bit(cpu.registers.l, 7);
            cpu.fetch_and_decode();
        },

        // BIT 7, (HL)
        inst_state(0x7E, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x7E, 1) => {
            cpu.bit(cpu.z, 7);
            cpu.fetch_and_decode();
        },

        // BIT 7, a
        inst_state(0x7F, 0) => {
            cpu.bit(cpu.registers.a, 7);
            cpu.fetch_and_decode();
        },

        // res 0, b
        inst_state(0x80, 0) => {
            cpu.res(&cpu.registers.b, 0);
            cpu.fetch_and_decode();
        },

        // res 0, c
        inst_state(0x81, 0) => {
            cpu.res(&cpu.registers.c, 0);
            cpu.fetch_and_decode();
        },

        // res 0, d
        inst_state(0x82, 0) => {
            cpu.res(&cpu.registers.d, 0);
            cpu.fetch_and_decode();
        },

        // res 0, e
        inst_state(0x83, 0) => {
            cpu.res(&cpu.registers.e, 0);
            cpu.fetch_and_decode();
        },

        // res 0, h
        inst_state(0x84, 0) => {
            cpu.res(&cpu.registers.h, 0);
            cpu.fetch_and_decode();
        },

        // res 0, l
        inst_state(0x85, 0) => {
            cpu.res(&cpu.registers.l, 0);
            cpu.fetch_and_decode();
        },

        // res0, (HL)
        inst_state(0x86, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x86, 1) => {
            cpu.res(&cpu.z, 0);
            cpu.state.cycle += 1;
        },
        inst_state(0x86, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // res 0, a
        inst_state(0x87, 0) => {
            cpu.res(&cpu.registers.a, 0);
            cpu.fetch_and_decode();
        },

        // res 1, b
        inst_state(0x88, 0) => {
            cpu.res(&cpu.registers.b, 1);
            cpu.fetch_and_decode();
        },

        // res 1, c
        inst_state(0x89, 0) => {
            cpu.res(&cpu.registers.c, 1);
            cpu.fetch_and_decode();
        },

        // res 1, d
        inst_state(0x8A, 0) => {
            cpu.res(&cpu.registers.d, 1);
            cpu.fetch_and_decode();
        },

        // res 1, e
        inst_state(0x8B, 0) => {
            cpu.res(&cpu.registers.e, 1);
            cpu.fetch_and_decode();
        },

        // res 1, h
        inst_state(0x8C, 0) => {
            cpu.res(&cpu.registers.h, 1);
            cpu.fetch_and_decode();
        },

        // res 1, l
        inst_state(0x8D, 0) => {
            cpu.res(&cpu.registers.l, 1);
            cpu.fetch_and_decode();
        },

        // res1, (HL)
        inst_state(0x8E, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x8E, 1) => {
            cpu.res(&cpu.z, 1);
            cpu.state.cycle += 1;
        },
        inst_state(0x8E, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // res 1, a
        inst_state(0x8F, 0) => {
            cpu.res(&cpu.registers.a, 1);
            cpu.fetch_and_decode();
        },

        // res 2, b
        inst_state(0x90, 0) => {
            cpu.res(&cpu.registers.b, 2);
            cpu.fetch_and_decode();
        },

        // res 2, c
        inst_state(0x91, 0) => {
            cpu.res(&cpu.registers.c, 2);
            cpu.fetch_and_decode();
        },

        // res 2, d
        inst_state(0x92, 0) => {
            cpu.res(&cpu.registers.d, 2);
            cpu.fetch_and_decode();
        },

        // res 2, e
        inst_state(0x93, 0) => {
            cpu.res(&cpu.registers.e, 2);
            cpu.fetch_and_decode();
        },

        // res 2, h
        inst_state(0x94, 0) => {
            cpu.res(&cpu.registers.h, 2);
            cpu.fetch_and_decode();
        },

        // res 2, l
        inst_state(0x95, 0) => {
            cpu.res(&cpu.registers.l, 2);
            cpu.fetch_and_decode();
        },

        // res2, (HL)
        inst_state(0x96, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x96, 1) => {
            cpu.res(&cpu.z, 2);
            cpu.state.cycle += 1;
        },
        inst_state(0x96, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // res 2, a
        inst_state(0x97, 0) => {
            cpu.res(&cpu.registers.a, 2);
            cpu.fetch_and_decode();
        },

        // res 3, b
        inst_state(0x98, 0) => {
            cpu.res(&cpu.registers.b, 3);
            cpu.fetch_and_decode();
        },

        // res 3, c
        inst_state(0x99, 0) => {
            cpu.res(&cpu.registers.c, 3);
            cpu.fetch_and_decode();
        },

        // res 3, d
        inst_state(0x9A, 0) => {
            cpu.res(&cpu.registers.d, 3);
            cpu.fetch_and_decode();
        },

        // res 3, e
        inst_state(0x9B, 0) => {
            cpu.res(&cpu.registers.e, 3);
            cpu.fetch_and_decode();
        },

        // res 3, h
        inst_state(0x9C, 0) => {
            cpu.res(&cpu.registers.h, 3);
            cpu.fetch_and_decode();
        },

        // res 3, l
        inst_state(0x9D, 0) => {
            cpu.res(&cpu.registers.l, 3);
            cpu.fetch_and_decode();
        },

        // res3, (HL)
        inst_state(0x9E, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0x9E, 1) => {
            cpu.res(&cpu.z, 3);
            cpu.state.cycle += 1;
        },
        inst_state(0x9E, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // res 3, a
        inst_state(0x9F, 0) => {
            cpu.res(&cpu.registers.a, 3);
            cpu.fetch_and_decode();
        },

        // res 4, b
        inst_state(0xA0, 0) => {
            cpu.res(&cpu.registers.b, 4);
            cpu.fetch_and_decode();
        },

        // res 4, c
        inst_state(0xA1, 0) => {
            cpu.res(&cpu.registers.c, 4);
            cpu.fetch_and_decode();
        },

        // res 4, d
        inst_state(0xA2, 0) => {
            cpu.res(&cpu.registers.d, 4);
            cpu.fetch_and_decode();
        },

        // res 4, e
        inst_state(0xA3, 0) => {
            cpu.res(&cpu.registers.e, 4);
            cpu.fetch_and_decode();
        },

        // res 4, h
        inst_state(0xA4, 0) => {
            cpu.res(&cpu.registers.h, 4);
            cpu.fetch_and_decode();
        },

        // res 4, l
        inst_state(0xA5, 0) => {
            cpu.res(&cpu.registers.l, 4);
            cpu.fetch_and_decode();
        },

        // res4, (HL)
        inst_state(0xA6, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0xA6, 1) => {
            cpu.res(&cpu.z, 4);
            cpu.state.cycle += 1;
        },
        inst_state(0xA6, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // res 4, a
        inst_state(0xA7, 0) => {
            cpu.res(&cpu.registers.a, 4);
            cpu.fetch_and_decode();
        },

        // res 5, b
        inst_state(0xA8, 0) => {
            cpu.res(&cpu.registers.b, 5);
            cpu.fetch_and_decode();
        },

        // res 5, c
        inst_state(0xA9, 0) => {
            cpu.res(&cpu.registers.c, 5);
            cpu.fetch_and_decode();
        },

        // res 5, d
        inst_state(0xAA, 0) => {
            cpu.res(&cpu.registers.d, 5);
            cpu.fetch_and_decode();
        },

        // res 5, e
        inst_state(0xAB, 0) => {
            cpu.res(&cpu.registers.e, 5);
            cpu.fetch_and_decode();
        },

        // res 5, h
        inst_state(0xAC, 0) => {
            cpu.res(&cpu.registers.h, 5);
            cpu.fetch_and_decode();
        },

        // res 5, l
        inst_state(0xAD, 0) => {
            cpu.res(&cpu.registers.l, 5);
            cpu.fetch_and_decode();
        },

        // res5, (HL)
        inst_state(0xAE, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0xAE, 1) => {
            cpu.res(&cpu.z, 5);
            cpu.state.cycle += 1;
        },
        inst_state(0xAE, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // res 5, a
        inst_state(0xAF, 0) => {
            cpu.res(&cpu.registers.a, 5);
            cpu.fetch_and_decode();
        },

        // res 6, b
        inst_state(0xB0, 0) => {
            cpu.res(&cpu.registers.b, 6);
            cpu.fetch_and_decode();
        },

        // res 6, c
        inst_state(0xB1, 0) => {
            cpu.res(&cpu.registers.c, 6);
            cpu.fetch_and_decode();
        },

        // res 6, d
        inst_state(0xB2, 0) => {
            cpu.res(&cpu.registers.d, 6);
            cpu.fetch_and_decode();
        },

        // res 6, e
        inst_state(0xB3, 0) => {
            cpu.res(&cpu.registers.e, 6);
            cpu.fetch_and_decode();
        },

        // res 6, h
        inst_state(0xB4, 0) => {
            cpu.res(&cpu.registers.h, 6);
            cpu.fetch_and_decode();
        },

        // res 6, l
        inst_state(0xB5, 0) => {
            cpu.res(&cpu.registers.l, 6);
            cpu.fetch_and_decode();
        },

        // res6, (HL)
        inst_state(0xB6, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0xB6, 1) => {
            cpu.res(&cpu.z, 6);
            cpu.state.cycle += 1;
        },
        inst_state(0xB6, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // res 6, a
        inst_state(0xB7, 0) => {
            cpu.res(&cpu.registers.a, 6);
            cpu.fetch_and_decode();
        },

        // res 7, b
        inst_state(0xB8, 0) => {
            cpu.res(&cpu.registers.b, 7);
            cpu.fetch_and_decode();
        },

        // res 7, c
        inst_state(0xB9, 0) => {
            cpu.res(&cpu.registers.c, 7);
            cpu.fetch_and_decode();
        },

        // res 7, d
        inst_state(0xBA, 0) => {
            cpu.res(&cpu.registers.d, 7);
            cpu.fetch_and_decode();
        },

        // res 7, e
        inst_state(0xBB, 0) => {
            cpu.res(&cpu.registers.e, 7);
            cpu.fetch_and_decode();
        },

        // res 7, h
        inst_state(0xBC, 0) => {
            cpu.res(&cpu.registers.h, 7);
            cpu.fetch_and_decode();
        },

        // res 7, l
        inst_state(0xBD, 0) => {
            cpu.res(&cpu.registers.l, 7);
            cpu.fetch_and_decode();
        },

        // res7, (HL)
        inst_state(0xBE, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0xBE, 1) => {
            cpu.res(&cpu.z, 7);
            cpu.state.cycle += 1;
        },
        inst_state(0xBE, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // res 7, a
        inst_state(0xBF, 0) => {
            cpu.res(&cpu.registers.a, 7);
            cpu.fetch_and_decode();
        },

        // set 0, b
        inst_state(0xC0, 0) => {
            cpu.set(&cpu.registers.b, 0);
            cpu.fetch_and_decode();
        },

        // set 0, c
        inst_state(0xC1, 0) => {
            cpu.set(&cpu.registers.c, 0);
            cpu.fetch_and_decode();
        },

        // set 0, d
        inst_state(0xC2, 0) => {
            cpu.set(&cpu.registers.d, 0);
            cpu.fetch_and_decode();
        },

        // set 0, e
        inst_state(0xC3, 0) => {
            cpu.set(&cpu.registers.e, 0);
            cpu.fetch_and_decode();
        },

        // set 0, h
        inst_state(0xC4, 0) => {
            cpu.set(&cpu.registers.h, 0);
            cpu.fetch_and_decode();
        },

        // set 0, l
        inst_state(0xC5, 0) => {
            cpu.set(&cpu.registers.l, 0);
            cpu.fetch_and_decode();
        },

        // set0, (HL)
        inst_state(0xC6, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0xC6, 1) => {
            cpu.set(&cpu.z, 0);
            cpu.state.cycle += 1;
        },
        inst_state(0xC6, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // set 0, a
        inst_state(0xC7, 0) => {
            cpu.set(&cpu.registers.a, 0);
            cpu.fetch_and_decode();
        },

        // set 1, b
        inst_state(0xC8, 0) => {
            cpu.set(&cpu.registers.b, 1);
            cpu.fetch_and_decode();
        },

        // set 1, c
        inst_state(0xC9, 0) => {
            cpu.set(&cpu.registers.c, 1);
            cpu.fetch_and_decode();
        },

        // set 1, d
        inst_state(0xCA, 0) => {
            cpu.set(&cpu.registers.d, 1);
            cpu.fetch_and_decode();
        },

        // set 1, e
        inst_state(0xCB, 0) => {
            cpu.set(&cpu.registers.e, 1);
            cpu.fetch_and_decode();
        },

        // set 1, h
        inst_state(0xCC, 0) => {
            cpu.set(&cpu.registers.h, 1);
            cpu.fetch_and_decode();
        },

        // set 1, l
        inst_state(0xCD, 0) => {
            cpu.set(&cpu.registers.l, 1);
            cpu.fetch_and_decode();
        },

        // set1, (HL)
        inst_state(0xCE, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0xCE, 1) => {
            cpu.set(&cpu.z, 1);
            cpu.state.cycle += 1;
        },
        inst_state(0xCE, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // set 1, a
        inst_state(0xCF, 0) => {
            cpu.set(&cpu.registers.a, 1);
            cpu.fetch_and_decode();
        },

        // set 2, b
        inst_state(0xD0, 0) => {
            cpu.set(&cpu.registers.b, 2);
            cpu.fetch_and_decode();
        },

        // set 2, c
        inst_state(0xD1, 0) => {
            cpu.set(&cpu.registers.c, 2);
            cpu.fetch_and_decode();
        },

        // set 2, d
        inst_state(0xD2, 0) => {
            cpu.set(&cpu.registers.d, 2);
            cpu.fetch_and_decode();
        },

        // set 2, e
        inst_state(0xD3, 0) => {
            cpu.set(&cpu.registers.e, 2);
            cpu.fetch_and_decode();
        },

        // set 2, h
        inst_state(0xD4, 0) => {
            cpu.set(&cpu.registers.h, 2);
            cpu.fetch_and_decode();
        },

        // set 2, l
        inst_state(0xD5, 0) => {
            cpu.set(&cpu.registers.l, 2);
            cpu.fetch_and_decode();
        },

        // set2, (HL)
        inst_state(0xD6, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0xD6, 1) => {
            cpu.set(&cpu.z, 2);
            cpu.state.cycle += 1;
        },
        inst_state(0xD6, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // set 2, a
        inst_state(0xD7, 0) => {
            cpu.set(&cpu.registers.a, 2);
            cpu.fetch_and_decode();
        },

        // set 3, b
        inst_state(0xD8, 0) => {
            cpu.set(&cpu.registers.b, 3);
            cpu.fetch_and_decode();
        },

        // set 3, c
        inst_state(0xD9, 0) => {
            cpu.set(&cpu.registers.c, 3);
            cpu.fetch_and_decode();
        },

        // set 3, d
        inst_state(0xDA, 0) => {
            cpu.set(&cpu.registers.d, 3);
            cpu.fetch_and_decode();
        },

        // set 3, e
        inst_state(0xDB, 0) => {
            cpu.set(&cpu.registers.e, 3);
            cpu.fetch_and_decode();
        },

        // set 3, h
        inst_state(0xDC, 0) => {
            cpu.set(&cpu.registers.h, 3);
            cpu.fetch_and_decode();
        },

        // set 3, l
        inst_state(0xDD, 0) => {
            cpu.set(&cpu.registers.l, 3);
            cpu.fetch_and_decode();
        },

        // set3, (HL)
        inst_state(0xDE, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0xDE, 1) => {
            cpu.set(&cpu.z, 3);
            cpu.state.cycle += 1;
        },
        inst_state(0xDE, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // set 3, a
        inst_state(0xDF, 0) => {
            cpu.set(&cpu.registers.a, 3);
            cpu.fetch_and_decode();
        },

        // set 4, b
        inst_state(0xE0, 0) => {
            cpu.set(&cpu.registers.b, 4);
            cpu.fetch_and_decode();
        },

        // set 4, c
        inst_state(0xE1, 0) => {
            cpu.set(&cpu.registers.c, 4);
            cpu.fetch_and_decode();
        },

        // set 4, d
        inst_state(0xE2, 0) => {
            cpu.set(&cpu.registers.d, 4);
            cpu.fetch_and_decode();
        },

        // set 4, e
        inst_state(0xE3, 0) => {
            cpu.set(&cpu.registers.e, 4);
            cpu.fetch_and_decode();
        },

        // set 4, h
        inst_state(0xE4, 0) => {
            cpu.set(&cpu.registers.h, 4);
            cpu.fetch_and_decode();
        },

        // set 4, l
        inst_state(0xE5, 0) => {
            cpu.set(&cpu.registers.l, 4);
            cpu.fetch_and_decode();
        },

        // set4, (HL)
        inst_state(0xE6, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0xE6, 1) => {
            cpu.set(&cpu.z, 4);
            cpu.state.cycle += 1;
        },
        inst_state(0xE6, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // set 4, a
        inst_state(0xE7, 0) => {
            cpu.set(&cpu.registers.a, 4);
            cpu.fetch_and_decode();
        },

        // set 5, b
        inst_state(0xE8, 0) => {
            cpu.set(&cpu.registers.b, 5);
            cpu.fetch_and_decode();
        },

        // set 5, c
        inst_state(0xE9, 0) => {
            cpu.set(&cpu.registers.c, 5);
            cpu.fetch_and_decode();
        },

        // set 5, d
        inst_state(0xEA, 0) => {
            cpu.set(&cpu.registers.d, 5);
            cpu.fetch_and_decode();
        },

        // set 5, e
        inst_state(0xEB, 0) => {
            cpu.set(&cpu.registers.e, 5);
            cpu.fetch_and_decode();
        },

        // set 5, h
        inst_state(0xEC, 0) => {
            cpu.set(&cpu.registers.h, 5);
            cpu.fetch_and_decode();
        },

        // set 5, l
        inst_state(0xED, 0) => {
            cpu.set(&cpu.registers.l, 5);
            cpu.fetch_and_decode();
        },

        // set5, (HL)
        inst_state(0xEE, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0xEE, 1) => {
            cpu.set(&cpu.z, 5);
            cpu.state.cycle += 1;
        },
        inst_state(0xEE, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // set 5, a
        inst_state(0xEF, 0) => {
            cpu.set(&cpu.registers.a, 5);
            cpu.fetch_and_decode();
        },

        // set 6, b
        inst_state(0xF0, 0) => {
            cpu.set(&cpu.registers.b, 6);
            cpu.fetch_and_decode();
        },

        // set 6, c
        inst_state(0xF1, 0) => {
            cpu.set(&cpu.registers.c, 6);
            cpu.fetch_and_decode();
        },

        // set 6, d
        inst_state(0xF2, 0) => {
            cpu.set(&cpu.registers.d, 6);
            cpu.fetch_and_decode();
        },

        // set 6, e
        inst_state(0xF3, 0) => {
            cpu.set(&cpu.registers.e, 6);
            cpu.fetch_and_decode();
        },

        // set 6, h
        inst_state(0xF4, 0) => {
            cpu.set(&cpu.registers.h, 6);
            cpu.fetch_and_decode();
        },

        // set 6, l
        inst_state(0xF5, 0) => {
            cpu.set(&cpu.registers.l, 6);
            cpu.fetch_and_decode();
        },

        // set6, (HL)
        inst_state(0xF6, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0xF6, 1) => {
            cpu.set(&cpu.z, 6);
            cpu.state.cycle += 1;
        },
        inst_state(0xF6, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // set 6, a
        inst_state(0xF7, 0) => {
            cpu.set(&cpu.registers.a, 6);
            cpu.fetch_and_decode();
        },

        // set 7, b
        inst_state(0xF8, 0) => {
            cpu.set(&cpu.registers.b, 7);
            cpu.fetch_and_decode();
        },

        // set 7, c
        inst_state(0xF9, 0) => {
            cpu.set(&cpu.registers.c, 7);
            cpu.fetch_and_decode();
        },

        // set 7, d
        inst_state(0xFA, 0) => {
            cpu.set(&cpu.registers.d, 7);
            cpu.fetch_and_decode();
        },

        // set 7, e
        inst_state(0xFB, 0) => {
            cpu.set(&cpu.registers.e, 7);
            cpu.fetch_and_decode();
        },

        // set 7, h
        inst_state(0xFC, 0) => {
            cpu.set(&cpu.registers.h, 7);
            cpu.fetch_and_decode();
        },

        // set 7, l
        inst_state(0xFD, 0) => {
            cpu.set(&cpu.registers.l, 7);
            cpu.fetch_and_decode();
        },

        // set7, (HL)
        inst_state(0xFE, 0) => {
            cpu.z = cpu.mem_read(cpu.registers.hl());
            cpu.state.cycle += 1;
        },
        inst_state(0xFE, 1) => {
            cpu.set(&cpu.z, 7);
            cpu.state.cycle += 1;
        },
        inst_state(0xFE, 2) => {
            cpu.mem_write(cpu.registers.hl(), cpu.z);
            cpu.fetch_and_decode();
        },

        // set 7, a
        inst_state(0xFF, 0) => {
            cpu.set(&cpu.registers.a, 7);
            cpu.fetch_and_decode();
        },

        else => unreachable,
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

fn fetch_next(cpu: *SM83) u8 {
    defer cpu.registers.pc +%= 1;
    return cpu.memory[cpu.registers.pc];
}

fn mem_read(cpu: *SM83, addr: u16) u8 {
    return cpu.memory[addr];
}

fn mem_write(cpu: *SM83, addr: u16, data: u8) void {
    cpu.memory[addr] = data;
}

/// Fetches the next instruction opcode and resets the cycle counter.
fn fetch_and_decode(cpu: *SM83) void {
    cpu.state = .{ .inst = cpu.fetch_next(), .cycle = 0, .is_cb_inst = false };
}

fn fetch_and_decode_extended(cpu: *SM83) void {
    cpu.state = .{ .inst = cpu.fetch_next(), .cycle = 0, .is_cb_inst = true };
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

fn rlc(cpu: *SM83, reg: *u8) void {
    reg.*, const carry = @shlWithOverflow(reg.*, 1);
    reg.* |= carry;
    cpu.registers.flags = .{
        .z = reg.* == 0,
        .n = false,
        .h = false,
        .c = carry == 1,
    };
}

fn rrc(cpu: *SM83, reg: *u8) void {
    const carry: u8 = reg.* & 1;
    reg.* = (reg.* >> 1) | (carry << 7);
    cpu.registers.flags = .{
        .z = reg.* == 0,
        .n = false,
        .h = false,
        .c = carry == 1,
    };
}

fn rl(cpu: *SM83, reg: *u8) void {
    reg.*, const carry = @shlWithOverflow(reg.*, 1);
    reg.* |= @intFromBool(cpu.registers.flags.c);
    cpu.registers.flags = .{
        .z = reg.* == 0,
        .n = false,
        .h = false,
        .c = carry == 1,
    };
}

fn rr(cpu: *SM83, reg: *u8) void {
    const carry: u8 = reg.* & 1;
    const old_carry: u8 = @intFromBool(cpu.registers.flags.c);
    reg.* = (reg.* >> 1) | (old_carry << 7);
    cpu.registers.flags = .{
        .z = reg.* == 0,
        .n = false,
        .h = false,
        .c = carry == 1,
    };
}

fn bit(cpu: *SM83, r: u8, comptime idx: u3) void {
    cpu.registers.flags.z = (r >> idx) & 1 == 0;
    cpu.registers.flags.n = false;
    cpu.registers.flags.h = true;
}

fn res(_: *SM83, r: *u8, comptime idx: u3) void {
    r.* &= ~(@as(u8, 1) << idx);
}

fn set(_: *SM83, r: *u8, comptime idx: u3) void {
    r.* |= (@as(u8, 1)) << idx;
}

fn sla(cpu: *SM83, r: *u8) void {
    r.*, const carry = @shlWithOverflow(r.*, 1);
    cpu.registers.flags = .{
        .z = r.* == 0,
        .n = false,
        .h = false,
        .c = carry == 1,
    };
}

fn sra(cpu: *SM83, r: *u8) void {
    const signed_r: i8 = @bitCast(r.*);
    const carry = r.* & 1;
    r.* = @bitCast(signed_r >> 1);
    cpu.registers.flags = .{
        .z = r.* == 0,
        .n = false,
        .h = false,
        .c = carry == 1,
    };
}

fn swap(cpu: *SM83, r: *u8) void {
    const ls_nibble: u8 = r.* & 0x0F;
    const ms_nibble: u8 = r.* & 0xF0;
    r.* = (ms_nibble >> 4) | (ls_nibble << 4);
    cpu.registers.flags = .{
        .z = r.* == 0,
        .n = false,
        .h = false,
        .c = false,
    };
}

fn srl(cpu: *SM83, r: *u8) void {
    const carry = r.* & 1;
    r.* >>= 1;
    cpu.registers.flags = .{
        .z = r.* == 0,
        .n = false,
        .h = false,
        .c = carry == 1,
    };
}

fn pop(cpu: *SM83) u8 {
    defer cpu.registers.sp +%= 1;
    return cpu.memory[cpu.registers.sp];
}

fn push(cpu: *SM83, data: u8) void {
    cpu.registers.sp -%= 1;
    cpu.memory[cpu.registers.sp] = data;
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

fn inst_state(comptime inst: u8, comptime cycle: u3) u16 {
    return @as(u16, inst) << 3 | cycle;
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

const std = @import("std");
const raw_opcode_info = @import("resources/opcodes.zig.zon");

// I want to move this to the build system, but there is currently a bug in the
// Zig build system that errors when passing structs/arrays through addOptions.
// https://github.com/ziglang/zig/issues/19594
fn buildOpcodeTable(table: anytype) [256]InstInfo {
    var opcode_table: [256]InstInfo = undefined;
    inline for (table, 0..) |raw_opcode, i| {
        opcode_table[i] = .{ .mnemonic = raw_opcode.mnemonic, .bytes = raw_opcode.bytes };
        inline for (raw_opcode.operands, 0..) |operand, operand_idx| {
            opcode_table[i].operands[operand_idx] = .{ .name = operand.name, .immediate = operand.immediate };
            if (@hasField(@TypeOf(operand), "bytes")) {
                opcode_table[i].operands[operand_idx].?.bytes = operand.bytes;
            }
            if (@hasField(@TypeOf(operand), "increment")) {
                opcode_table[i].operands[operand_idx].?.increment = operand.increment;
            }
        }
    }

    return opcode_table;
}

const unprefixed_opcodes = buildOpcodeTable(raw_opcode_info.unprefixed);
const cbprefixed_opcodes = buildOpcodeTable(raw_opcode_info.cbprefixed);

const Mnemonic = enum {
    NOP,
    LD,
    INC,
    DEC,
    RLCA,
    ADD,
    RRCA,
    STOP,
    RLA,
    JR,
    RRA,
    DAA,
    CPL,
    SCF,
    CCF,
    HALT,
    ADC,
    SUB,
    SBC,
    AND,
    XOR,
    OR,
    CP,
    RET,
    POP,
    JP,
    CALL,
    PUSH,
    RST,
    PREFIX,
    ILLEGAL_D3,
    RETI,
    ILLEGAL_DB,
    ILLEGAL_DD,
    LDH,
    ILLEGAL_E3,
    ILLEGAL_E4,
    ILLEGAL_EB,
    ILLEGAL_EC,
    ILLEGAL_ED,
    DI,
    ILLEGAL_F4,
    EI,
    ILLEGAL_FC,
    ILLEGAL_FD,
    RLC,
    RRC,
    RL,
    RR,
    SLA,
    SRA,
    SWAP,
    SRL,
    BIT,
    RES,
    SET,
};

const Operands = [3]?Operand;
const Operand = struct {
    name: Name,
    immediate: bool,
    bytes: u8 = 0,
    increment: bool = false,

    const Name = enum {
        @"$00",
        @"$08",
        @"$10",
        @"$18",
        @"$20",
        @"$28",
        @"$30",
        @"$38",
        @"0",
        @"1",
        @"2",
        @"3",
        @"4",
        @"5",
        @"6",
        @"7",
        A,
        a16,
        a8,
        AF,
        B,
        BC,
        C,
        D,
        DE,
        E,
        e8,
        H,
        HL,
        L,
        n16,
        n8,
        NC,
        NZ,
        SP,
        Z,
    };
};

const InstInfo = struct {
    mnemonic: Mnemonic,
    bytes: u8,
    operands: Operands = .{null} ** 3,
};

// TODO better error handling
pub fn disassemble(writer: *std.Io.Writer, code: []const u8) !void {
    var pos: u16 = 0;
    while (pos < code.len) {
        const opcode_byte = code[pos];
        pos += 1;

        try writer.print("0x{X:0>4}:    ", .{pos});

        const opcode = blk: {
            if (opcode_byte == 0xCB) {
                defer pos += 1;
                break :blk cbprefixed_opcodes[code[pos]];
            } else {
                break :blk unprefixed_opcodes[opcode_byte];
            }
        };

        const pc = pos + opcode.bytes;

        try writer.writeAll(@tagName(opcode.mnemonic));

        for (opcode.operands, 0..) |operand_or_null, i| {
            const operand = operand_or_null orelse break;

            if (i > 0) {
                try writer.writeByte(',');
            }
            try writer.writeByte(' ');

            switch (operand.name) {
                .e8 => {
                    const signed_operand: i8 = @bitCast(code[pos]);
                    const signed_pc: i16 = @bitCast(pc);
                    try writer.print("0x{X:0>4}", .{@as(u16, @bitCast(signed_operand + signed_pc))});
                },
                inline .a16, .n16 => |op_tag| {
                    const fmt = if (op_tag == .a16) "[0x{X:0>4}]" else "0x{X:0>4}";
                    try writer.print(fmt, .{(@as(u16, code[pos + 1]) << 8) | code[pos]});
                },
                inline .a8, .n8 => |op_tag| {
                    const fmt = if (op_tag == .a8) "[0x{X:0>2}]" else "0x{X:0>2}";
                    try writer.print(fmt, .{code[pos]});
                },
                else => {
                    if (operand.immediate) {
                        try writer.print("{s}", .{@tagName(operand.name)});
                    } else {
                        try writer.print("[{s}]", .{@tagName(operand.name)});
                    }
                },
            }
            pos += operand.bytes;
        }
        try writer.writeByte('\n');
    }
}

test {
    const buffer = try std.testing.allocator.alloc(u8, 1024 * 1024);
    defer std.testing.allocator.free(buffer);
    var writer: std.Io.Writer = .fixed(buffer);

    const rom = @import("bootrom.zig").bytes;

    try disassemble(&writer, &rom);

    std.debug.print("{s}\n", .{writer.buffered()});
}

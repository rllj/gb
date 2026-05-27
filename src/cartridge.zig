const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const build_bitstring = @import("common.zig").build_bitstring;

const ROM_BANK_SIZE = 0x4000;
const RAM_BANK_SIZE = 0x2000;

pub const Cartridge = union(enum) {
    no_mbc: NoMBC,
    mbc1: MBC1,

    pub fn init(game: []const u8, allocator: Allocator) !Cartridge {
        const header: *const Header = @ptrCast(@alignCast(game[0x100..0x150]));

        std.debug.print("{f}\n", .{header});

        const cart_mem = try allocator.dupe(u8, game);
        assert(header.cart_type != .ROM_ONLY or cart_mem.len == 0x8000);
        return switch (header.cart_type) {
            .ROM_ONLY => .{ .no_mbc = .{ .cart_mem = cart_mem } },
            .MBC1, .@"MBC1+RAM", .@"MBC1+RAM+BATTERY" => .{ .mbc1 = .{
                .cart_mem = cart_mem,
                .num_rom_banks = header.rom_size,
                .num_ram_banks = header.ram_size,
            } },
            else => unreachable,
        };
    }

    pub fn deinit(self: *Cartridge, allocator: Allocator) void {
        switch (self.*) {
            inline else => |*mbc| allocator.free(mbc.cart_mem),
        }
    }

    pub fn read(self: *Cartridge, addr: u16) u8 {
        return switch (self.*) {
            inline else => |*mbc| mbc.read(addr),
        };
    }

    pub fn write(self: *Cartridge, addr: u16, data: u8) void {
        switch (self.*) {
            inline else => |*mbc| mbc.write(addr, data),
        }
    }
};

const NoMBC = struct {
    cart_mem: []const u8,

    pub fn read(self: *const NoMBC, addr: u16) u8 {
        assert(addr < 0x8000);
        return self.cart_mem[addr];
    }

    pub fn write(_: *const NoMBC, _: u16, _: u8) void {}
};

pub const MBC1 = struct {
    cart_mem: []u8,

    num_rom_banks: u8,
    num_ram_banks: u8,

    ram_enable: bool = false,
    rom_bank: u5 = 0,
    bank_upper: u2 = 0,
    bank_upper_mode: u1 = 0,

    pub fn read(self: *MBC1, addr: u16) u8 {
        return switch (addr) {
            0x0000...0x3FFF => self.cart_mem[self.rom_addr_bank0(addr)],
            0x4000...0x7FFF => self.cart_mem[self.rom_addr(addr)],
            0xA000...0xBFFF => self.cart_mem[self.ram_addr(addr)],
            else => unreachable,
        };
    }

    pub fn write(self: *MBC1, addr: u16, data: u8) void {
        switch (addr) {
            0x0000...0x1FFF => self.ram_enable = data & 0xF == 0xA,
            0x2000...0x3FFF => self.rom_bank = blk: {
                const trunc: u5 = @truncate(data);
                break :blk if (trunc == 0) 1 else trunc;
            },
            0x4000...0x5FFF => {
                self.bank_upper = @truncate(data);
            },
            0x6000...0x7FFF => {
                self.bank_upper_mode = @as(u1, @truncate(data));
            },
            0xA000...0xBFFF => self.cart_mem[self.ram_addr(addr)] = data,
            else => unreachable,
        }
    }

    fn rom_addr_bank0(self: *MBC1, addr: u16) u21 {
        const addr_low14: u14 = @truncate(addr);
        return build_bitstring(u21, .{
            self.bank_upper_mode * self.bank_upper,
            @as(u5, 0),
            addr_low14,
        });
    }

    fn rom_addr(self: *MBC1, addr: u16) u21 {
        const addr_low14: u14 = @truncate(addr);
        const bank_num = if (self.rom_bank == 0) 1 else self.rom_bank;
        return build_bitstring(u21, .{ self.bank_upper, bank_num, addr_low14 });
    }

    fn ram_addr(self: *MBC1, addr: u16) u21 {
        if (!self.ram_enable) return 0xFF;
        const addr_low13: u13 = @truncate(addr);
        const ram_start = @as(u21, self.num_rom_banks) * ROM_BANK_SIZE;
        return ram_start + build_bitstring(u15, .{
            self.bank_upper_mode * self.bank_upper,
            addr_low13,
        });
    }

    fn read_ram(self: *MBC1, bank_number: u8, addr: u16) u8 {
        const ram_begin = self.num_rom_banks * ROM_BANK_SIZE;
        return self.cart_mem[ram_begin + bank_number * RAM_BANK_SIZE + addr - 0xA000];
    }

    fn write_ram(self: *MBC1, addr: u16, data: u8) void {
        self.cart_mem[self.rom_size + addr - 0xA000] = data;
    }
};

const Header = extern struct {
    entry: [4]u8,
    logo: [48]u8,
    title: [16]u8,
    new_licensee: [2]u8,
    sgb: u8,
    cart_type: CartType,
    rom_size: u8,
    ram_size: u8,
    destination: Destination,
    old_licensee: u8,
    rom_version: u8,
    header_checksum: u8,
    global_checksum: u16,

    const Destination = enum(u8) {
        japan = 0,
        overseas = 1,
    };

    const CartType = enum(u8) {
        ROM_ONLY = 0x00,
        MBC1 = 0x01,
        @"MBC1+RAM" = 0x02,
        @"MBC1+RAM+BATTERY" = 0x03,
        MBC2 = 0x05,
        @"MBC2+BATTERY" = 0x06,
        @"ROM+RAM 11" = 0x08,
        @"ROM+RAM+BATTERY 11" = 0x09,
        MMM01 = 0x0B,
        @"MMM01+RAM" = 0x0C,
        @"MMM01+RAM+BATTERY" = 0x0D,
        @"MBC3+TIMER+BATTERY" = 0x0F,
        @"MBC3+TIMER+RAM+BATTERY 12" = 0x10,
        MBC3 = 0x11,
        @"MBC3+RAM 12" = 0x12,
        @"MBC3+RAM+BATTERY 12" = 0x13,
        MBC5 = 0x19,
        @"MBC5+RAM" = 0x1A,
        @"MBC5+RAM+BATTERY" = 0x1B,
        @"MBC5+RUMBLE" = 0x1C,
        @"MBC5+RUMBLE+RAM" = 0x1D,
        @"MBC5+RUMBLE+RAM+BATTERY" = 0x1E,
        MBC6 = 0x20,
        @"MBC7+SENSOR+RUMBLE+RAM+BATTERY" = 0x22,
        POCKET_CAMERA = 0xFC,
        BANDAI_TAMA5 = 0xFD,
        HuC3 = 0xFE,
        @"HuC1+RAM+BATTERY" = 0xFF,
    };

    pub fn format(self: Header, w: *std.Io.Writer) !void {
        try w.print(
            \\entry = {any},
            \\logo = {any},
            \\title = {s},
            \\new_licensee = {any},
            \\sgb = {},
            \\cart_type = {s},
            \\rom_size = {},
            \\ram_size = {},
            \\destination = {s},
            \\old_licensee = {},
            \\rom_version = {},
            \\header_checksum = {},
            \\global_checksum = {},
        , .{
            self.entry,
            self.logo,
            self.title[0 .. std.mem.indexOfScalar(u8, &self.title, 0) orelse 16],
            self.new_licensee,
            self.sgb,
            @tagName(self.cart_type),
            self.rom_size,
            self.ram_size,
            @tagName(self.destination),
            self.old_licensee,
            self.rom_version,
            self.header_checksum,
            self.global_checksum,
        });
    }
};
const NINTENDO_LOGO: [48]u8 = .{
    0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B,
    0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
    0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
    0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
    0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC,
    0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E,
};

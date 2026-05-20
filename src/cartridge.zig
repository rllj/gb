const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const BANK_SIZE_BYTES = 16 * 1024;

pub const Cartridge = union(enum) {
    no_mbc: NoMBC,
    mbc1: MBC1,

    pub fn init(game: []const u8, allocator: Allocator) !Cartridge {
        const header: *const Header = @ptrCast(@alignCast(game[0x100..0x150]));
        const rom_size = @as(u20, header.rom_size) * 2 * BANK_SIZE_BYTES;
        const ram_size = @as(u20, header.ram_size) * 2 * BANK_SIZE_BYTES;

        const cart_mem = try allocator.dupe(u8, game);
        return switch (header.cart_type) {
            .ROM_ONLY => .{ .no_mbc = .{ .cart_mem = cart_mem } },
            .MBC1 => .{ .mbc1 = .{ .cart_mem = cart_mem, .rom_size = rom_size, .ram_size = ram_size } },
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
    cart_mem: []u8,

    pub fn read(self: *const NoMBC, addr: u16) u8 {
        assert(addr < 0x8000);
        return self.cart_mem[addr];
    }

    pub fn write(_: *const NoMBC, _: u16, _: u8) void {}
};

pub const MBC1 = struct {
    cart_mem: []u8,

    rom_size: u20,
    ram_size: u20,

    ram_enable: bool = false,
    rom_bank: u5 = 0,
    ram_bank_or_rom_bank_upper: u2 = 0,
    rom_ram_select: enum(u1) { rom, ram } = .rom,

    pub fn read(self: *MBC1, addr: u16) u8 {
        switch (addr) {
            0x0000...0x3FFF => {
                var bits: u20 = 0;
                bits |= addr & 0x03FF;
                return if (self.rom_ram_select == .rom)
                    self.read_rom_bank(0, addr)
                else
                    0xFF;
            },
            0x4000...0x7FFF => {
                const bank_num = if (self.rom_bank == 0) 1 else self.rom_bank;
                return self.read_rom_bank(bank_num, addr);
            },
            0xA000...0xBFFF => {
                if (!self.ram_enable) return 0xFF;
                return self.read_ram(addr);
            },
            else => unreachable,
        }
    }

    fn read_rom_bank(self: *MBC1, bank_number: u8, addr: u16) u8 {
        return self.cart_mem[@as(u20, bank_number) * BANK_SIZE_BYTES + addr % BANK_SIZE_BYTES];
    }

    fn read_ram(self: *MBC1, addr: u16) u8 {
        return self.cart_mem[self.rom_size + addr - 0xA000];
    }

    pub fn write(self: *MBC1, addr: u16, data: u8) void {
        switch (addr) {
            0x0000...0x1FFF => self.ram_enable = data & 0xF == 0xA,
            0x2000...0x3FFF => self.rom_bank = blk: {
                const trunc: u5 = @truncate(data);
                break :blk if (trunc == 0) 1 else trunc;
            },
            0x4000...0x5FFF => {
                self.ram_bank_or_rom_bank_upper = @truncate(data);
            },
            0x6000...0x7FFF => {
                self.rom_ram_select = @enumFromInt(@as(u1, @truncate(data)));
            },
            else => unreachable,
        }
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
};
const NINTENDO_LOGO: [48]u8 = .{
    0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B,
    0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
    0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
    0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
    0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC,
    0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E,
};

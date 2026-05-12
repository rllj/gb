const Cartridge = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    read_bank0: *const fn (*anyopaque, addr: u16) u8,
    read_bank1: *const fn (*anyopaque, addr: u16) u8,
    write_ram: *const fn (*anyopaque, addr: u16, data: u8) void,
};

pub fn write_ram(self: Cartridge, addr: u16, data: u8) void {
    return self.write_ram(addr, data);
}

pub fn read_bank0(self: Cartridge, addr: u16) void {
    return self.read_bank0(addr);
}

pub fn read_bank1(self: Cartridge, addr: u16) void {
    return self.read_bank1(addr);
}

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

pub const MBC1 = struct {
    rom_banks: []const []u8,
    ram_enable: bool,
    rom_bank: u5,
    ram_bank_or_rom_bank_upper: u2,
    rom_ram_select: enum(u1) { rom, ram },

    pub fn cartridge(self: *MBC1) Cartridge {
        return .{
            .ptr = self,
            .vtable = &.{
                .read_bank0 = MBC1.read_bank0,
                .read_bank1 = MBC1.read_bank1,
                .write_ram = MBC1.write_ram,
            },
        };
    }

    pub fn read_bank0(ctx: *const anyopaque, addr: u16) u8 {
        const self: *const MBC1 = @ptrCast(@alignCast(ctx));
        return self.rom_banks[0][addr];
    }

    pub fn read_bank1(ctx: *const anyopaque, addr: u16) u8 {
        const self: *const MBC1 = @ptrCast(@alignCast(ctx));
        const bank = if (self.rom_bank == 0) 1 else self.rom_bank;
        const upper_bits: u7 = if (self.rom_ram_select == .rom) self.ram_bank_or_rom_bank_upper else 0;
        const rom = self.rom_banks[bank | upper_bits << 5];
        return rom[addr];
    }
};

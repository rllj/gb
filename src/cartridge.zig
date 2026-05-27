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
                .num_rom_banks = @as(u9, 2) << @truncate(header.rom_size),
                .num_ram_banks = switch (header.ram_size) {
                    0, 1 => 0,
                    2 => 1,
                    3 => 4,
                    4 => 16,
                    5 => 8,
                    else => unreachable,
                },
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

    num_rom_banks: u9,
    num_ram_banks: u5,

    ram_enable: bool = false,
    rom_bank: u5 = 0,
    bank_upper: u2 = 0,
    bank_upper_mode: u1 = 0,

    pub fn read(self: *MBC1, addr: u16) u8 {
        const rom_size_bytes = ROM_BANK_SIZE * @as(u21, self.num_rom_banks);
        const ram_size_bytes = RAM_BANK_SIZE * @as(u21, self.num_ram_banks);
        return switch (addr) {
            0x0000...0x3FFF => self.cart_mem[self.rom_addr_bank0(addr) % rom_size_bytes],
            0x4000...0x7FFF => self.cart_mem[self.rom_addr(addr) % rom_size_bytes],
            0xA000...0xBFFF => {
                if (!self.ram_enable) return 0xFF;
                return self.cart_mem[self.ram_addr(addr) % ram_size_bytes];
            },
            else => unreachable,
        };
    }

    pub fn write(self: *MBC1, addr: u16, data: u8) void {
        const ram_size_bytes = 8 * 1024 * @as(u21, self.num_ram_banks);
        switch (addr) {
            0x0000...0x1FFF => self.ram_enable = (data & 0xF) == 0xA and self.num_ram_banks > 0,
            0x2000...0x3FFF => self.rom_bank = @truncate(@max(1, data)),
            0x4000...0x5FFF => self.bank_upper = @truncate(data),
            0x6000...0x7FFF => self.bank_upper_mode = @as(u1, @truncate(data)),
            0xA000...0xBFFF => if (self.ram_enable) {
                self.cart_mem[self.ram_addr(addr) % ram_size_bytes] = data;
            },
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
        const bank_num = @max(1, self.rom_bank);
        return build_bitstring(u21, .{ self.bank_upper, bank_num, addr_low14 });
    }

    fn ram_addr(self: *MBC1, addr: u16) u21 {
        const addr_low13: u13 = @truncate(addr);
        const ram_start = @as(u21, self.num_rom_banks) * ROM_BANK_SIZE;
        return ram_start + build_bitstring(u15, .{
            self.bank_upper_mode * self.bank_upper,
            addr_low13,
        });
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
    global_checksum: [2]u8,

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

    fn old_licencee_name(old_licencee: u8) []const u8 {
        return switch (old_licencee) {
            0x00 => "None",
            0x01 => "Nintendo",
            0x08 => "Capcom",
            0x09 => "HOT-B",
            0x0A => "Jaleco",
            0x0B => "Coconuts Japan",
            0x0C => "Elite Systems",
            0x13 => "EA (Electronic Arts)",
            0x18 => "Hudson Soft",
            0x19 => "ITC Entertainment",
            0x1A => "Yanoman",
            0x1D => "Japan Clary",
            0x1F => "Virgin Games Ltd.3",
            0x24 => "PCM Complete",
            0x25 => "San-X",
            0x28 => "Kemco",
            0x29 => "SETA Corporation",
            0x30 => "Infogrames5",
            0x31 => "Nintendo",
            0x32 => "Bandai",
            0x33 => "(see new licencee)",
            0x34 => "Konami",
            0x35 => "HectorSoft",
            0x38 => "Capcom",
            0x39 => "Banpresto",
            0x3C => "Entertainment Interactive (stub)",
            0x3E => "Gremlin",
            0x41 => "Ubi Soft1",
            0x42 => "Atlus",
            0x44 => "Malibu Interactive",
            0x46 => "Angel",
            0x47 => "Spectrum HoloByte",
            0x49 => "Irem",
            0x4A => "Virgin Games Ltd.3",
            0x4D => "Malibu Interactive",
            0x4F => "U.S. Gold",
            0x50 => "Absolute",
            0x51 => "Acclaim Entertainment",
            0x52 => "Activision",
            0x53 => "Sammy USA Corporation",
            0x54 => "GameTek",
            0x55 => "Park Place15",
            0x56 => "LJN",
            0x57 => "Matchbox",
            0x59 => "Milton Bradley Company",
            0x5A => "Mindscape",
            0x5B => "Romstar",
            0x5C => "Naxat Soft16",
            0x5D => "Tradewest",
            0x60 => "Titus Interactive",
            0x61 => "Virgin Games Ltd.3",
            0x67 => "Ocean Software",
            0x69 => "EA (Electronic Arts)",
            0x6E => "Elite Systems",
            0x6F => "Electro Brain",
            0x70 => "Infogrames5",
            0x71 => "Interplay Entertainment",
            0x72 => "Broderbund",
            0x73 => "Sculptured Software6",
            0x75 => "The Sales Curve Limited7",
            0x78 => "THQ",
            0x79 => "Accolade8",
            0x7A => "Triffix Entertainment",
            0x7C => "MicroProse",
            0x7F => "Kemco",
            0x80 => "Misawa Entertainment",
            0x83 => "LOZC G.",
            0x86 => "Tokuma Shoten",
            0x8B => "Bullet-Proof Software2",
            0x8C => "Vic Tokai Corp.17",
            0x8E => "Ape Inc.18",
            0x8F => "I’Max19",
            0x91 => "Chunsoft Co.9",
            0x92 => "Video System",
            0x93 => "Tsubaraya Productions",
            0x95 => "Varie",
            0x96 => "Yonezawa10/S’Pal",
            0x97 => "Kemco",
            0x99 => "Arc",
            0x9A => "Nihon Bussan",
            0x9B => "Tecmo",
            0x9C => "Imagineer",
            0x9D => "Banpresto",
            0x9F => "Nova",
            0xA1 => "Hori Electric",
            0xA2 => "Bandai",
            0xA4 => "Konami",
            0xA6 => "Kawada",
            0xA7 => "Takara",
            0xA9 => "Technos Japan",
            0xAA => "Broderbund",
            0xAC => "Toei Animation",
            0xAD => "Toho",
            0xAF => "Namco",
            0xB0 => "Acclaim Entertainment",
            0xB1 => "ASCII Corporation or Nexsoft",
            0xB2 => "Bandai",
            0xB4 => "Square Enix",
            0xB6 => "HAL Laboratory",
            0xB7 => "SNK",
            0xB9 => "Pony Canyon",
            0xBA => "Culture Brain",
            0xBB => "Sunsoft",
            0xBD => "Sony Imagesoft",
            0xBF => "Sammy Corporation",
            0xC0 => "Taito",
            0xC2 => "Kemco",
            0xC3 => "Square",
            0xC4 => "Tokuma Shoten",
            0xC5 => "Data East",
            0xC6 => "Tonkin House",
            0xC8 => "Koei",
            0xC9 => "UFL",
            0xCA => "Ultra Games",
            0xCB => "VAP, Inc.",
            0xCC => "Use Corporation",
            0xCD => "Meldac",
            0xCE => "Pony Canyon",
            0xCF => "Angel",
            0xD0 => "Taito",
            0xD1 => "SOFEL (Software Engineering Lab)",
            0xD2 => "Quest",
            0xD3 => "Sigma Enterprises",
            0xD4 => "ASK Kodansha Co.",
            0xD6 => "Naxat Soft16",
            0xD7 => "Copya System",
            0xD9 => "Banpresto",
            0xDA => "Tomy",
            0xDB => "LJN",
            0xDD => "Nippon Computer Systems",
            0xDE => "Human Ent.",
            0xDF => "Altron",
            0xE0 => "Jaleco",
            0xE1 => "Towa Chiki",
            0xE2 => "Yutaka # Needs more info",
            0xE3 => "Varie",
            0xE5 => "Epoch",
            0xE7 => "Athena",
            0xE8 => "Asmik Ace Entertainment",
            0xE9 => "Natsume",
            0xEA => "King Records",
            0xEB => "Atlus",
            0xEC => "Epic/Sony Records",
            0xEE => "IGS",
            0xF0 => "A Wave",
            0xF3 => "Extreme Entertainment",
            0xFF => "LJN",
            else => "(unknown)",
        };
    }

    fn new_licencee_name(new_licencee: [2]u8) []const u8 {
        const key = (@as(u16, new_licencee[0]) << 8) | new_licencee[1];
        return switch (key) {
            0x3030 => "None",
            0x3031 => "Nintendo Research & Development 1",
            0x3038 => "Capcom",
            0x3133 => "EA (Electronic Arts)",
            0x3138 => "Hudson Soft",
            0x3139 => "B-AI",
            0x3230 => "KSS",
            0x3232 => "Planning Office WADA",
            0x3234 => "PCM Complete",
            0x3235 => "San-X",
            0x3238 => "Kemco",
            0x3239 => "SETA Corporation",
            0x3330 => "Viacom",
            0x3331 => "Nintendo",
            0x3332 => "Bandai",
            0x3333 => "Ocean Software/Acclaim Entertainment",
            0x3334 => "Konami",
            0x3335 => "HectorSoft",
            0x3337 => "Taito",
            0x3338 => "Hudson Soft",
            0x3339 => "Banpresto",
            0x3431 => "Ubi Soft1",
            0x3432 => "Atlus",
            0x3434 => "Malibu Interactive",
            0x3436 => "Angel",
            0x3437 => "Bullet-Proof Software2",
            0x3439 => "Irem",
            0x3530 => "Absolute",
            0x3531 => "Acclaim Entertainment",
            0x3532 => "Activision",
            0x3533 => "Sammy USA Corporation",
            0x3534 => "Konami",
            0x3535 => "Hi Tech Expressions",
            0x3536 => "LJN",
            0x3537 => "Matchbox",
            0x3538 => "Mattel",
            0x3539 => "Milton Bradley Company",
            0x3630 => "Titus Interactive",
            0x3631 => "Virgin Games Ltd.3",
            0x3634 => "Lucasfilm Games4",
            0x3637 => "Ocean Software",
            0x3639 => "EA (Electronic Arts)",
            0x3730 => "Infogrames5",
            0x3731 => "Interplay Entertainment",
            0x3732 => "Broderbund",
            0x3733 => "Sculptured Software6",
            0x3735 => "The Sales Curve Limited7",
            0x3738 => "THQ",
            0x3739 => "Accolade8",
            0x3830 => "Misawa Entertainment",
            0x3833 => "LOZC G.",
            0x3836 => "Tokuma Shoten",
            0x3837 => "Tsukuda Original",
            0x3931 => "Chunsoft Co.9",
            0x3932 => "Video System",
            0x3933 => "Ocean Software/Acclaim Entertainment",
            0x3935 => "Varie",
            0x3936 => "Yonezawa10/S’Pal",
            0x3937 => "Kaneko",
            0x3939 => "Pack-In-Video",
            0x3948 => "Bottom Up",
            0x4134 => "Konami (Yu-Gi-Oh!)",
            0x424c => "MTO",
            0x444b => "Kodansha",
            else => "(unknown)",
        };
    }

    pub fn format(self: Header, w: *std.Io.Writer) !void {
        try w.print(
            \\entry = {any},
            \\logo = {any},
            \\title = {s},
            \\new_licensee = {s},
            \\sgb = {},
            \\cart_type = {s},
            \\rom_size = {},
            \\ram_size = {},
            \\destination = {s},
            \\old_licensee = {s},
            \\rom_version = {},
            \\header_checksum = {},
            \\global_checksum = {any},
        , .{
            self.entry,
            self.logo,
            self.title[0 .. std.mem.indexOfScalar(u8, &self.title, 0) orelse 16],
            new_licencee_name(self.new_licensee),
            self.sgb,
            @tagName(self.cart_type),
            self.rom_size,
            self.ram_size,
            @tagName(self.destination),
            old_licencee_name(self.old_licensee),
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

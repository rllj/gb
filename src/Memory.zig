const Allocator = @import("std").mem.Allocator;

const Memory = @This();

memory: []u8,

rom_bank00: []u8,
rom_bank_switchable: []u8,
vram: []u8,
cart_ram: []u8,
wram: []u8,
echo: []u8,
oam: []u8,
unusable: []u8,
io: []u8,
hram: []u8,
ie: *u8,

pub fn init(allocator: Allocator) !Memory {
    const memory: []u8 = try allocator.alloc(u8, 65536);
    @memset(memory, 0xFF); // TODO bootrom
    return .{
        .rom_bank00 = memory[0x0000..0x4000],
        .rom_bank_switchable = memory[0x4000..0x8000],
        .vram = memory[0x8000..0xA000],
        .cart_ram = memory[0xA000..0xC000],
        .wram = memory[0xC000..0xE000],
        .echo = memory[0xE000..0xFE00],
        .oam = memory[0xFE00..0xFEA0],
        .unusable = memory[0xFEA0..0xFF00],
        .io = memory[0xFF00..0xFF80],
        .hram = memory[0xFF80..0xFFFF],
        .ie = &memory[0xFFFF],
        .memory = memory,
    };
}

pub fn deinit(self: Memory, allocator: Allocator) void {
    allocator.free(self.memory);
}

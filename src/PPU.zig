const std = @import("std");
const assert = std.debug.assert;

const BoundedArray = @import("common.zig").BoundedArray;
const Pins = @import("SM83.zig").Pins;

const PPU = @This();

pub const LCDC = 0xFF40;
pub const STAT = 0xFF41;
pub const SCY = 0xFF42;
pub const SCX = 0xFF43;
pub const LY = 0xFF44;
pub const LYC = 0xFF45;
pub const DMA = 0xFF46;
pub const BGP = 0xFF47;
pub const OBP0 = 0xFF48;
pub const OBP1 = 0xFF49;
pub const WY = 0xFF4A;
pub const WX = 0xFF4B;

pub const TILE_DATA_START: u16 = 0x8000;
pub const TILE_DATA_MIDDLE: u16 = 0x8800;
pub const TILE_DATA_END: u16 = 0x9800;

pub const TILE_MAP_0_START = 0x9800;
pub const TILE_MAP_0_END = 0x9BFF;
pub const TILE_MAP_1_START = 0x9C00;
pub const TILE_MAP_1_END = 0x9FFF;

pub const OAM_START = 0xFE00;

lcdc: LCDControl = .{},
stat: Status = @bitCast(@as(u8, 0)),
scy: u8 = 0,
scx: u8 = 0,
ly: u8 = 0,
lyc: u8 = 0,
bgp: Palette = @bitCast(@as(u8, 0)),
obp0: Palette = @bitCast(@as(u8, 0)),
obp1: Palette = @bitCast(@as(u8, 0)),
wy: u8 = 0,
wx: u8 = 0,
// TODO remove
temp_ready_to_render: bool = false,
// The "stat line" is what the Pandocs call a shared state between each of the
// possible stat interrupts. The actual STAT interrupt is triggered by a rising
// edge on the shared STAT line, meaning we need to store the prevous state
// here.
stat_line: u1 = 0,

// TODO This certainly isn't optimal, and once I find out why OAM scan (mode 2)
// doesn't take 84 cycles I'll make the PPU commicate with memory via a Bus
// like the CPU.
oam: []u8,
vram: []u8,

dots_per_mode: usize = 0,
scanline_pixel: u8 = 0,
visible_sprites: BoundedArray(ObjectAttribute, 10) = .{},

fetcher_state: FetchState = .fetch_tile,
fetcher_index: u1 = 0,
fetcher_buffer: u16 = 0,
fetcher_tile_x: u8 = 0,
fetcher_curr_tile: u16 = 0,
fifo_discard_scroll: u8 = 0,
fifo: Fifo = .{},

// TODO The PPU shouldn't own the display, of course
display: [160 * 144]u32 = .{0x00} ** (160 * 144),

const ObjectAttribute = packed struct(u32) {
    y_pos: u8,
    x_pos: u8,
    tile_idx: u8,
    flags: Flags,

    const Flags = packed struct(u8) { priority: bool, y_flip: bool, x_flip: bool, dmg_palette: u1, cgb_reserved: u4 };
};

// https://gbdev.io/pandocs/LCDC.html
const LCDControl = packed struct(u8) {
    bg_window_enable: u1 = 0,
    obj_enable: u1 = 0,
    obj_size: u1 = 0,
    bg_tilemap_area: u1 = 0,
    bg_window_addressing_mode: u1 = 0,
    window_enable: u1 = 0,
    window_tilemap_area: u1 = 0,
    lcd_enable: u1 = 0,
};

const Status = packed struct(u8) {
    mode: Mode = .oam_scan,
    ly_lyc_eq: bool,
    mode_0_stat_int: bool,
    mode_1_stat_int: bool,
    mode_2_stat_int: bool,
    lyc_stat_int: bool,
    unused: u1,
};

const Mode = enum(u2) {
    hblank = 0,
    vblank = 1,
    oam_scan = 2,
    draw = 3,
};

const Palette = packed struct(u8) {
    idx_0: Colour,
    idx_1: Colour,
    idx_2: Colour,
    idx_3: Colour,

    pub fn from_index(self: Palette, index: u2) Colour {
        return switch (index) {
            0 => self.idx_0,
            1 => self.idx_1,
            2 => self.idx_2,
            3 => self.idx_3,
        };
    }
};

const Colour = enum(u2) {
    white = 0,
    light_gray = 1,
    dark_gray = 2,
    black = 3,

    pub fn rgba_8_8_8_8(self: Colour) u32 {
        return switch (self) {
            .white => 0xE0F8D0FF,
            .light_gray => 0x86C06CFF,
            .dark_gray => 0x306850FF,
            .black => 0x071821FF,
        };
    }
};

const FetchState = enum {
    fetch_tile,
    fetch_low,
    fetch_high,
    idle,
};

const FetcherBuffer = struct {
    buffer: u16 = 0,
    len: u4 = 0,

    pub fn enqueue(self: *FetcherBuffer, pixel: u2) void {
        self.buffer |= @as(u16, pixel) << (14 - self.len * 2);
        self.len += 1;
    }
};

const Fifo = struct {
    fifo: u32 = 0,
    len: u5 = 0,

    pub fn enqueue_row(self: *Fifo, row: u16) void {
        self.fifo |= @as(u32, row) << (16 - self.len * 2);
        self.len += 8;
    }

    pub fn enqueue(self: *Fifo, pixel: u2) void {
        self.fifo |= @as(u32, pixel) << (30 - self.len * 2);
        self.len += 1;
    }

    pub fn dequeue(self: *Fifo) u2 {
        const pixel: u2 = @truncate(self.fifo >> 30);
        self.fifo <<= 2;
        self.len -= 1;
        return pixel;
    }
};

/// To be called at 4.194304 MHz.
pub fn dot(self: *PPU, bus: *Pins) void {
    if (self.lcdc.lcd_enable == 0) return;

    var stat_int: u1 = 0;

    self.stat.ly_lyc_eq = self.ly == self.lyc;
    if (self.stat.ly_lyc_eq and self.stat.lyc_stat_int) {
        stat_int = 1;
    }

    const sprite_height: u8 = if (self.lcdc.obj_size == 0) 8 else 16;

    switch (self.stat.mode) {
        .oam_scan => {
            if (self.stat.mode_2_stat_int) stat_int = 1;

            self.dots_per_mode += 1;
            if (self.dots_per_mode == 80) {
                // TODO cycle-step
                const oam: []ObjectAttribute = @ptrCast(@alignCast(self.oam));
                for (oam) |oa| {
                    if (oa.y_pos != 0 and self.ly + 16 >= oa.y_pos and
                        self.ly + 16 < oa.y_pos + sprite_height and self.visible_sprites.len < 10)
                    {
                        self.visible_sprites.push(oa);
                    }
                }

                self.fifo_discard_scroll = self.scx % 8;
                self.stat.mode = .draw;
            }
        },
        .draw => {
            self.dots_per_mode += 1;

            if (self.fifo.len > 8) {
                if (self.fifo_discard_scroll != 0) {
                    _ = self.fifo_dequeue();
                    self.fifo_discard_scroll -= 1;
                } else {
                    self.put_pixel(self.fifo_dequeue());
                    self.scanline_pixel += 1;
                }
            }
            self.fifo_fetch();

            if (self.scanline_pixel == 160) {
                self.reset_scanline();
                self.stat.mode = .hblank;
            }
        },
        .hblank => {
            if (self.stat.mode_0_stat_int) stat_int = 1;

            self.dots_per_mode += 1;

            if (self.dots_per_mode == 456) {
                if (self.ly == 143) {
                    self.stat.mode = .vblank;
                    self.temp_ready_to_render = true;
                } else {
                    self.stat.mode = .oam_scan;
                    self.ly += 1;
                    self.dots_per_mode = 0;
                }
            }
        },
        .vblank => {
            if (self.stat.mode_1_stat_int) stat_int = 1;

            if (self.dots_per_mode % 456 == 0) {
                self.ly += 1;
            }

            if (self.ly == 144) {
                bus.int.vblank = 1;
            }

            self.dots_per_mode += 1;

            if (self.ly == 153) {
                self.dots_per_mode = 0;
                self.ly = 0;
                self.stat.mode = .oam_scan;
            }
        },
    }

    if (stat_int == 1 and self.stat_line == 0) {
        bus.int.status = 1;
    }
    self.stat_line = stat_int;
}

fn fifo_fetch(self: *PPU) void {
    switch (self.fetcher_state) {
        .fetch_tile => {
            if (self.advance_fetcher()) {
                const x: u16 = (self.fetcher_tile_x + self.scx / 8) & 0x1F;
                const y: u16 = (self.ly +% self.scy) / 8;

                var tilemap_address: u16 = TILE_MAP_0_START;
                if (self.lcdc.bg_tilemap_area == 1 and !self.inside_window(x)) {
                    tilemap_address = TILE_MAP_1_START;
                }
                if (self.lcdc.window_tilemap_area == 1 and self.inside_window(x)) {
                    tilemap_address = TILE_MAP_1_START;
                }

                const idx = x + y * 32;
                self.fetcher_curr_tile = self.read_vram(tilemap_address + idx);

                self.fetcher_state = .fetch_low;
            }
        },
        .fetch_low => {
            if (self.advance_fetcher()) {
                const tile_data_base = switch (self.lcdc.bg_window_addressing_mode) {
                    0 => add_as_signed(TILE_DATA_MIDDLE, self.fetcher_curr_tile * 16),
                    1 => TILE_DATA_START + self.fetcher_curr_tile * 16,
                };
                const y: u16 = (self.ly % 8 + self.scy % 8) % 8;

                const tile_data_idx = tile_data_base + y * 2;
                const tile_data = self.read_vram(tile_data_idx);

                var fetcher_buffer: FetcherBuffer = .{};
                for (0..8) |idx| {
                    const i: u3 = @truncate(7 - idx);
                    const bit: u2 = @truncate((tile_data >> i) & 1);
                    fetcher_buffer.enqueue(bit);
                }
                self.fetcher_buffer = fetcher_buffer.buffer;

                self.fetcher_state = .fetch_high;
            }
        },
        .fetch_high => {
            if (self.advance_fetcher()) {
                const tile_data_base = switch (self.lcdc.bg_window_addressing_mode) {
                    0 => add_as_signed(TILE_DATA_MIDDLE, self.fetcher_curr_tile * 16),
                    1 => TILE_DATA_START + self.fetcher_curr_tile * 16,
                };
                const y: u16 = (self.ly % 8 + self.scy % 8) % 8;

                const tile_data_idx = tile_data_base + y * 2 + 1;
                const tile_data = self.read_vram(tile_data_idx);

                var fetcher_buffer: FetcherBuffer = .{};
                for (0..8) |idx| {
                    const i: u3 = @truncate(7 - idx);
                    const bit: u2 = @truncate((tile_data >> i) & 1);
                    fetcher_buffer.enqueue(bit << 1);
                }
                self.fetcher_buffer |= fetcher_buffer.buffer;

                self.fetcher_state = .idle;
            }
        },
        .idle => {
            if (self.fifo_enqueue(self.fetcher_buffer)) {
                self.fetcher_state = .fetch_tile;
                self.fetcher_tile_x += 1;
            }
        },
    }
}

fn read_vram(self: *const PPU, addr: u16) u8 {
    return self.vram[addr - 0x8000];
}

fn add_as_signed(lhs: u16, rhs: u16) u16 {
    const signed_rhs: i16 = @bitCast(rhs);
    return lhs +% @as(u16, @bitCast(signed_rhs));
}

fn fifo_enqueue(self: *PPU, row: u16) bool {
    if (self.fifo.len <= 8) {
        self.fifo.enqueue_row(row);
        return true;
    }
    return false;
}

fn fifo_dequeue(self: *PPU) u2 {
    return self.fifo.dequeue();
}

fn advance_fetcher(self: *PPU) bool {
    defer self.fetcher_index ^= 1;
    return self.fetcher_index == 1;
}

fn put_pixel(self: *PPU, pixel: u2) void {
    const pixel_pos = @as(u16, self.scanline_pixel) + @as(u16, self.ly) * 160;
    const colour = self.bgp.from_index(pixel);
    self.display[pixel_pos] = colour.rgba_8_8_8_8();
}

fn reset_scanline(self: *PPU) void {
    self.visible_sprites = .{};
    self.scanline_pixel = 0;
    self.fetcher_tile_x = 0;
    self.fifo = .{};
}

// TODO
fn inside_window(self: *PPU, x: u16) bool {
    _ = self;
    _ = x;
    return false;
}

pub fn debug_generate_tilemap(self: *PPU, comptime tilemap: u1, allocator: std.mem.Allocator) ![]const u32 {
    const tilemap_start = (if (tilemap == 0) TILE_MAP_0_START else TILE_MAP_1_START) - 0x8000;
    const tilemap_end = tilemap_start + 1024;

    const map = try allocator.alloc(u32, 256 * 256);
    for (self.vram[tilemap_start..tilemap_end], 0..) |tile_idx, vert| {
        const row_x = vert % 32;
        const row_y = vert / 32;
        const offset = TILE_DATA_START - 0x8000;
        const from = offset + @as(usize, tile_idx) * 16;

        for (0..8) |i| {
            const low = self.vram[from + i * 2];
            const high = self.vram[from + i * 2 + 1];

            var colours: [8]u32 = undefined;
            for (0..8) |shift| {
                const s: u3 = @truncate(7 - shift);
                const colour_idx: u2 = (@as(u2, @truncate(high >> s)) & 1) << 1 |
                    (@as(u2, @truncate(low >> s)) & 1);
                const colour: Colour = self.bgp.from_index(colour_idx);
                colours[shift] = colour.rgba_8_8_8_8();
            }

            const dst_start = row_y * 8 * 256 + i * 256 + row_x * 8;
            @memcpy(map[dst_start .. dst_start + 8], &colours);
        }
    }
    return map;
}

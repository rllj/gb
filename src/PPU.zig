const std = @import("std");
const assert = std.debug.assert;

const BoundedArray = @import("common.zig").BoundedArray;

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
    id0: Colour,
    id1: Colour,
    id2: Colour,
    id3: Colour,
};

const Colour = enum(u2) {
    white = 0,
    light_gray = 1,
    dark_gray = 2,
    black = 3,
};

const FetchState = enum {
    fetch_tile,
    fetch_low,
    fetch_high,
    idle,
};

lcdc: LCDControl = .{},
stat: Status = @bitCast(@as(u8, 0)),
scy: u8 = 0,
scx: u8 = 0,
ly: u8 = 0,
lyc: u8 = 0,
bgp: Palette = @bitCast(@as(u8, 0)),
obp0: Palette = @bitCast(@as(u8, 0)),
obp1: Palette = @bitCast(@as(u8, 0)),

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
fetcher_buffer: [8]u2 = .{0} ** 8,
fetcher_tile_x: u8 = 0,
fetcher_curr_tile: u8 = 0,
// TODO shift register data structure instead
fifo: std.Deque(u2),

// TODO The PPU shouldn't own the display, of course
display: [160 * 144]u32 = .{0x00} ** (160 * 144),

fn fifo_fetch(self: *PPU) void {
    switch (self.fetcher_state) {
        .fetch_tile => {
            if (self.advance_fetcher()) {
                const x: u16 = @truncate(self.fetcher_tile_x + self.scx / 8);
                const y: u16 = @truncate((self.ly + self.scy) / 8);

                // TODO tilemap 2

                const idx = x + y * 32;
                self.fetcher_curr_tile = self.read_vram(TILE_MAP_0_START + idx);

                self.fetcher_state = .fetch_low;
            }
        },
        .fetch_low => {
            if (self.advance_fetcher()) {
                const tile_data_base = switch (self.lcdc.bg_window_addressing_mode) {
                    0 => TILE_DATA_START + self.fetcher_curr_tile,
                    1 => add_as_signed(TILE_DATA_MIDDLE, self.fetcher_curr_tile),
                };
                const y: u16 = @truncate((self.ly + self.scy) / 8);

                const tile_data_idx = tile_data_base + y * 2;
                const tile_data = self.read_vram(tile_data_idx);

                for (&self.fetcher_buffer, 0..) |*pixel, i| {
                    const bit: u2 = @truncate((tile_data >> @truncate(i)) & 1);
                    pixel.* = bit;
                }

                self.fetcher_state = .fetch_high;
            }
        },
        .fetch_high => {
            if (self.advance_fetcher()) {
                const tile_data_base = switch (self.lcdc.bg_window_addressing_mode) {
                    0 => TILE_DATA_START + self.fetcher_curr_tile,
                    1 => add_as_signed(TILE_DATA_MIDDLE, self.fetcher_curr_tile),
                };
                const y: u16 = @truncate((self.ly + self.scy) / 8);

                const tile_data_idx = tile_data_base + y * 2 + 1;
                const tile_data = self.read_vram(tile_data_idx);

                for (&self.fetcher_buffer, 0..) |*pixel, i| {
                    const bit: u2 = @truncate((tile_data >> @truncate(i)) & 1);
                    pixel.* |= bit << 1;
                }

                self.fetcher_state = .idle;
            }
        },
        .idle => {
            if (self.fifo_enqueue(self.fetcher_buffer)) {
                self.fetcher_state = .fetch_tile;
            }
        },
    }
}

fn fifo_enqueue(self: *PPU, row: [8]u2) bool {
    if (self.fifo.len <= 8) {
        self.fifo.pushFrontSliceAssumeCapacity(&row);
        return true;
    }
    return false;
}

fn fifo_dequeue(self: *PPU) u2 {
    return self.fifo.popBack().?;
}

fn advance_fetcher(self: *PPU) bool {
    defer self.fetcher_index ^= 1;
    return self.fetcher_index == 1;
}

fn put_pixel(self: *PPU, pixel: u2) void {
    const pixel_pos = @as(u16, self.scanline_pixel) + @as(u16, self.ly) * 160;
    self.display[pixel_pos] = switch (pixel) {
        0 => 0x0F380FFF,
        1 => 0x306230FF,
        2 => 0x8BAC0FFF,
        3 => 0x9BBC0FFF,
    };
}

fn reset_scanline(self: *PPU) void {
    if (self.scanline_pixel != 160) {
        std.debug.panic("Expected 160, got {}", .{self.scanline_pixel});
    }
    self.scanline_pixel = 0;
    self.fetcher_tile_x = 0;
    self.fifo = .{ .buffer = self.fifo.buffer, .head = 0, .len = 0 };
}

/// To be called at 4.194304 MHz.
pub fn dot(self: *PPU) void {

    // TODO trigger interrupts
    self.stat.ly_lyc_eq = self.ly == self.lyc;

    const sprite_height: u8 = if (self.lcdc.obj_size == 0) 8 else 16;

    switch (self.stat.mode) {
        .oam_scan => {
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

                self.stat.mode = .draw;
            }
        },
        .draw => {
            self.dots_per_mode += 1;

            self.fifo_fetch();
            if (self.fifo.len > 8) {
                self.put_pixel(self.fifo_dequeue());
                self.scanline_pixel += 1;
            }

            // Fetcher: get tile (2 dots)
            // Fetcher: get low (2 dots)
            // Fetcher: get high, put row in fifo (2 dots)
            // repeat steps above once
            // Fifo: put one pixel, Fetcher: get tile (1 dot)
            // Fifo: put one pixel, Fetcher: get tile (1 dot)
            // Fifo: put one pixel, Fetcher: get low (1 dot)
            // Fifo: put one pixel, Fetcher: get low (1 dot)
            // Fifo: put one pixel, Fetcher: get high (1 dot)
            // Fifo: put one pixel, Fetcher: get high (1 dot)
            // Fifo: put one pixel, Fetcher: idle (1 dot)
            // Fifo: put one pixel, Fetcher: put row in fifo (1 dot)

            // Alternatively: self.current_pixel == 160
            if (self.scanline_pixel == 160) {
                self.stat.mode = .hblank;
                self.reset_scanline();
            }
        },
        .hblank => {
            self.dots_per_mode += 1;

            if (self.dots_per_mode == 456) {
                if (self.ly == 143) {
                    self.stat.mode = .vblank;
                } else {
                    self.stat.mode = .oam_scan;
                    self.ly += 1;
                }
                self.dots_per_mode = 0;
            }
        },
        .vblank => {
            self.dots_per_mode += 1;
            self.ly += 1;

            if (self.ly == 153) {
                // We need to clear the visible sprites buffer before drawing the next line;
                self.visible_sprites = .{};
                self.dots_per_mode = 0;
                self.ly = 0;
                self.stat.mode = .oam_scan;
            }
        },
    }
}

fn read_vram(self: *const PPU, addr: u16) u8 {
    return self.vram[addr - 0x8000];
}

/// This is not excusable for a language to require. I love Zig, but come on.
fn add_as_signed(lhs: u16, rhs: u8) u16 {
    const signed_rhs: i16 = @as(i8, @bitCast(rhs));
    return lhs +% @as(u16, @bitCast(signed_rhs));
}

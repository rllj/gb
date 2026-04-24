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
pub const TILE_DATA_MIDDLE: u16 = 0x9000;
pub const TILE_DATA_END: u16 = 0x9800;

pub const TILE_MAP_0_START = 0x9800;
pub const TILE_MAP_0_END = 0x9BFF;
pub const TILE_MAP_1_START = 0x9C00;
pub const TILE_MAP_1_END = 0x9FFF;

pub const OAM_START = 0xFE00;

// Externally adressable registers
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

/// The "stat line" is what the Pandocs call a shared state between each of the
/// possible stat interrupts. The actual STAT interrupt is triggered by a rising
/// edge on the shared STAT line, meaning we need to store the prevous state
/// here.
stat_line: u1 = 0,

oam: []u8,
vram: []u8,

dots_per_mode: usize = 0,
scanline_pixels_consumed: u8 = 0,
scanline_pixels_drawn: u8 = 0,
visible_sprites: BoundedArray(u8, 10) = .{},
window_y: u8 = 0,
has_ly_matched_wy: bool = false,
fetcher: Fetcher = .{},
bg_window_fifo: Fifo(PixelRow) = .{},
sprite_fifo: Fifo(SpritePixelRow) = .{},
layer: Layer = .background,

// TODO The PPU shouldn't own the display, of course
display: [160 * 144]u32 = .{0x00} ** (160 * 144),

const PixelRow = [8]u2;

const SpritePixelRow = [8]SpritePixel;
const SpritePixel = struct {};

pub fn Fifo(T: type) type {
    return struct {
        const Self = @This();

        pixel_row: T = std.mem.zeroes(T),
        len: u8 = 0,

        pub fn try_enqueue_row(self: *Self, row: T) bool {
            if (self.len == 0) {
                self.enqueue_row(row);
                return true;
            }
            return false;
        }

        fn enqueue_row(self: *Self, row: T) void {
            self.pixel_row = row;
            self.len += 8;
        }

        pub fn dequeue(self: *Self) @typeInfo(T).array.child {
            const pixel = self.pixel_row[7];
            @memmove(self.pixel_row[1..], self.pixel_row[0..7]);
            self.len -= 1;
            return pixel;
        }
    };
}

const Fetcher = struct {
    state: FetchState = .fetch_tile,
    wait: bool = false,
    buffer: [8]u2 = .{0} ** 8,
    curr_tile: u8 = 0,

    pub fn consume(self: *Fetcher) [8]u2 {
        assert(self.state == .idle);
        self.state = .fetch_tile;
        return self.buffer;
    }

    fn advance(self: *Fetcher) bool {
        defer self.wait = !self.wait;
        return self.wait;
    }

    const FetchState = enum {
        fetch_tile,
        fetch_low,
        fetch_high,
        idle,
    };
};

const FetcherBuffer = struct {
    buffer: u16 = 0,
    len: u4 = 0,

    pub fn enqueue(self: *FetcherBuffer, pixel: u2) void {
        self.buffer |= @as(u16, pixel) << (14 - self.len * 2);
        self.len += 1;
    }
};

const Layer = enum {
    background,
    window,
    sprite,
};

const ObjectAttribute = packed struct(u32) {
    y_pos: u8,
    x_pos: u8,
    tile_idx: u8,
    flags: Flags,

    const Flags = packed struct(u8) {
        priority: bool,
        y_flip: bool,
        x_flip: bool,
        dmg_palette: u1,
        cgb_reserved: u4,
    };
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

/// To be called at 4.194304 MHz.
pub fn dot(self: *PPU, bus: *Pins) void {
    if (self.lcdc.lcd_enable == 0) return;

    self.stat.ly_lyc_eq = self.ly == self.lyc;

    const sprite_height: u8 = if (self.lcdc.obj_size == 0) 8 else 16;

    switch (self.stat.mode) {
        .oam_scan => {
            if (self.dots_per_mode == 0) {
                if (self.ly == self.wy) self.has_ly_matched_wy = true;
            }

            self.dots_per_mode += 1;
            if (self.dots_per_mode == 80) {
                // TODO cycle-step
                var i: u8 = 0;
                while (i < 40) : (i += 4) {
                    const y_pos = self.oam[i];
                    const x_pos = self.oam[i + 1];
                    if (y_pos != 0 and self.ly + 16 >= y_pos and
                        self.ly + 16 < y_pos + sprite_height and
                        self.visible_sprites.len < 10 and x_pos != 0)
                    {
                        self.visible_sprites.push(i / 4);
                    }
                }

                self.stat.mode = .draw;
            }
        },
        .draw => {
            if (self.lcdc.window_enable == 1 and self.has_ly_matched_wy) {
                if (self.scanline_pixels_consumed + 7 == self.wx and self.layer != .window) {
                    // self.layer = .window;
                    // self.fetcher = .{};
                    // self.bg_window_fifo = .{};
                }
            }

            switch (self.layer) {
                // .background => self.dot_bg(),
                // .window => self.dot_window(),
                // .sprite => self.dot_sprite(),
                else => self.dot_bg(),
            }

            self.dots_per_mode += 1;
            if (self.scanline_pixels_drawn == 160) {
                if (self.layer == .window) self.window_y += 1;
                self.reset_scanline();
                self.stat.mode = .hblank;
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
                    self.dots_per_mode = 0;
                }
            }
        },
        .vblank => {
            if (self.dots_per_mode == 456) {
                if (self.ly == 143) bus.int.vblank = 1;
                self.has_ly_matched_wy = false;
            }

            if (self.dots_per_mode % 456 == 0) {
                self.ly += 1;
            }

            self.dots_per_mode += 1;

            if (self.ly == 154) {
                self.dots_per_mode = 0;
                self.ly = 0;
                self.window_y = 0;
                self.stat.mode = .oam_scan;
            }
        },
    }

    const stat_int: u1 = @intFromBool((self.stat.ly_lyc_eq and self.stat.lyc_stat_int) or
        (self.stat.mode == .hblank and self.stat.mode_0_stat_int) or
        (self.stat.mode == .vblank and self.stat.mode_1_stat_int) or
        (self.stat.mode == .oam_scan and self.stat.mode_2_stat_int));

    if (stat_int == 1 and self.stat_line == 0) {
        bus.int.status = 1;
    }
    self.stat_line = stat_int;
}

fn dot_bg(self: *PPU) void {
    const scanline_x = self.scx +% self.scanline_pixels_drawn;
    const scanline_y = self.scy +% self.ly;
    self.fetcher_tick(scanline_x, scanline_y);

    if (self.bg_window_fifo.len > 0) {
        const pixel = self.bg_window_fifo.dequeue();
        if (self.scanline_pixels_consumed > 7 + (self.scx % 8)) {
            self.put_pixel(pixel);
        }
        self.scanline_pixels_consumed += 1;
    } else if (self.fetcher.state == .idle) {
        self.bg_window_fifo.enqueue_row(self.fetcher.consume());
    }
}
fn dot_window(self: *PPU) void {
    _ = self;
}
fn dot_sprite(self: *PPU) void {
    _ = self;
}

fn fetcher_tick(self: *PPU, scanline_x: u8, scanline_y: u8) void {
    switch (self.fetcher.state) {
        .fetch_tile => {
            if (self.fetcher.advance()) {
                const x: u16 = scanline_x / 8;
                const y: u16 = scanline_y / 8;

                var tilemap_address: u16 = TILE_MAP_0_START;
                if (self.lcdc.bg_tilemap_area == 1 and self.layer != .window) {
                    tilemap_address = TILE_MAP_1_START;
                }
                if (self.lcdc.window_tilemap_area == 1 and self.layer == .window) {
                    tilemap_address = TILE_MAP_1_START;
                }

                const idx = x + y * 32;
                self.fetcher.curr_tile = self.read_vram(tilemap_address + idx);

                self.fetcher.state = .fetch_low;
            }
        },
        .fetch_low => {
            if (self.fetcher.advance()) {
                const tile_data_base = switch (self.lcdc.bg_window_addressing_mode) {
                    0 => signed_tile_index(TILE_DATA_MIDDLE, self.fetcher.curr_tile),
                    1 => TILE_DATA_START + @as(u16, self.fetcher.curr_tile) * 16,
                };
                const y: u8 = scanline_y % 8;

                const tile_data_idx = tile_data_base + y * 2;
                const tile_data = self.read_vram(tile_data_idx);

                for (0..8) |idx| {
                    const i: u3 = @truncate(7 - idx);
                    const bit: u2 = @truncate((tile_data >> i) & 1);
                    self.fetcher.buffer[i] = bit;
                }

                self.fetcher.state = .fetch_high;
            }
        },
        .fetch_high => {
            if (self.fetcher.advance()) {
                const tile_data_base = switch (self.lcdc.bg_window_addressing_mode) {
                    0 => signed_tile_index(TILE_DATA_MIDDLE, self.fetcher.curr_tile),
                    1 => TILE_DATA_START + @as(u16, self.fetcher.curr_tile) * 16,
                };
                const y: u8 = scanline_y % 8;

                const tile_data_idx = tile_data_base + y * 2 + 1;
                const tile_data = self.read_vram(tile_data_idx);

                for (0..8) |idx| {
                    const i: u3 = @truncate(7 - idx);
                    const bit: u2 = @truncate((tile_data >> i) & 1);
                    self.fetcher.buffer[i] |= bit << 1;
                }

                self.fetcher.state = .idle;
            }
        },
        .idle => {},
    }
}

fn read_vram(self: *const PPU, addr: u16) u8 {
    return self.vram[addr - 0x8000];
}

fn signed_tile_index(base_addr: u16, offset: u8) u16 {
    const signed_offset: i16 = @as(i8, @bitCast(offset));
    const base_addr_signed: i16 = @bitCast(base_addr);
    return @bitCast(base_addr_signed +% signed_offset * 16);
}

fn put_pixel(self: *PPU, pixel: u2) void {
    // Since we've already written to the "invisible" left part of the screen, we need to offset the scanline pixel.
    const pixel_pos = @as(u16, self.scanline_pixels_drawn) + @as(u16, self.ly) * 160;
    const colour =
        if (self.lcdc.bg_window_enable == 1)
            self.bgp.from_index(pixel)
        else
            self.bgp.from_index(0);
    self.display[pixel_pos] = colour.rgba_8_8_8_8();
    self.scanline_pixels_drawn += 1;
}

fn reset_scanline(self: *PPU) void {
    self.visible_sprites = .{};
    self.scanline_pixels_consumed = 0;
    self.scanline_pixels_drawn = 0;
    self.bg_window_fifo = .{};
    self.sprite_fifo = .{};
    self.layer = .background;
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

const assert = @import("std").debug.assert;

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

const Tile = struct {
    rows: [8]Row,

    const Row = packed struct(u16) {
        ls_bits: u8,
        ms_bits: u8,
    };

    pub fn get_pixel(self: Tile, x: u3, y: u3) u2 {
        const ls_bit: u1 = @truncate(self.rows[y].ls_bits >> x);
        const ms_bit: u1 = @truncate(self.rows[y].ms_bits >> x);

        const pixel: u2 = @as(u2, ms_bit) << 1 | ls_bit;
        return pixel;
    }
};

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

const Pixel = struct {
    colour_index: u2,
};

const PixelFifo = struct {
    pixels: u32 = 0,
    count: u8 = 0,

    pub fn enqueue_row(self: *PixelFifo, pixels: u16) void {
        assert(self.count == 0 or self.count == 8);
        if (self.count == 0) {
            self.pixels = pixels;
        } else {
            self.pixels &= 0xFFFF0000;
            self.pixels |= pixels;
        }
        self.count += 8;
    }

    pub fn dequeue(self: *PixelFifo) Pixel {
        assert(self.count > 8);
        const pixel: u2 = @truncate(self.pixels >> 30);
        self.pixels <<= 2;
        self.count -= 1;
        return .{ .colour_index = pixel };
    }
};

const Fetcher = struct {
    state: State = .fetch_tile,
    tilemap_idx: u16 = 0,
    fetched: u16 = 0,
    is_filled: bool = false,
    cycle: u1 = 0,
    x: u5 = 0,

    inline fn advance_cycle(self: *Fetcher) bool {
        defer self.cycle ^= 1;
        return self.cycle == 1;
    }

    pub fn read_pixels(self: *Fetcher) u16 {
        self.is_filled = false;
        return self.fetched;
    }

    const State = enum {
        fetch_tile,
        fetch_data_low,
        fetch_data_high,
        sleep,
    };

    const Tilemap = enum(u16) { tilemap0 = 0x9800, timemap1 = 0x9C00 };
};

pub fn fetcher_tick(self: *PPU) void {
    state: switch (self.fetcher.state) {
        .fetch_tile => {
            if (self.fetcher.advance_cycle()) {
                const tilemap_base = self.get_fetcher_tilemap();
                self.fetcher.tilemap_idx = tilemap_base + self.fetcher_x() + (self.fetcher_y() / 8) * 32;

                self.fetcher.state = .fetch_data_low;
            }
        },
        .fetch_data_low => {
            if (self.fetcher.advance_cycle()) {
                const tile_offset = self.read_vram(self.fetcher.tilemap_idx);
                const tile_idx: u16 = switch (self.lcdc.bg_window_addressing_mode) {
                    0 => TILE_DATA_START + tile_offset,
                    1 => add_as_signed(TILE_DATA_MIDDLE, tile_offset),
                };
                const tile_data_low = self.read_vram(tile_idx + self.fetcher_y() % 8);

                for (0..8) |i| {
                    const bit: u16 = (tile_data_low >> @truncate(i)) & 1;
                    self.fetcher.fetched |= bit << @truncate(i * 2);
                }

                self.fetcher.state = .fetch_data_high;
            }
        },
        .fetch_data_high => {
            if (self.fetcher.advance_cycle()) {
                const tile_offset = self.read_vram(self.fetcher.tilemap_idx);
                const tile_idx = switch (self.lcdc.bg_window_addressing_mode) {
                    0 => TILE_DATA_START + tile_offset,
                    1 => add_as_signed(TILE_DATA_MIDDLE, tile_offset),
                };
                const tile_data_high = self.read_vram(tile_idx + self.fetcher_y() % 8 + 1);

                for (0..8) |i| {
                    const bit: u16 = (tile_data_high >> @truncate(i)) & 1;
                    self.fetcher.fetched |= bit << @truncate(i * 2 + 1);
                }

                self.fetcher.x += 1;
                self.fetcher.state = .sleep;
                self.fetcher.is_filled = true;
            }
        },
        .sleep => {
            if (!self.fetcher.is_filled) {
                self.fetcher.state = .fetch_tile;
                continue :state .fetch_tile;
            }
        },
    }
}

fn get_fetcher_tilemap(self: *const PPU) u16 {
    if (self.lcdc.bg_tilemap_area == 1 and !self.is_in_window(self.fetcher_x())) {
        return 0x9C00;
    }
    if (self.lcdc.window_tilemap_area == 1 and self.is_in_window(self.fetcher_x())) {
        return 0x9C00;
    }
    return 0x9800;
}

fn fetcher_x(self: *const PPU) u8 {
    return (self.scx / 8 + self.fetcher.x) & 0x1F;
}

fn fetcher_y(self: *const PPU) u8 {
    return self.ly +% self.scy;
}

fn is_in_window(self: *const PPU, x: u8) bool {
    _ = self;
    _ = x;
    // TODO
    return false;
}

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
current_pixel: u8 = 0,
visible_sprites: BoundedArray(ObjectAttribute, 10) = .{},
fifo: PixelFifo = .{},
fetcher: Fetcher = .{},

display: [160 * 144]u8 = .{0xFF} ** (160 * 144),

fn put_pixel(self: *PPU, pixel: Pixel) void {
    const colour: u8 = switch (pixel.colour_index) {
        0b00 => 0x00,
        0b01 => 0x10,
        0b10 => 0x80,
        0b11 => 0xFF,
    };
    const x: u16 = self.current_pixel;
    const y: u16 = self.ly;
    const idx = x + y * 160;
    self.display[idx] = colour;
}

/// To be called at 4.194304 MHz.
pub fn dot(self: *PPU) void {

    // TODO trigger interrupts
    self.stat.ly_lyc_eq = self.ly == self.lyc;

    const sprite_height: u8 = if (self.lcdc.obj_size == 0) 8 else 16;

    const background_left = self.scx;
    const background_top = self.scy;
    const background_right = self.scx +% 159;
    const background_bottom = self.scy +% 143;

    _ = background_left;
    _ = background_top;
    _ = background_right;
    _ = background_bottom;

    switch (self.stat.mode) {
        .oam_scan => {
            self.current_pixel = 0;
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

            self.fetcher_tick();
            if (self.fifo.count > 8) {
                self.put_pixel(self.fifo.dequeue());
                self.current_pixel += 1;
            } else if (self.fetcher.state == .sleep) {
                self.fifo.enqueue_row(self.fetcher.read_pixels());
            }

            // Perform two tile fetches.
            // take SCX % 8 dots to discard the same amount from the first tile.
            // discard the second.

            // Alternatively: self.current_pixel == 160
            if (self.fetcher.x == 20) {
                self.stat.mode = .hblank;
            }
        },
        .hblank => {
            self.dots_per_mode += 1;
            self.current_pixel = 0;

            if (self.dots_per_mode == 456) {
                self.ly += 1;
                self.stat.mode = if (self.ly == 144) .vblank else .oam_scan;
                self.dots_per_mode = 0;
            }
        },
        .vblank => {
            self.dots_per_mode += 1;

            if (self.dots_per_mode == 4560 + 456) {
                // We need to clear the visible sprites buffer before drawing the next line;
                self.visible_sprites = .{};
                self.fetcher = .{};
                self.dots_per_mode = 0;
                self.ly = 0;

                if (self.ly < 144) {
                    self.stat.mode = .oam_scan;
                } else {
                    self.stat.mode = .hblank;
                }
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

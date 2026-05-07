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

pub const LCD_WIDTH = 160;

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

dots_per_frame: usize = 0,
lx: u8 = 0,
pixels_to_discard: u3 = 0,
visible_sprites: BoundedArray(ObjectAttributes, 10) = .{},
internal_wy: u8 = 0,
has_ly_matched_wy: bool = false,
fetcher: Fetcher = .{},
bg_window_fifo: Fifo(PixelRow) = .{},
obj_fifo: Fifo(SpritePixelRow) = .{},
layer: Layer = .background,
is_fetching_obj: bool = false,

// TODO The PPU shouldn't own the display, of course
display: [160 * 144]u32 = .{0x00} ** (160 * 144),

const PixelRow = [8]u2;

const SpritePixelRow = [8]SpritePixel;
const SpritePixel = struct {
    color: u2 = 0,
    palette: u1 = 0,
    bg_priority: bool = false,
};

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
            self.len = 8;
        }

        pub fn dequeue(self: *Self) @typeInfo(T).array.child {
            const pixel = self.pixel_row[7];
            @memmove(self.pixel_row[1..], self.pixel_row[0..7]);
            self.pixel_row[0] = std.mem.zeroes(@typeInfo(T).array.child);
            self.len -|= 1;
            return pixel;
        }
    };
}

const Fetcher = struct {
    state: FetchState = .fetch_tile,
    wait: bool = false,
    buffer: [8]u2 = .{0} ** 8,
    curr_tile: u8 = 0,
    curr_sprite: ObjectAttributes = .{},
    tile_x: u8 = 0xFF,

    pub fn consume(self: *Fetcher) [8]u2 {
        assert(self.state == .idle or self.state == .fetch_obj_high);
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

        fetch_obj,
        fetch_obj_low,
        fetch_obj_high,
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
};

const ObjectAttributes = packed struct(u32) {
    y_pos: u8 = 0,
    x_pos: u8 = 0,
    tile_idx: u8 = 0,
    flags: Flags = @bitCast(@as(u8, 0)),

    const Flags = packed struct(u8) {
        cgb_reserved: u4 = 0,
        dmg_palette: u1,
        x_flip: bool,
        y_flip: bool,
        priority: bool,
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
            if (self.dots_per_frame == 0) {
                if (self.ly == self.wy) self.has_ly_matched_wy = true;
            }

            self.dots_per_frame += 1;
            if (self.dots_per_frame == 80) {
                var i: u8 = 0;
                while (i < 160) : (i += 4) {
                    const y_pos = self.oam[i];
                    const x_pos = self.oam[i + 1];
                    const tile_idx = self.oam[i + 2];
                    const flags: ObjectAttributes.Flags = @bitCast(self.oam[i + 3]);
                    if (y_pos != 0 and self.ly + 16 >= y_pos and
                        self.ly + 16 < y_pos + sprite_height and
                        self.visible_sprites.len < 10 and x_pos != 0)
                    {
                        self.visible_sprites.push(.{
                            .x_pos = x_pos,
                            .y_pos = y_pos,
                            .tile_idx = tile_idx,
                            .flags = flags,
                        });
                    }
                }
                // TODO sorting network
                const sort_func = struct {
                    pub fn cmp(_: void, lhs_oa: ObjectAttributes, rhs_oa: ObjectAttributes) bool {
                        return lhs_oa.x_pos < rhs_oa.x_pos;
                    }
                }.cmp;
                std.sort.insertion(ObjectAttributes, self.visible_sprites.slice(), {}, sort_func);
                std.mem.reverse(ObjectAttributes, self.visible_sprites.slice());
                self.pixels_to_discard = @truncate(self.scx);
                self.stat.mode = .draw;
            }
        },
        .draw => {
            if (self.lcdc.window_enable == 1 and self.has_ly_matched_wy) {
                if (self.lx == self.wx + 1 and self.layer != .window) {
                    self.layer = .window;
                    self.fetcher = .{ .tile_x = 0 };
                    self.bg_window_fifo = .{};
                }
            }

            if (!self.is_fetching_obj) {
                if (switch (self.layer) {
                    .background => self.dot_bg(),
                    .window => self.dot_window(),
                }) |bg_window_pixel| {
                    const obj_pixel = self.obj_fifo.dequeue();
                    self.put_pixel(self.merge_pixels(bg_window_pixel, obj_pixel), self.lx);
                    self.lx += 1;
                }
                if (self.visible_sprites.last()) |sprite| {
                    if (sprite.x_pos == self.lx) {
                        self.is_fetching_obj = true;
                    }
                }
            } else {
                self.dot_sprite();
            }

            self.dots_per_frame += 1;
            if (self.lx == LCD_WIDTH + 8) {
                if (self.layer == .window) self.internal_wy += 1;
                self.reset_scanline();
                self.stat.mode = .hblank;
            }
        },
        .hblank => {
            self.dots_per_frame += 1;

            if (self.dots_per_frame == 456) {
                if (self.ly == 143) {
                    self.stat.mode = .vblank;
                } else {
                    self.stat.mode = .oam_scan;
                    self.ly += 1;
                    self.dots_per_frame = 0;
                }
            }
        },
        .vblank => {
            if (self.dots_per_frame == 456) {
                if (self.ly == 143) bus.int.vblank = 1;
                self.has_ly_matched_wy = false;
            }

            if (self.dots_per_frame % 456 == 0) {
                self.ly += 1;
            }

            self.dots_per_frame += 1;

            if (self.ly == 154) {
                self.dots_per_frame = 0;
                self.ly = 0;
                self.internal_wy = 0;
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

fn dot_bg(self: *PPU) ?u2 {
    const scanline_y = self.scy +% self.ly;
    self.fetcher_tick(scanline_y);

    if (self.bg_window_fifo.len > 0) {
        const pixel = self.bg_window_fifo.dequeue();
        if (self.pixels_to_discard > 0) {
            self.pixels_to_discard -= 1;
        } else {
            return pixel;
        }
    } else if (self.fetcher.state == .idle) {
        self.bg_window_fifo.enqueue_row(self.fetcher.consume());
    }
    return null;
}
fn dot_window(self: *PPU) ?u2 {
    const scanline_y = self.internal_wy;
    self.fetcher_tick(scanline_y);

    if (self.bg_window_fifo.len > 0) {
        return self.bg_window_fifo.dequeue();
    } else if (self.fetcher.state == .idle) {
        self.bg_window_fifo.enqueue_row(self.fetcher.consume());
    }
    return null;
}
fn dot_sprite(self: *PPU) void {
    const scanline_y = self.ly;
    if (self.bg_window_fifo.len == 0) {
        self.fetcher_tick(scanline_y);
        if (self.fetcher.state == .idle) {
            self.bg_window_fifo.enqueue_row(self.fetcher.consume());
        }
    } else {
        self.fetcher_tick(scanline_y);
        if (self.fetcher.state == .idle) {
            self.fetcher.wait = false;
            self.fetcher.state = .fetch_obj;
        }
    }
}

fn merge_pixels(self: *PPU, bg_window_pixel: u2, obj_pixel: SpritePixel) Colour {
    const bg_colour = if (self.lcdc.bg_window_enable == 1)
        self.bgp.from_index(bg_window_pixel)
    else
        self.bgp.from_index(0);

    if (self.lcdc.obj_enable == 0 or obj_pixel.color == 0) {
        return bg_colour;
    }

    if (self.lcdc.bg_window_enable == 1 and obj_pixel.bg_priority and bg_window_pixel != 0) {
        return bg_colour;
    }

    const obj_palette = if (obj_pixel.palette == 0) self.obp0 else self.obp1;
    return obj_palette.from_index(obj_pixel.color);
}

fn fetcher_tick(self: *PPU, scanline_y: u8) void {
    switch (self.fetcher.state) {
        .fetch_tile => {
            if (self.fetcher.advance()) {
                const scroll = if (self.layer == .background) self.scx else 0;
                const x: u5 = @truncate(self.fetcher.tile_x +% scroll / 8);
                const y: u5 = @truncate(scanline_y / 8);

                const tilemap_address: u1 = if (self.layer == .background)
                    self.lcdc.bg_tilemap_area
                else
                    self.lcdc.window_tilemap_area;

                const base_address: u16 = 0b1001100000000000;
                const idx = base_address | (@as(u11, tilemap_address) << 10) | (@as(u10, y) << 5) | x;

                self.fetcher.curr_tile = self.read_vram(idx);
                self.fetcher.state = .fetch_low;
                self.fetcher.tile_x +%= 1;
            }
        },
        .fetch_low => {
            if (self.fetcher.advance()) {
                self.fetch_tile_byte(scanline_y, .low);
                self.fetcher.state = .fetch_high;
            }
        },
        .fetch_high => {
            if (self.fetcher.advance()) {
                self.fetch_tile_byte(scanline_y, .high);
                self.fetcher.state = .idle;
            }
        },
        .idle => {},

        .fetch_obj => {
            if (self.fetcher.advance()) {
                const sprite = self.visible_sprites.pop();

                self.fetcher.curr_tile = sprite.tile_idx;
                self.fetcher.curr_sprite = sprite;
                self.fetcher.state = .fetch_obj_low;
            }
        },
        .fetch_obj_low => {
            if (self.fetcher.advance()) {
                self.fetch_obj_byte(scanline_y, .low);
                self.fetcher.state = .fetch_obj_high;
            }
        },
        .fetch_obj_high => {
            if (self.fetcher.advance()) {
                self.fetch_obj_byte(scanline_y, .high);

                for (0..8) |i| {
                    const color = self.fetcher.buffer[i];
                    if (color != 0 and self.obj_fifo.pixel_row[i].color == 0) {
                        self.obj_fifo.pixel_row[i] = .{
                            .color = color,
                            .palette = self.fetcher.curr_sprite.flags.dmg_palette,
                            .bg_priority = self.fetcher.curr_sprite.flags.priority,
                        };
                    }
                }
                self.obj_fifo.len = 8;

                self.fetcher.tile_x -= 1;
                self.fetcher.state = .fetch_tile;
                self.is_fetching_obj = false;
            }
        },
    }
}

fn fetch_tile_byte(
    self: *PPU,
    scanline_y: u8,
    comptime low_or_high: enum { low, high },
) void {
    const tile_data_base = switch (self.lcdc.bg_window_addressing_mode) {
        0 => signed_tile_index(TILE_DATA_MIDDLE, self.fetcher.curr_tile),
        1 => TILE_DATA_START + @as(u16, self.fetcher.curr_tile) * 16,
    };
    const y: u8 = scanline_y % 8;

    const tile_data_idx = tile_data_base + y * 2 + @intFromEnum(low_or_high);
    const tile_data = self.read_vram(tile_data_idx);

    for (0..8) |idx| {
        const i: u3 = @truncate(7 - idx);
        const bit: u2 = @truncate((tile_data >> i) & 1);
        if (low_or_high == .low) {
            self.fetcher.buffer[i] = bit;
        } else {
            self.fetcher.buffer[i] |= bit << 1;
        }
    }
}

fn fetch_obj_byte(
    self: *PPU,
    scanline_y: u8,
    comptime low_or_high: enum { low, high },
) void {
    const sprite = self.fetcher.curr_sprite;
    const sprite_height: u8 = if (self.lcdc.obj_size == 1) 16 else 8;

    var y: u8 = (scanline_y + 16) - sprite.y_pos;
    if (sprite.flags.y_flip) {
        y = sprite_height - 1 - y;
    }

    var tile_id = self.fetcher.curr_tile;
    if (self.lcdc.obj_size == 1) {
        tile_id &= 0xFE;
        if (y >= 8) {
            tile_id |= 1;
        }
    }

    const tile_data_base = TILE_DATA_START + @as(u16, tile_id) * 16;
    const tile_data_idx = tile_data_base + y * 2 + @intFromEnum(low_or_high);
    const tile_data = self.read_vram(tile_data_idx);

    for (0..8) |idx| {
        const shift = if (sprite.flags.x_flip) 7 - idx else idx;
        const bit: u2 = @truncate((tile_data >> @truncate(shift)) & 1);
        if (low_or_high == .low) {
            self.fetcher.buffer[idx] = bit;
        } else {
            self.fetcher.buffer[idx] |= bit << 1;
        }
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

fn put_pixel(self: *PPU, colour: Colour, x_coord: u8) void {
    if (x_coord >= 8) {
        const x = x_coord - 8;
        if (x < 160) {
            const pixel_pos = @as(u16, x) + @as(u16, self.ly) * 160;
            self.display[pixel_pos] = colour.rgba_8_8_8_8();
        }
    }
}

fn reset_scanline(self: *PPU) void {
    self.visible_sprites = .{};
    self.lx = 0;
    self.bg_window_fifo = .{};
    self.obj_fifo = .{};
    self.layer = .background;
    self.fetcher = .{};
}

pub fn debug_generate_tilemap(self: *PPU, comptime tilemap: u1, colours: []u32) void {
    const tilemap_start = (if (tilemap == 0) TILE_MAP_0_START else TILE_MAP_1_START) - 0x8000;
    const tilemap_end = tilemap_start + 1024;

    for (self.vram[tilemap_start..tilemap_end], 0..) |tile_idx, vert| {
        const row_x = vert % 32;
        const row_y = vert / 32;
        const from = if (self.lcdc.bg_window_addressing_mode == 0)
            signed_tile_index(TILE_DATA_MIDDLE, tile_idx) - 0x8000
        else
            @as(usize, tile_idx) * 16;

        for (0..8) |i| {
            const low = self.vram[from + i * 2];
            const high = self.vram[from + i * 2 + 1];

            var row_colours: [8]u32 = undefined;
            for (0..8) |shift| {
                const s: u3 = @truncate(7 - shift);
                const colour_idx = (@as(u2, @truncate(high >> s)) & 1) << 1 |
                    (@as(u2, @truncate(low >> s)) & 1);
                const colour: Colour = self.bgp.from_index(colour_idx);
                row_colours[shift] = colour.rgba_8_8_8_8();
            }

            const dst_start = row_y * 8 * 256 + i * 256 + row_x * 8;
            @memcpy(colours[dst_start .. dst_start + 8], &row_colours);
        }
    }
}

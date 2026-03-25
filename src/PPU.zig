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

pub const TILE_DATA_START = 0x8000;
pub const TILE_DATA_END = 0x9800;

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

lcdc: LCDControl = .{},
stat: Status = @bitCast(@as(u8, 0)),
scy: u8 = 0,
scx: u8 = 0,
ly: u8 = 0,
lyc: u8 = 0,
bgp: Palette = @bitCast(@as(u8, 0)),
obp0: Palette = @bitCast(@as(u8, 0)),
obp1: Palette = @bitCast(@as(u8, 0)),

dots_per_mode: usize = 0,

display: [160 * 144]u8 = undefined,

// https://gbdev.io/pandocs/LCDC.html
const LCDControl = packed struct(u8) {
    bg_window_enable: u1 = 0,
    obj_enable: u1 = 0,
    obj_size: u1 = 0,
    bg_tile_map_area: u1 = 0,
    bg_window_addressing_mode: u1 = 0,
    window_enable: u1 = 0,
    window_tile_map_area: u1 = 0,
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

/// To be called at 4.194304 MHz.
pub fn dot(self: *PPU) void {
    // TODO trigger interrupts
    self.stat.ly_lyc_eq = self.ly == self.lyc;

    const background_left = self.scx;
    const background_top = self.scy;
    const background_right = self.scx +% 159;
    const background_bottom = self.scy +% 143;

    _ = background_left;
    _ = background_top;
    _ = background_right;
    _ = background_bottom;

    switch (self.mode) {
        .oam_scan => {
            self.dots_per_mode += 1;

            if (self.dots_per_mode == 80) {
                self.mode = .draw;
            }
        },
        .draw => {
            self.dots_per_mode += 1;

            // Perform two tile fetches.
            // take SCX % 8 dots to discard the same amount from the first tile.
            // discard the second.

            if (self.dots_per_mode == 172 + 80) {
                self.mode = .hblank;
            }
        },
        .hblank => {
            self.dots_per_mode += 1;

            if (self.dots_per_mode == 456) {
                self.mode = if (self.ly == 144) .vblank else .hblank;
                self.dots_per_mode = 0;
            }
        },
        .vblank => {
            self.dots_per_mode += 1;

            if (self.dots_per_mode == 456) {
                self.dots_per_mode = 0;
                self.ly += 1;

                if (self.ly < 144) {
                    self.mode = .oam_scan;
                } else {
                    self.mode = .hblank;
                }
            }
        },
    }
    self.dots += 1;
}

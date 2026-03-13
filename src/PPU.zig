const PPU = @This();

const MMIO = extern struct {
    lcdc: u8,
    stat: u8,
    scy: u8,
    scx: u8,
    ly: u8,
    lyc: u8,
};

mmio: *MMIO,
mode: Mode = .oam_scan,
dots_per_mode: usize = 0,

const Mode = enum(u2) {
    hblank = 0,
    vblank = 1,
    oam_scan = 2,
    draw = 3,
};

const Pixel = struct {
    colour_index: u2,
};

/// To be called at 4.194304 MHz.
pub fn dot(self: *PPU) void {
    switch (self.mode) {
        .hblank => {
            self.dots_per_mode += 1;

            if (self.dots_per_mode == 376) {
                self.dots_per_mode = 0;
                // self.mode = ;
            }
        },
        .vblank => {
            self.dots_per_mode += 1;
        },
        .oam_scan => {
            self.dots_per_mode += 1;
        },
        .draw => {
            self.dots_per_mode += 1;
        },
    }
    self.dots += 1;
}

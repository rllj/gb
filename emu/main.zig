const std = @import("std");
const allocator = std.heap.page_allocator;

const sdl3 = @import("sdl3");

const GB = @import("GB").GB;

const SCREEN_WIDTH = 640;
const SCREEN_HEIGHT = 576;

pub fn main(init: std.process.Init) !void {
    defer sdl3.shutdown();

    const init_flags = sdl3.InitFlags{ .video = true };
    try sdl3.init(init_flags);
    defer sdl3.quit(init_flags);

    var main_view: View = try .init("Gameboy!", SCREEN_WIDTH, SCREEN_HEIGHT, 160, 144);
    defer main_view.deinit();

    const tile_data_0 = try allocator.alloc(u32, 256 * 256);
    defer allocator.free(tile_data_0);
    var tile_view_0: View = try .init("Tilemap 0", 512, 512, 256, 256);
    defer tile_view_0.deinit();

    const tile_data_1 = try allocator.alloc(u32, 256 * 256);
    defer allocator.free(tile_data_1);
    var tile_view_1: View = try .init("Tilemap 1", 512, 512, 256, 256);
    defer tile_view_1.deinit();

    try main_view.window.raise();

    var gb: GB = try .init(init.gpa, @embedFile("roms/dmg-acid2.gb"));
    defer gb.deinit(init.gpa);

    var fps_capper = sdl3.extras.FramerateCapper(f32){ .mode = .{ .limited = 60 } };

    var quit = false;
    while (!quit) {
        gb.tick_tcycle();

        if (gb.ppu.dots_per_frame == 456) {
            _ = fps_capper.delay();

            gb.ppu.debug_generate_tilemap(0, tile_data_0);
            try tile_view_0.render(tile_data_0);

            gb.ppu.debug_generate_tilemap(1, tile_data_1);
            try tile_view_1.render(tile_data_1);

            try main_view.render(&gb.ppu.display);

            while (sdl3.events.poll()) |event|
                switch (event) {
                    .quit => quit = true,
                    .terminating => quit = true,
                    .key_down => |keyboard| {
                        switch (keyboard.key.?) {
                            .k => gb.buttons.a = true,
                            .l => gb.buttons.b = true,
                            .h => gb.buttons.select = true,
                            .j => gb.buttons.start = true,

                            .w => gb.buttons.up = true,
                            .a => gb.buttons.left = true,
                            .s => gb.buttons.down = true,
                            .d => gb.buttons.right = true,
                            else => {},
                        }
                    },
                    .key_up => |keyboard| {
                        switch (keyboard.key.?) {
                            .k => gb.buttons.a = false,
                            .l => gb.buttons.b = false,
                            .h => gb.buttons.select = false,
                            .j => gb.buttons.start = false,

                            .w => gb.buttons.up = false,
                            .a => gb.buttons.left = false,
                            .s => gb.buttons.down = false,
                            .d => gb.buttons.right = false,
                            else => {},
                        }
                    },
                    else => {},
                };
        }
    }
}

const View = struct {
    renderer: sdl3.render.Renderer,
    window: sdl3.video.Window,
    texture: sdl3.render.Texture,

    pub fn init(
        name: [:0]const u8,
        screen_width: usize,
        screen_height: usize,
        texture_width: usize,
        texture_height: usize,
    ) !View {
        const window, const renderer = try sdl3.render.Renderer.initWithWindow(
            name,
            screen_width,
            screen_height,
            .{},
        );
        const texture: sdl3.render.Texture = try renderer.createTexture(
            .packed_rgba_8_8_8_8,
            .streaming,
            texture_width,
            texture_height,
        );
        try texture.setScaleMode(.nearest);

        return .{
            .window = window,
            .renderer = renderer,
            .texture = texture,
        };
    }

    pub fn deinit(self: *View) void {
        self.texture.deinit();
        self.renderer.deinit();
        self.window.deinit();
    }

    pub fn render(self: *View, texture: []const u32) !void {
        const data, _ = try self.texture.lock(null);
        @memcpy(data, std.mem.sliceAsBytes(texture));
        self.texture.unlock();

        try self.renderer.clear();
        try self.renderer.renderTexture(self.texture, null, null);
        try self.renderer.present();
    }
};

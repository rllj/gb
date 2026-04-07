const std = @import("std");
const allocator = std.heap.page_allocator;

const sdl3 = @import("sdl3");

const GB = @import("GB").GB;

const SCREEN_WIDTH = 640;
const SCREEN_HEIGHT = 576;

// TODO clean up
pub fn main(init: std.process.Init) !void {
    defer sdl3.shutdown();

    const init_flags = sdl3.InitFlags{ .video = true };
    try sdl3.init(init_flags);
    defer sdl3.quit(init_flags);

    const window, const renderer = try sdl3.render.Renderer.initWithWindow("Gameboy", SCREEN_WIDTH, SCREEN_HEIGHT, .{});
    defer window.deinit();
    defer renderer.deinit();

    const texture: sdl3.render.Texture = try renderer.createTexture(.packed_rgba_8_8_8_8, .streaming, 160, 144);
    try texture.setScaleMode(.nearest);

    const window2, const renderer2 = try sdl3.render.Renderer.initWithWindow("Tilemap 0", 512, 512, .{});
    defer window2.deinit();
    defer renderer2.deinit();

    const window3, const renderer3 = try sdl3.render.Renderer.initWithWindow("Tilemap 1", 512, 512, .{});
    defer window3.deinit();
    defer renderer3.deinit();

    const texture_debug: sdl3.render.Texture = try renderer2.createTexture(.packed_rgba_8_8_8_8, .streaming, 256, 256);
    try texture_debug.setScaleMode(.nearest);

    const texture_debug2: sdl3.render.Texture = try renderer3.createTexture(.packed_rgba_8_8_8_8, .streaming, 256, 256);
    try texture_debug2.setScaleMode(.nearest);

    try window.raise();

    var gb: GB = try .init(init.gpa, @embedFile("roms/dmg-acid2.gb"));
    defer gb.deinit(init.gpa);

    var fps_capper = sdl3.extras.FramerateCapper(f32){ .mode = .{ .limited = 60 } };

    var stdout = std.Io.File.stdout();
    defer stdout.close(init.io);
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(init.io, &buffer);
    defer writer.flush() catch {};

    var quit = false;
    while (!quit) {
        gb.tick_mcycle();

        if (gb.ppu.dots_per_mode == 456) {
            _ = fps_capper.delay();

            {
                const data, _ = try texture.lock(null);
                @memcpy(data, std.mem.sliceAsBytes(&gb.ppu.display));
                texture.unlock();

                try renderer.clear();
                try renderer.renderTexture(texture, null, null);
                try renderer.present();
            }

            {
                const debug_data = try gb.ppu.debug_generate_tilemap(0, init.gpa);
                defer init.gpa.free(debug_data);
                const data, _ = try texture_debug.lock(null);
                @memcpy(data, std.mem.sliceAsBytes(debug_data));
                texture_debug.unlock();

                try renderer2.clear();
                try renderer2.renderTexture(texture_debug, null, null);
                try renderer2.present();
            }

            {
                const debug_data = try gb.ppu.debug_generate_tilemap(1, init.gpa);
                defer init.gpa.free(debug_data);
                const data, _ = try texture_debug2.lock(null);
                @memcpy(data, std.mem.sliceAsBytes(debug_data));
                texture_debug2.unlock();

                try renderer3.clear();
                try renderer3.renderTexture(texture_debug2, null, null);
                try renderer3.present();
            }

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

// pub fn main(init: std.process.Init) !void {
//     var stdout = std.Io.File.stdout();
//     defer stdout.close(init.io);
//     var buffer: [4096]u8 = undefined;
//     var writer = stdout.writer(init.io, &buffer);
//     defer writer.flush() catch {};
//
//     const start = std.Io.Clock.now(.awake, init.io);
//     var inst_cnt: usize = 0;
//     const cartridge = @embedFile("roms/07-jr,jp,call,ret,rst.gb");
//     var gb: GB = try .init(allocator, init.io, cartridge);
//     defer gb.deinit(allocator);
//     while (true) {
//         gb.tick();
//         inst_cnt += 1;
//         if (gb.serial_input.items.len > 7 and
//             (std.mem.eql(u8, gb.serial_input.items[gb.serial_input.items.len - 7 ..], "Passed\n") or
//                 std.mem.eql(u8, gb.serial_input.items[gb.serial_input.items.len - 6 ..], "Failed")))
//         {
//             break;
//         }
//     }
//     const elapsed = start.untilNow(init.io, .awake);
//     std.debug.print("{} cycles in {}µs.\n", .{ inst_cnt, @divFloor(elapsed.nanoseconds, 1000) });
// }

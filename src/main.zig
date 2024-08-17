const rl = @import("raylib");
const std = @import("std");
const GameLib = @import("gamelib.zig");

// Clouds - 145
// Clouds and sky - 161
// Sky - 177
fn generateBgTileData(allocator: std.mem.Allocator) ![][]u8 {
    var level_data_list = std.ArrayList([]u8).init(allocator);

    for (0..300) |y| {
        var row_list = std.ArrayList(u8).init(allocator);
        for (0..300) |x| {
            _ = x; // autofix
            // const tile: u8 = @intCast((1 + y + x) % 256);
            // try row_list.append(tile);
            if (y < 40) {
                try row_list.append(145);
            } else if (y == 40) {
                try row_list.append(161);
            } else if (y > 40 and y < 80) {
                try row_list.append(177);
            } else {
                try row_list.append(1);
            }
        }
        try level_data_list.append(try row_list.toOwnedSlice());
    }

    return level_data_list.toOwnedSlice();
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    // Initialization
    //--------------------------------------------------------------------------------------
    const display = rl.getCurrentMonitor();

    rl.initWindow(320, 240, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(120); // Set our game to run at 60 frames-per-second
    rl.toggleFullscreen();
    //--------------------------------------------------------------------------------------

    const screen_width = rl.getMonitorWidth(display);
    const screen_height = rl.getMonitorHeight(display);
    std.debug.print("Current monitor: {s}\n", .{rl.getMonitorName(display)});
    std.debug.print("screen width: {}, screen height: {}\n", .{ screen_width, screen_height });

    const screen_width_float: f32 = @floatFromInt(screen_width);
    const screen_height_float: f32 = @floatFromInt(screen_height);

    const viewport_padding_x = 20;
    const viewport_padding_y = 22;

    const tile_data = try generateBgTileData(allocator);
    defer allocator.free(tile_data);

    var viewport = GameLib.Viewport.init(rl.Rectangle.init(viewport_padding_x, viewport_padding_y, screen_width_float - (viewport_padding_x * 2), screen_height_float - (viewport_padding_y * 2)));

    const tilemap = try GameLib.Tilemap(512).init("assets/sprites/world_tileset.png", .{ .x = 16, .y = 16 }, allocator);

    const foreground_layer = GameLib.TileLayer.init(.{ .x = 300 * 16, .y = 300 * 16 }, tilemap, tile_data, .DoNotRepeat);

    var layers = [_]GameLib.TileLayer{foreground_layer};

    var level = try GameLib.Level.create(&layers, &viewport, allocator);
    defer level.destroy();

    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
        //----------------------------------------------------------------------------------
        const delta_time = rl.getFrameTime();

        viewport.update(delta_time);
        level.update(delta_time);

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);

        viewport.draw();
        level.draw();

        //----------------------------------------------------------------------------------
    }
}

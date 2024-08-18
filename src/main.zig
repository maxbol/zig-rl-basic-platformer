const rl = @import("raylib");
const std = @import("std");
const GameLib = @import("gamelib.zig");

// Clouds - 145
// Clouds and sky - 161
// Sky - 177
fn generateBgTileData() [1 * 35]u8 {
    var bg_tile_data: [1 * 35]u8 = undefined;

    for (0..35) |y| {
        for (0..1) |x| {
            bg_tile_data[y * 1 + x] = blk: {
                if (y < 3) {
                    break :blk 145;
                } else if (y == 3) {
                    break :blk 161;
                } else if (y > 3) {
                    break :blk 177;
                }
                break :blk 0;
            };
        }
    }

    return bg_tile_data;
}

fn generateFgTileData() [100 * 40]u8 {
    var fg_tile_data: [100 * 40]u8 = undefined;

    for (0..40) |y| {
        for (0..100) |x| {
            fg_tile_data[y * 100 + x] = blk: {
                if (y < 25) {
                    break :blk 0;
                } else if (y == 25) {
                    break :blk 1;
                } else if (y > 15) {
                    break :blk 17;
                }
                break :blk 0;
            };
        }
    }

    return fg_tile_data;
}

const PlayerAnimationBuffer = GameLib.AnimationBuffer(5, 16);
const MobAnimationBuffer = GameLib.AnimationBuffer(3, 6);

fn getPlayerAnimations() PlayerAnimationBuffer {
    var buffer = PlayerAnimationBuffer{};

    buffer.encodeAnimationData(.Idle, 0.5, for (1..4) |i| i);
    buffer.encodeAnimationData(.Walk, 1, for (17..32) |i| i);
    buffer.encodeAnimationData(.Roll, 0.8, for (49..56) |i| i);
    buffer.encodeAnimationData(.Hit, 0.5, for (57..60) |i| i);
    buffer.encodeAnimationData(.Death, 1, for (65..68) |i| i);

    return buffer;
}

fn getMobAnimations() MobAnimationBuffer {
    var buffer = MobAnimationBuffer{};

    buffer.encodeAnimationData(.Walk, 1, .{ 1, 2, 3, 4, 3, 2 });
    buffer.encodeAnimationData(.Attack, 0.5, for (5..8) |i| i);
    buffer.encodeAnimationData(.Hit, 0.5, for (9..12) |i| i);

    return buffer;
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

    var viewport = GameLib.Viewport.init(rl.Rectangle.init(viewport_padding_x, viewport_padding_y, screen_width_float - (viewport_padding_x * 2), screen_height_float - (viewport_padding_y * 2)));

    const tilemap = try GameLib.Tileset(512).init("assets/sprites/world_tileset.png", .{ .x = 16, .y = 16 }, allocator);

    var bg_tile_data = generateBgTileData();
    const bg_layer = GameLib.TileLayer.init(.{ .x = 70, .y = 35 }, 1, tilemap, &bg_tile_data, &.{}, GameLib.LayerFlag.compose(&.{}));

    var fg_tile_data = generateFgTileData();
    const fg_layer = GameLib.TileLayer.init(.{ .x = 100, .y = 40 }, 100, tilemap, &fg_tile_data, &.{}, GameLib.LayerFlag.compose(&.{.Collidable}));

    var layers = [_]GameLib.TileLayer{ bg_layer, fg_layer };

    const player_animations = getPlayerAnimations();
    const mob_animations = getMobAnimations();

    const player_sprite = try GameLib.Sprite.init(
        "assets/sprites/knight.png",
        .{ .x = 32, .y = 32 },
        rl.Rectangle.init(8, 8, 16, 16),
        rl.Vector2.init(0, 1),
        0,
        player_animations.reader(),
    );

    var scene = try GameLib.Scene.create(&layers, &viewport, allocator);
    scene.scroll_state = .{ .x = 0, .y = 1 };

    defer scene.destroy();

    var player_animations = getPlayerAnimations();
    _ = player_animations; // autofix

    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
        //----------------------------------------------------------------------------------
        const delta_time = rl.getFrameTime();

        viewport.update(delta_time);
        scene.update(delta_time);

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);

        viewport.draw();
        scene.draw();

        //----------------------------------------------------------------------------------
    }
}

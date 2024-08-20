const rl = @import("raylib");
const std = @import("std");
const an = @import("animation.zig");
const debug = @import("debug.zig");
const Viewport = @import("viewport.zig");
const Scene = @import("scene.zig");
const Sprite = @import("sprite.zig");
const tl = @import("tiles.zig");

const Tileset512 = tl.Tileset(512);

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
                } else if (y > 25) {
                    break :blk 17;
                }
                break :blk 0;
            };
        }
    }

    return fg_tile_data;
}

fn generateTilesetCollisionData() [512]bool {
    var fg_collision_data: [512]bool = std.mem.zeroes([512]bool);

    fg_collision_data[1] = true;

    return fg_collision_data;
}

const PlayerAnimationBuffer = an.AnimationBuffer(&.{ .Idle, .Hit, .Walk, .Death, .Roll }, 16);
const MobAnimationBuffer = an.AnimationBuffer(&.{ .Walk, .Attack, .Hit }, 6);

fn getPlayerAnimations() PlayerAnimationBuffer {
    var buffer = PlayerAnimationBuffer{};

    buffer.writeAnimation(.Idle, 0.5, &.{ 1, 2, 3, 4 });
    buffer.writeAnimation(.Walk, 1, blk: {
        var data: [16]u8 = undefined;
        for (17..33, 0..) |i, idx| {
            data[idx] = @intCast(i);
        }
        break :blk &data;
    });
    buffer.writeAnimation(.Roll, 0.8, blk: {
        var data: [8]u8 = undefined;
        for (41..49, 0..) |i, idx| {
            data[idx] = @intCast(i);
        }
        break :blk &data;
    });
    buffer.writeAnimation(.Hit, 0.5, blk: {
        var data: [4]u8 = undefined;
        for (49..53, 0..) |i, idx| {
            data[idx] = @intCast(i);
        }
        break :blk &data;
    });
    buffer.writeAnimation(.Death, 1, blk: {
        var data: [4]u8 = undefined;
        for (57..61, 0..) |i, idx| {
            data[idx] = @intCast(i);
        }
        break :blk &data;
    });

    std.log.debug("PlayerAnimationBuffer: {any}\n", .{buffer.data});

    return buffer;
}

fn getSlimeAnimations() MobAnimationBuffer {
    var buffer = MobAnimationBuffer{};

    buffer.writeAnimation(.Walk, 1, &.{ 1, 2, 3, 4, 3, 2 });
    buffer.writeAnimation(.Attack, 0.5, &.{ 5, 6, 7, 8 });
    buffer.writeAnimation(.Hit, 0.5, &.{ 9, 10, 11, 12 });

    std.log.debug("SlimeAnimationBuffer: {any}\n", .{buffer.data});

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

    debug.setDebugFlags(&.{ .ShowHitboxes, .ShowScrollState });

    const screen_width_float: f32 = @floatFromInt(screen_width);
    const screen_height_float: f32 = @floatFromInt(screen_height);

    const viewport_padding_x = 20;
    const viewport_padding_y = 22;

    var viewport = Viewport.init(rl.Rectangle.init(viewport_padding_x, viewport_padding_y, screen_width_float - (viewport_padding_x * 2), screen_height_float - (viewport_padding_y * 2)));

    const tilemap = try Tileset512.init("assets/sprites/world_tileset.png", .{ .x = 16, .y = 16 }, generateTilesetCollisionData(), allocator);

    var bg_tile_data = generateBgTileData();
    const bg_layer = tl.TileLayer.init(.{ .x = 70, .y = 35 }, 1, tilemap, &bg_tile_data, tl.LayerFlag.mask(&.{}));

    var fg_tile_data = generateFgTileData();
    const fg_layer = tl.TileLayer.init(.{ .x = 100, .y = 40 }, 100, tilemap, &fg_tile_data, tl.LayerFlag.mask(&.{.Collidable}));

    var layers = [_]tl.TileLayer{ bg_layer, fg_layer };

    var player_animations = getPlayerAnimations();
    var slime_animations = getSlimeAnimations();

    const player_sprite = Sprite.init(
        "assets/sprites/knight.png",
        .{ .x = 32, .y = 32 },
        rl.Rectangle.init(8, 8, 16, 22),
        rl.Vector2.init(0, 0.45),
        player_animations.reader(),
    );

    var slime_sprite = Sprite.init(
        "assets/sprites/slime_green.png",
        .{ .x = 24, .y = 24 },
        rl.Rectangle.init(6, 12, 12, 12),
        rl.Vector2.init(0.7, 0.45),
        slime_animations.reader(),
    );
    slime_sprite.current_animation = .Walk;

    var sprites = [_]Sprite{ player_sprite, slime_sprite };

    var scene = try Scene.create(&layers, &viewport, &sprites, allocator);
    scene.scroll_state = .{ .x = 0, .y = 1 };

    defer scene.destroy();

    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
        //----------------------------------------------------------------------------------
        const delta_time = rl.getFrameTime();

        if (rl.isKeyPressed(rl.KeyboardKey.key_one)) {
            sprites[0].setAnimation(.Idle, null, false);
        } else if (rl.isKeyPressed(rl.KeyboardKey.key_two)) {
            sprites[0].setAnimation(.Walk, null, false);
        } else if (rl.isKeyPressed(rl.KeyboardKey.key_three)) {
            sprites[0].setAnimation(.Roll, .Idle, false);
        } else if (rl.isKeyPressed(rl.KeyboardKey.key_four)) {
            sprites[0].setAnimation(.Hit, .Idle, false);
        } else if (rl.isKeyPressed(rl.KeyboardKey.key_five)) {
            sprites[0].setAnimation(.Death, null, true);
        }

        if (rl.isKeyPressed(rl.KeyboardKey.key_six)) {
            sprites[1].setAnimation(.Walk, null, false);
        } else if (rl.isKeyPressed(rl.KeyboardKey.key_seven)) {
            sprites[1].setAnimation(.Attack, null, false);
        } else if (rl.isKeyPressed(rl.KeyboardKey.key_eight)) {
            sprites[1].setAnimation(.Hit, .Attack, false);
        }

        if (rl.isKeyPressed(rl.KeyboardKey.key_q)) {
            sprites[0].setDirection(if (sprites[0].sprite_direction == .Right) .Left else .Right);
        }

        if (rl.isKeyPressed(rl.KeyboardKey.key_e)) {
            sprites[1].setDirection(if (sprites[1].sprite_direction == .Right) .Left else .Right);
        }

        viewport.update(delta_time);
        try scene.update(delta_time);

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

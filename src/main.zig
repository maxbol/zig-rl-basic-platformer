const rl = @import("raylib");
const std = @import("std");
const an = @import("animation.zig");
const debug = @import("debug.zig");
const Viewport = @import("viewport.zig");
const Scene = @import("scene.zig");
const Sprite = @import("sprite.zig");
const tl = @import("tiles.zig");
const controls = @import("controls.zig");
const co = @import("collisions.zig");

const Tileset512 = tl.Tileset(512);

const JUMP_HEIGHT = 100;
const JUMP_PARABOLA = [_]u8{
    0,
    4,
    8,
    11,
    15,
    18,
    20,
    23,
    25,
    28,
    29,
    31,
    32,
    34,
    35,
    35,
    36,
    36,
    // 36,
    // 36,
    // 35,
    // 35,
    // 34,
    // 32,
    // 31,
    // 29,
    // 28,
    // 25,
    // 23,
    // 20,
    // 18,
    // 15,
    // 11,
    // 8,
    // 4,
    // 0,
};

var is_paused = false;

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
                if (y < 24) {
                    break :blk 0;
                } else if (y == 24) {
                    if (x == 1) {
                        break :blk 1;
                    } else if (x == 3) {
                        break :blk 0;
                    }
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
    fg_collision_data[17] = true;

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

    const WINDOW_SIZE_X = 1600;
    const WINDOW_SIZE_Y = 900;

    const GAME_SIZE_X = 640;
    const GAME_SIZE_Y = 480;

    rl.setConfigFlags(.{
        // .fullscreen_mode = true,
        .vsync_hint = true,
        .window_resizable = false,
    });
    rl.initWindow(WINDOW_SIZE_X, WINDOW_SIZE_Y, "raylib-zig [core] example - basic window");
    rl.setWindowMinSize(GAME_SIZE_X, GAME_SIZE_Y);
    rl.setTargetFPS(120); // Set our game to run at 60 frames-per-second

    const target = rl.loadRenderTexture(GAME_SIZE_X, GAME_SIZE_Y);
    rl.setTextureFilter(target.texture, .texture_filter_bilinear);
    defer rl.unloadRenderTexture(target);

    //--------------------------------------------------------------------------------------

    const debug_flags = &.{ .ShowHitboxes, .ShowScrollState };
    debug.setDebugFlags(debug_flags);

    const viewport_padding_x = 16 + (GAME_SIZE_X % 16);
    const viewport_padding_y = 16 + (GAME_SIZE_Y % 16);

    var viewport = Viewport.init(rl.Rectangle.init(viewport_padding_x, viewport_padding_y, GAME_SIZE_X - (viewport_padding_x * 2), GAME_SIZE_Y - (viewport_padding_y * 2)));

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
        rl.Rectangle.init(8, 8, 16, 20),
        rl.Vector2.init(0, 16 * 16),
        player_animations.reader(),
    );

    var slime_sprite = Sprite.init(
        "assets/sprites/slime_green.png",
        .{ .x = 24, .y = 24 },
        rl.Rectangle.init(6, 12, 12, 12),
        rl.Vector2.init(50 * 16, 16 * 16),
        slime_animations.reader(),
    );
    slime_sprite.current_animation = .Walk;

    var sprites = [_]Sprite{ player_sprite, slime_sprite };

    var scene = try Scene.create(&layers, &viewport, &sprites, allocator);
    scene.scroll_state = .{ .x = 0, .y = 1 };

    var jump_frame: f32 = -1;

    defer scene.destroy();

    controls.initKeyboardControls();

    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
        //----------------------------------------------------------------------------------
        const screen_width: f32 = @floatFromInt(rl.getScreenWidth());
        const screen_height: f32 = @floatFromInt(rl.getScreenHeight());

        const scale = @min(
            screen_width / GAME_SIZE_X,
            screen_height / GAME_SIZE_Y,
        );
        const delta_time = rl.getFrameTime();

        if (rl.isKeyPressed(rl.KeyboardKey.key_f)) {
            rl.toggleFullscreen();
        }

        if (rl.isKeyPressed(rl.KeyboardKey.key_p)) {
            debug.togglePause();
        }

        if (rl.isKeyPressed(rl.KeyboardKey.key_o)) {
            if (debug.isDebugFlagSet(debug_flags[0])) {
                debug.clearDebugFlags();
            } else {
                debug.setDebugFlags(debug_flags);
            }
        }

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

        if (!debug.isPaused()) {
            // Manual camera panning with WASD
            if (jump_frame >= 0) {
                const next_jump_frame = jump_frame - (JUMP_PARABOLA.len * delta_time);
                const jump_frame_idx: usize = @intFromFloat(@floor(jump_frame));
                const jmp_adj = @as(f32, @floatFromInt(JUMP_PARABOLA[jump_frame_idx])) * 0.1;
                sprites[0].movement_vec.y -= jmp_adj;
                jump_frame = next_jump_frame;
            } else {
                jump_frame = -1;
            }

            var dir_mask: u4 = @intFromEnum(controls.MovementKeyBitmask.None);

            if (rl.isKeyDown(rl.KeyboardKey.key_w) and jump_frame == -1 and (sprites[0].world_collision_mask & @intFromEnum(co.CollisionDirection.Up)) == 0 and (sprites[0].world_collision_mask & @intFromEnum(co.CollisionDirection.Down)) != 0) {
                jump_frame = @as(f32, JUMP_PARABOLA.len - 1);
                // dir_mask |= @intFromEnum(controls.MovementKeyBitmask.Up);
            }

            if (rl.isKeyDown(rl.KeyboardKey.key_a) and (sprites[0].world_collision_mask & @intFromEnum(co.CollisionDirection.Left)) == 0) {
                sprites[0].setDirection(.Left);
                dir_mask |= @intFromEnum(controls.MovementKeyBitmask.Left);
            } else if (rl.isKeyDown(rl.KeyboardKey.key_d) and (sprites[0].world_collision_mask & @intFromEnum(co.CollisionDirection.Right)) == 0) {
                sprites[0].setDirection(.Right);
                dir_mask |= @intFromEnum(controls.MovementKeyBitmask.Right);
            }

            const dir_vec = controls.movement_vectors[dir_mask];
            const movement_speed = 40;

            if (dir_vec.length() > 0) {
                if (sprites[0].current_animation != .Walk) {
                    sprites[0].setAnimation(.Walk, null, false);
                }
                sprites[0].movement_vec = sprites[0].movement_vec.add(dir_vec.scale(movement_speed * delta_time));

                // scene.scroll_state = scene.scroll_state.add(dir_vec.scale(scroll_speed * delta_time)).clamp(rl.Vector2.init(0, 0), rl.Vector2.init(1, 1));
            } else if (sprites[0].current_animation == .Walk) {
                sprites[0].setAnimation(.Idle, null, false);
            }
        }

        viewport.update(delta_time);
        try scene.update(delta_time);

        if (!debug.isPaused()) {
            scene.scroll_state.x = @min(@max(sprites[0].pos.x - (viewport.rectangle.width / 2), 0) / scene.max_x_scroll, scene.max_x_scroll);
            scene.scroll_state.y = @min(@max(sprites[0].pos.y - (viewport.rectangle.height / 2), 0) / scene.max_y_scroll, scene.max_y_scroll);
        }

        // Draw to render texture
        //----------------------------------------------------------------------------------
        rl.beginTextureMode(target);

        rl.clearBackground(rl.Color.black);

        viewport.draw();
        scene.draw();

        rl.endTextureMode();

        // Draw render texture to screen
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.red);
        rl.drawTexturePro(
            target.texture,
            rl.Rectangle.init(0, 0, @as(f32, @floatFromInt(target.texture.width)), @as(f32, @floatFromInt(-target.texture.height))),
            rl.Rectangle.init(
                (screen_width - (GAME_SIZE_X * scale)) * 0.5,
                (screen_height - (GAME_SIZE_Y * scale)) * 0.5,
                GAME_SIZE_X * scale,
                GAME_SIZE_Y * scale,
            ),
            rl.Vector2.init(0, 0),
            0,
            rl.Color.white,
        );
    }
}

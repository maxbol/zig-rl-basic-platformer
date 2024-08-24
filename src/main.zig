const Entity = @import("entity.zig");
const Player = @import("actor_player.zig");
const Scene = @import("scene.zig");
const Sprite = @import("sprite.zig");
const Viewport = @import("viewport.zig");
const an = @import("animation.zig");
const co = @import("collisions.zig");
const controls = @import("controls.zig");
const debug = @import("debug.zig");
const rl = @import("raylib");
const std = @import("std");
const tl = @import("tiles.zig");

const Tileset512 = tl.FixedSizeTileset(512);

// Clouds - 145
// Clouds and sky - 161
// Sky - 177
fn generateBgTileData() [1 * 35]u8 {
    var bg_tile_data: [1 * 35]u8 = undefined;

    for (0..35) |y| {
        for (0..1) |x| {
            bg_tile_data[y * 1 + x] = blk: {
                if (y < 12) {
                    break :blk 145;
                } else if (y == 12) {
                    break :blk 161;
                } else if (y > 12) {
                    break :blk 177;
                }
                break :blk 0;
            };
        }
    }

    return bg_tile_data;
}

fn generateMainTileData() [100 * 40]u8 {
    var fg_tile_data: [100 * 40]u8 = undefined;

    for (0..40) |y| {
        for (0..100) |x| {
            fg_tile_data[y * 100 + x] = blk: {
                if (y < 20) {
                    break :blk 0;
                } else if (y == 20) {
                    if (x == 6 or x == 15) {
                        break :blk 1;
                    }
                    break :blk 0;
                }
                if (y < 24) {
                    if (x == 15) {
                        break :blk 1;
                    }
                    break :blk 0;
                } else if (y == 24) {
                    if (x == 1 or x == 15 or x == 16) {
                        break :blk 1;
                    }
                    break :blk 0;
                } else if (y == 25) {
                    break :blk 1;
                } else {
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

const PlayerAnimationBuffer = an.AnimationBuffer(&.{ .Idle, .Hit, .Walk, .Death, .Roll, .Jump }, 16);
const MobAnimationBuffer = an.AnimationBuffer(&.{ .Walk, .Attack, .Hit }, 6);

fn getPlayerAnimations() PlayerAnimationBuffer {
    var buffer = PlayerAnimationBuffer{};

    buffer.writeAnimation(.Idle, 0.5, &.{ 1, 2, 3, 4 });
    buffer.writeAnimation(.Jump, 0.1, &.{4});
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

    return buffer;
}

fn getSlimeAnimations() MobAnimationBuffer {
    var buffer = MobAnimationBuffer{};

    buffer.writeAnimation(.Walk, 1, &.{ 1, 2, 3, 4, 3, 2 });
    buffer.writeAnimation(.Attack, 0.5, &.{ 5, 6, 7, 8 });
    buffer.writeAnimation(.Hit, 0.5, &.{ 9, 10, 11, 12 });

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
    const GAME_SIZE_Y = 360;

    rl.setConfigFlags(.{
        // .fullscreen_mode = true,
        .vsync_hint = true,
        .window_resizable = true,
    });
    rl.initWindow(WINDOW_SIZE_X, WINDOW_SIZE_Y, "knight jumper");
    rl.setWindowMinSize(GAME_SIZE_X, GAME_SIZE_Y);
    rl.setTargetFPS(120); // Set our game to run at 60 frames-per-second

    const target = rl.loadRenderTexture(GAME_SIZE_X, GAME_SIZE_Y);
    rl.setTextureFilter(target.texture, .texture_filter_bilinear);
    defer rl.unloadRenderTexture(target);

    //--------------------------------------------------------------------------------------

    const debug_flags = &.{ .ShowHitboxes, .ShowScrollState, .ShowFps, .ShowSpriteOutlines, .ShowTestedTiles, .ShowCollidedTiles };
    debug.setDebugFlags(debug_flags);

    const viewport_padding_x = 16 + (GAME_SIZE_X % 16);
    const viewport_padding_y = 16 + (GAME_SIZE_Y % 16);

    var viewport = Viewport.init(rl.Rectangle.init(viewport_padding_x, viewport_padding_y, GAME_SIZE_X - (viewport_padding_x * 2), GAME_SIZE_Y - (viewport_padding_y * 2)));

    const tilemap = try Tileset512.init("assets/sprites/world_tileset.png", .{ .x = 16, .y = 16 }, generateTilesetCollisionData());

    const BgTileLayer = tl.FixedSizeTileLayer(1 * 35, Tileset512);
    const bg_tile_data = generateBgTileData();
    var bg_layer = BgTileLayer.init(.{ .x = 70, .y = 35 }, 1, tilemap, bg_tile_data, tl.LayerFlag.mask(&.{}));
    var bg_layers: [1]tl.TileLayer = .{bg_layer.tileLayer()};

    const MainLayer = tl.FixedSizeTileLayer(100 * 40, Tileset512);
    const main_tile_data = generateMainTileData();
    var main_layer = MainLayer.init(.{ .x = 100, .y = 40 }, 100, tilemap, main_tile_data, tl.LayerFlag.mask(&.{.Collidable}));

    const fg_layers: [0]tl.TileLayer = .{};

    var player_animations = getPlayerAnimations();
    // var slime_animations = getSlimeAnimations();

    const player_sprite = Sprite.init(
        "assets/sprites/knight.png",
        .{ .x = 32, .y = 32 },
        player_animations.reader(),
    );

    var player = Player.init(
        rl.Rectangle.init(0, 16 * 16, 16, 16),
        player_sprite,
        .{ .x = 8, .y = 12 },
    );
    const actor = player.entity();

    // var slime_sprite = Sprite.init(
    //     "assets/sprites/slime_green.png",
    //     .{ .x = 24, .y = 24 },
    //     // rl.Rectangle.init(6, 12, 12, 12),
    //     // rl.Vector2.init(50 * 16, 16 * 16),
    //     slime_animations.reader(),
    // );
    // slime_sprite.current_animation = .Walk;
    //
    var actors: [1]Entity = .{actor};

    var scene = try Scene.create(main_layer.tileLayer(), &bg_layers, &fg_layers, &viewport, &actors, allocator);
    scene.scroll_state = .{ .x = 0, .y = 1 };

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

        viewport.update(delta_time);
        try scene.update(delta_time);

        // Draw to render texture
        //----------------------------------------------------------------------------------
        rl.beginTextureMode(target);

        rl.clearBackground(rl.Color.black);

        viewport.draw();
        scene.draw();
        scene.drawDebug();

        if (debug.isDebugFlagSet(.ShowFps)) {
            rl.drawFPS(GAME_SIZE_X - 150, GAME_SIZE_Y - 20);
        }

        rl.endTextureMode();

        // Draw render texture to screen
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);
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

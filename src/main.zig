const Actor = @import("actor/actor.zig");
const Editor = @import("editor.zig");
const Entity = @import("entity.zig");
const Scene = @import("scene.zig");
const Sprite = @import("sprite.zig");
const TileLayer = @import("tile_layer/tile_layer.zig");
const Tileset = @import("tileset/tileset.zig");
const Viewport = @import("viewport.zig");
const an = @import("animation.zig");
const constants = @import("constants.zig");
const controls = @import("controls.zig");
const debug = @import("debug.zig");
const globals = @import("globals.zig");
const helpers = @import("helpers.zig");
const rl = @import("raylib");
const static = @import("static.zig");
const std = @import("std");

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
    fg_collision_data[3] = true;
    fg_collision_data[4] = true;
    fg_collision_data[17] = true;

    return fg_collision_data;
}

fn getPlayerAnimations() static.PlayerAnimationBuffer {
    var buffer = static.PlayerAnimationBuffer{};

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
    buffer.writeAnimation(.Hit, 0.15, blk: {
        var data: [3]u8 = undefined;
        // for (49..53, 0..) |i, idx| {
        for (49..52, 0..) |i, idx| {
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

fn getSlimeAnimations() static.MobAnimationBuffer {
    var buffer = static.MobAnimationBuffer{};

    buffer.writeAnimation(.Walk, 1, &.{ 1, 2, 3, 4, 3, 2 });
    buffer.writeAnimation(.Attack, 0.5, &.{ 5, 6, 7, 8 });
    buffer.writeAnimation(.Hit, 0.1, &.{ 9, 10, 11, 12 });

    return buffer;
}

pub fn initGameData() void {
    // Init randomizer
    globals.rand = helpers.createRandomizer() catch {
        std.log.err("Error initializing randomizer, quitting...", .{});
        std.process.exit(1);
    };

    // Init debug flags
    globals.debug_flags = &.{ .ShowHitboxes, .ShowScrollState, .ShowFps, .ShowSpriteOutlines, .ShowTestedTiles, .ShowCollidedTiles, .ShowGridBoxes };
    debug.setDebugFlags(globals.debug_flags);

    // Init viewport
    globals.viewport = Viewport.init(constants.VIEWPORT_BIG_RECT);

    // Init tileset
    globals.tileset_image = rl.loadImage("assets/sprites/world_tileset.png");
    globals.tileset = try static.Tileset512.init(
        globals.tileset_image,
        .{ .x = constants.TILE_SIZE, .y = constants.TILE_SIZE },
        generateTilesetCollisionData(),
    );
    var byte_len: usize = undefined;
    const tileset_bytes = globals.tileset.toBytes(&byte_len) catch {
        @panic("Skill issues tbh");
    };
    if (byte_len == 0) {
        @panic("Skill issues tbh");
    }

    std.debug.print("tileset_bytes={any}", .{tileset_bytes[0..byte_len]});

    // Init tile layers
    globals.bg_layers[0] = static.BgTileLayer.init(.{ .x = 70, .y = 35 }, 1, globals.tileset, generateBgTileData(), TileLayer.LayerFlag.mask(&.{}));
    globals.bg_layers_count = 1;
    globals.main_layer = static.MainLayer.init(.{ .x = 100, .y = 40 }, 100, globals.tileset, generateMainTileData(), TileLayer.LayerFlag.mask(&.{.Collidable}));
    globals.fg_layers_count = 0;

    // Init animation frames
    globals.player_animations = getPlayerAnimations();
    globals.slime_animations = getSlimeAnimations();

    // Init player actor
    const player_sprite_texture = rl.loadTexture("assets/sprites/knight.png");
    const player_sprite = Sprite.init(
        player_sprite_texture,
        .{ .x = 32, .y = 32 },
        globals.player_animations.reader(),
    );
    globals.player = Actor.Player.init(
        rl.Rectangle.init(0, constants.TILE_SIZE * constants.TILE_SIZE, constants.TILE_SIZE, 20),
        player_sprite,
        .{ .x = 8, .y = 8 },
    );

    // Init mobs
    const slime_sprite_texture = rl.loadTexture("assets/sprites/slime_green.png");
    for (0..constants.MOB_AMOUNT) |i| {
        var slime_sprite = Sprite.init(
            slime_sprite_texture,
            .{ .x = 24, .y = 24 },
            globals.slime_animations.reader(),
        );
        slime_sprite.current_animation = .Walk;

        globals.mobs[i] = Actor.Mob.init(
            rl.Rectangle.init(
                (1 + @as(f32, @floatFromInt(i))) * constants.MOB_SPACING,
                0,
                12,
                12,
            ),
            slime_sprite,
            .{ .x = 6, .y = 12 },
        );
    }

    for (0..constants.MOB_AMOUNT) |i| {
        globals.mob_actors[i] = globals.mobs[i].actor();
    }

    // Init scene
    globals.scene = Scene.init(
        globals.main_layer.tileLayer(),
        globals.getBgLayers(),
        globals.getFgLayers(),
        &globals.viewport,
        globals.player.actor(),
        &globals.mob_actors,
    );
    globals.scene.scroll_state = .{ .x = 0, .y = 1 };

    // Init virtual mouse
    globals.vmouse = controls.VirtualMouse{};

    // Init editor
    globals.editor = Editor.init(&globals.scene, &globals.vmouse);
    globals.editor_mode = false;
}

pub fn main() anyerror!void {
    rl.setConfigFlags(.{
        // .fullscreen_mode = true,
        .vsync_hint = true,
        .window_resizable = true,
    });
    rl.initWindow(constants.WINDOW_SIZE_X, constants.WINDOW_SIZE_Y, "knight jumper");
    rl.initAudioDevice();
    rl.setWindowMinSize(constants.GAME_SIZE_X, constants.GAME_SIZE_Y);
    rl.setTargetFPS(120); // Set our game to run at 60 frames-per-second

    const target = rl.loadRenderTexture(constants.GAME_SIZE_X, constants.GAME_SIZE_Y);
    rl.setTextureFilter(target.texture, .texture_filter_bilinear);
    defer rl.unloadRenderTexture(target);

    const music = rl.loadMusicStream("assets/music/time_for_adventure.mp3");
    rl.playMusicStream(music);

    initGameData();

    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        rl.updateMusicStream(music);
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
        //----------------------------------------------------------------------------------
        const screen_width: f32 = @floatFromInt(rl.getScreenWidth());
        const screen_height: f32 = @floatFromInt(rl.getScreenHeight());

        const scale = @min(
            screen_width / constants.GAME_SIZE_X,
            screen_height / constants.GAME_SIZE_Y,
        );
        const delta_time = rl.getFrameTime();

        if (rl.isKeyPressed(rl.KeyboardKey.key_f)) {
            rl.toggleFullscreen();
        }

        if (rl.isKeyPressed(rl.KeyboardKey.key_p)) {
            debug.togglePause();
        }

        if (rl.isKeyPressed(rl.KeyboardKey.key_o)) {
            if (debug.isDebugFlagSet(globals.debug_flags[0])) {
                debug.clearDebugFlags();
            } else {
                debug.setDebugFlags(globals.debug_flags);
            }
        }

        if (rl.isKeyDown(rl.KeyboardKey.key_left_shift) and rl.isKeyPressed(rl.KeyboardKey.key_t)) {
            globals.editor_mode = !globals.editor_mode;
            globals.viewport.setTargetRect(if (!globals.editor_mode) constants.VIEWPORT_BIG_RECT else constants.VIEWPORT_SMALL_RECT);
        }

        globals.viewport.update(delta_time);
        try globals.scene.update(delta_time);

        if (globals.editor_mode) {
            globals.editor.update(delta_time);
        }

        // Draw to render texture
        //----------------------------------------------------------------------------------
        rl.beginTextureMode(target);

        rl.clearBackground(rl.Color.black);

        globals.vmouse.update(scale);

        globals.viewport.draw();
        globals.scene.draw();
        globals.scene.drawDebug();

        if (globals.editor_mode) {
            globals.editor.draw();
        }

        if (debug.isDebugFlagSet(.ShowFps)) {
            rl.drawFPS(constants.GAME_SIZE_X - 150, constants.GAME_SIZE_Y - 20);
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
                (screen_width - (constants.GAME_SIZE_X * scale)) * 0.5,
                (screen_height - (constants.GAME_SIZE_Y * scale)) * 0.5,
                constants.GAME_SIZE_X * scale,
                constants.GAME_SIZE_Y * scale,
            ),
            rl.Vector2.init(0, 0),
            0,
            rl.Color.white,
        );
    }
}

const Actor = @import("actor/actor.zig");
const Editor = @import("editor.zig");
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
const std = @import("std");

fn generateTilesetTileFlagMap() [512]u8 {
    var fg_collision_data: [512]u8 = std.mem.zeroes([512]u8);

    for (1..13) |i| {
        fg_collision_data[i] |= @intFromEnum(Tileset.TileFlag.Collidable);
    }

    for (17..29) |i| {
        fg_collision_data[i] |= @intFromEnum(Tileset.TileFlag.Collidable);
    }

    for (33..45) |i| {
        fg_collision_data[i] |= @intFromEnum(Tileset.TileFlag.Collidable);
    }

    fg_collision_data[51] |= @intFromEnum(Tileset.TileFlag.Collidable);
    fg_collision_data[56] |= @intFromEnum(Tileset.TileFlag.Collidable);
    fg_collision_data[72] |= @intFromEnum(Tileset.TileFlag.Collidable);

    fg_collision_data[1] = @intFromEnum(Tileset.TileFlag.Collidable);
    fg_collision_data[2] = @intFromEnum(Tileset.TileFlag.Collidable);
    fg_collision_data[3] = @intFromEnum(Tileset.TileFlag.Collidable);
    fg_collision_data[4] = @intFromEnum(Tileset.TileFlag.Collidable);
    fg_collision_data[7] = @intFromEnum(Tileset.TileFlag.Collidable) | @intFromEnum(Tileset.TileFlag.Slippery);
    fg_collision_data[17] = @intFromEnum(Tileset.TileFlag.Collidable);

    fg_collision_data[7] |= @intFromEnum(Tileset.TileFlag.Slippery);
    fg_collision_data[36] |= @intFromEnum(Tileset.TileFlag.Slippery);

    fg_collision_data[151] |= @intFromEnum(Tileset.TileFlag.Collidable);
    fg_collision_data[151] |= @intFromEnum(Tileset.TileFlag.Deadly);

    return fg_collision_data;
}

pub fn createDefaultScene(allocator: std.mem.Allocator) *Scene {
    // Init scene
    const scene = Scene.loadSceneFromFile(allocator, globals.scene_file) catch |err| {
        std.log.err("Error loading scene from file: {!}\n", .{err});
        std.process.exit(1);
    };
    scene.scroll_state = .{ .x = 0, .y = 1 };

    return scene;
}

pub fn initGameData(allocator: std.mem.Allocator) !void {
    // Init randomizer
    globals.rand = helpers.createRandomizer() catch {
        std.log.err("Error initializing randomizer, quitting...", .{});
        std.process.exit(1);
    };

    // Spawn game over texts
    const all_game_over_texts = [_][*:0]const u8{
        "Ya done goofed up son!",
        "You a failure!",
        "You a disgrace!",
    };
    var slots: [all_game_over_texts.len]bool = .{false} ** all_game_over_texts.len;
    globals.game_over_texts = try allocator.alloc([*:0]const u8, all_game_over_texts.len);
    for (all_game_over_texts) |text| {
        while (true) {
            const idx = globals.rand.random().intRangeAtMost(usize, 0, globals.game_over_texts.len - 1);
            if (!slots[idx]) {
                slots[idx] = true;
                globals.game_over_texts[idx] = text;
                break;
            }
        }
    }

    // Init debug flags
    globals.debug_flags = &.{ .ShowHitboxes, .ShowScrollState, .ShowFps, .ShowSpriteOutlines, .ShowTestedTiles, .ShowCollidedTiles, .ShowGridBoxes, .ShowTilemapDebug };
    // debug.setDebugFlags(globals.debug_flags);

    // Init game font
    globals.font = rl.loadFont("assets/fonts/PixelOperator8-Bold.ttf");

    // Init audio
    globals.on_save_sfx = rl.loadSound("assets/sounds/power_up.wav");
    globals.music_level = rl.loadMusicStream("assets/music/time_for_adventure.mp3");
    globals.music_gameover = rl.loadMusicStream("assets/music/game_over.mp3");
    globals.music_gameover.looping = false;
    globals.current_music = &globals.music_level;

    // Init viewport
    globals.viewport = Viewport.init(constants.VIEWPORT_BIG_RECT);

    // Init player actor
    globals.player = Actor.Player.Knight.init(.{ .x = 0, .y = 0 });

    // Init virtual mouse
    globals.vmouse = controls.VirtualMouse{};
}

pub fn freeGameData(allocator: std.mem.Allocator) void {
    allocator.free(globals.game_over_texts);
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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

    // Uncomment this to regenerate the tileset:
    rebuildAndStoreDefaultTileset(allocator, "data/tilesets/default.tileset");

    // Setup static game data
    try initGameData(allocator);
    defer freeGameData(allocator);

    const scene = createDefaultScene(allocator);
    defer scene.destroy();

    // Init editor
    globals.editor = try Editor.create(allocator, scene, &globals.vmouse);
    globals.editor_mode = false;
    defer globals.editor.destroy();

    // Play music
    rl.playMusicStream(globals.current_music.*);

    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        if (globals.current_music == &globals.music_gameover and !rl.isMusicStreamPlaying(globals.current_music.*)) {
            globals.current_music = &globals.music_level;
            rl.seekMusicStream(globals.current_music.*, 0);
            rl.playMusicStream(globals.current_music.*);
        }
        rl.updateMusicStream(globals.current_music.*);
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

        if (rl.isKeyPressed(rl.KeyboardKey.key_r)) {
            scene.reset();
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
        scene.layer_visibility_treshold = null;
        try scene.update(delta_time);

        if (globals.editor_mode) {
            try globals.editor.update(delta_time);
        }

        // Draw to render texture
        //----------------------------------------------------------------------------------
        rl.beginTextureMode(target);

        rl.clearBackground(rl.Color.black);

        globals.vmouse.update(scale);

        globals.viewport.draw();
        scene.draw();
        scene.drawDebug();

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

pub fn rebuildAndStoreDefaultTileset(allocator: std.mem.Allocator, tileset_path: []const u8) void {
    const tileset_image = rl.loadImage("assets/sprites/world_tileset.png");
    var size: c_int = undefined;
    const image_data = rl.exportImageToMemory(tileset_image, ".png", &size);
    const tileset = Tileset.Tileset512.create(image_data[0..@intCast(size)], .{ .x = 16, .y = 16 }, &generateTilesetTileFlagMap(), allocator) catch |err| {
        std.log.err("Error storing tileset to file: {!}\n", .{err});
        std.process.exit(1);
    };
    defer tileset.tileset().destroy();
    const tileset_file = helpers.openFile(tileset_path, .{ .mode = .write_only }) catch {
        std.log.err("Error opening file for writing: {s}\n", .{tileset_path});
        std.process.exit(1);
    };
    tileset.writeToFile(tileset_file) catch {
        std.log.err("Error writing tileset to file: {s}\n", .{tileset_path});
        std.process.exit(1);
    };
}

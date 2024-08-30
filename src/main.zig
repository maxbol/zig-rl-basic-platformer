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

pub fn createDefaultScene(allocator: std.mem.Allocator) *Scene {
    // Init scene
    const scene = Scene.loadSceneFromFile(allocator, globals.scene_file) catch |err| {
        std.log.err("Error loading scene from file: {!}\n", .{err});
        std.process.exit(1);
    };
    scene.scroll_state = .{ .x = 0, .y = 1 };

    // Store scene in new loc
    // const new_file = helpers.openFile("data/scenes/level1-new.scene", .{ .mode = .write_only }) catch {
    //     std.log.err("Error opening file for writing: {s}\n", .{"data/scenes/level1-new.scene"});
    //     std.process.exit(1);
    // };
    // scene.writeBytes(new_file.writer()) catch |err| {
    //     std.log.err("Error writing scene to file: {!}\n", .{err});
    //     std.process.exit(1);
    // };

    return scene;
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

    // Init game font
    globals.font = rl.loadFont("assets/fonts/PixelOperator8.ttf");

    // Init audio
    globals.on_save_sfx = rl.loadSound("assets/sounds/power_up.wav");
    globals.music = rl.loadMusicStream("assets/music/time_for_adventure.mp3");

    // Init viewport
    globals.viewport = Viewport.init(constants.VIEWPORT_BIG_RECT);

    // Init animation frames
    globals.player_animations = getPlayerAnimations();

    // Init player actor
    const player_sprite_texture = rl.loadTexture("assets/sprites/knight.png");
    const player_sprite = Sprite.init(
        player_sprite_texture,
        .{ .x = 32, .y = 32 },
        globals.player_animations.reader(),
        .Idle,
    );
    globals.player = Actor.Player.init(
        rl.Rectangle.init(0, 0, constants.TILE_SIZE, 20),
        player_sprite,
        .{ .x = 8, .y = 8 },
    );

    // Init virtual mouse
    globals.vmouse = controls.VirtualMouse{};
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
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

    // Setup static game data
    initGameData();

    const scene = createDefaultScene(allocator);
    defer scene.destroy();

    // Init editor
    globals.editor = Editor.init(scene, &globals.vmouse);
    globals.editor_mode = false;

    // Play music
    rl.playMusicStream(globals.music);

    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        rl.updateMusicStream(globals.music);
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
    const tileset = Tileset.Tileset512.create(image_data[0..@intCast(size)], .{ .x = 16, .y = 16 }, &generateTilesetCollisionData(), allocator) catch |err| {
        std.log.err("Error storing tileset to file: {!}\n", .{err});
        @panic("skill issues");
    };
    const tileset_file = helpers.openFile(tileset_path, .{ .mode = .write_only }) catch {
        std.log.err("Error opening file for writing: {s}\n", .{tileset_path});
        @panic("skill issues");
    };
    tileset.writeToFile(tileset_file) catch {
        std.log.err("Error writing tileset to file: {s}\n", .{tileset_path});
        @panic("skill issues");
    };
    std.debug.print("stored tileset file successfully\n", .{});
}

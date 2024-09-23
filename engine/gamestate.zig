const Actor = @import("actor/actor.zig");
const Editor = @import("editor.zig");
const GameState = @This();
const HUD = @import("hud.zig");
const Scene = @import("scene.zig");
const Viewport = @import("viewport.zig");
const constants = @import("constants.zig");
const controls = @import("controls.zig");
const debug = @import("debug.zig");
const helpers = @import("helpers.zig");
const rl = @import("raylib");
const std = @import("std");
const Tileset = @import("tileset/tileset.zig");

allocator: std.mem.Allocator = undefined,
current_music: *rl.Music = undefined,
debug_flags: []const debug.DebugFlag = undefined,
editor: *Editor = undefined,
editor_mode: bool = false,
font: rl.Font = undefined,
game_over_counter: u32 = 0,
game_over_texts: [][*:0]const u8 = undefined,
hud: HUD = undefined,
music_gameover: rl.Music = undefined,
music_level: rl.Music = undefined,
on_save_sfx: rl.Sound = undefined,
player: Actor.Player = undefined,
rand: std.rand.DefaultPrng = undefined,
render_texture: rl.RenderTexture2D = undefined,
scene: *Scene = undefined,
scene_file: []const u8 = "data/scenes/level1.scene",
viewport: Viewport = undefined,
vmouse: controls.VirtualMouse = controls.VirtualMouse{},

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;

pub fn create() !*GameState {
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var game_state = try allocator.create(GameState);

    game_state.allocator = allocator;

    // Init randomizer
    game_state.rand = helpers.createRandomizer() catch {
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
    game_state.game_over_texts = try game_state.allocator.alloc([*:0]const u8, all_game_over_texts.len);
    for (all_game_over_texts) |text| {
        while (true) {
            const idx = game_state.rand.random().intRangeAtMost(usize, 0, game_state.game_over_texts.len - 1);
            if (!slots[idx]) {
                slots[idx] = true;
                game_state.game_over_texts[idx] = text;
                break;
            }
        }
    }

    // Init debug flags
    game_state.debug_flags = &.{ .ShowHitboxes, .ShowScrollState, .ShowFps, .ShowSpriteOutlines, .ShowTestedTiles, .ShowCollidedTiles, .ShowGridBoxes, .ShowTilemapDebug };
    // debug.setDebugFlags(self.debug_flags);

    // Init game font
    game_state.font = rl.loadFont("assets/fonts/PixelOperator8-Bold.ttf");

    // Init audio
    game_state.on_save_sfx = rl.loadSound("assets/sounds/power_up.wav");
    game_state.music_level = rl.loadMusicStream("assets/music/time_for_adventure.mp3");
    game_state.music_gameover = rl.loadMusicStream("assets/music/game_over.mp3");
    game_state.music_gameover.looping = false;
    game_state.current_music = &game_state.music_level;

    std.debug.print("setting current_music: {any}\n", .{game_state.current_music});

    // Init viewport
    game_state.viewport = Viewport.init(constants.VIEWPORT_BIG_RECT);

    // Init player actor
    std.debug.print("Creating player actor\n", .{});
    game_state.player = Actor.Player.Knight.init(.{ .x = 0, .y = 0 });

    // Init virtual mouse
    std.debug.print("Creating virtual mouse\n", .{});
    game_state.vmouse = controls.VirtualMouse{};

    // Uncomment this to regenerate the tileset:
    // rebuildAndStoreDefaultTileset(allocator, "data/tilesets/default.tileset");

    // Init scene
    game_state.scene_file = "data/scenes/level1.scene";
    std.debug.print("Loading scene from file: {s}\n", .{game_state.scene_file});
    game_state.scene = Scene.loadSceneFromFile(game_state.allocator, game_state.scene_file) catch |err| {
        std.log.err("Error loading scene from file: {!}\n", .{err});
        std.process.exit(1);
    };
    game_state.scene.scroll_state = .{ .x = 0, .y = 1 };

    // Editor
    std.debug.print("Creating editor\n", .{});
    game_state.editor = try Editor.create(game_state.allocator, game_state.scene, &game_state.vmouse);
    game_state.editor_mode = false;

    // Hud
    std.debug.print("Creating HUD\n", .{});
    game_state.hud = HUD.init(&game_state.player);

    std.debug.print("Game state created\n", .{});

    return game_state;
}

pub fn deinit(self: *GameState) void {
    self.scene.destroy();
    self.editor.destroy();
    self.allocator.free(self.game_over_texts);
}

pub fn reload(self: *GameState) void {
    _ = self; // autofix
}

pub fn update(self: *GameState) !void {
    std.debug.print("running GameState.update()\n", .{});
    if (self.current_music == &self.music_gameover and !rl.isMusicStreamPlaying(self.current_music.*)) {
        self.current_music = &self.music_level;
        rl.seekMusicStream(self.current_music.*, 0);
        rl.playMusicStream(self.current_music.*);
    }
    std.debug.print("updating music stream\n", .{});

    std.debug.print("scene_file: {s}\n", .{self.scene_file});
    std.debug.print("current_music: {any}\n", .{self.current_music});
    rl.updateMusicStream(self.current_music.*);
    std.debug.print("music stream updated\n", .{});
    // Update
    //----------------------------------------------------------------------------------
    // TODO: Update your variables here
    //----------------------------------------------------------------------------------
    const delta_time = rl.getFrameTime();

    // Only run update jobs if window is not currently being resized to avoid weirdness/miscalculations
    // std.debug.print("{d} isWindowResized: {any}\n", .{ delta_time, rl.isWindowResized() });
    if (!rl.isWindowResized()) {
        if (rl.isKeyPressed(rl.KeyboardKey.key_f)) {
            rl.toggleFullscreen();
        }

        if (rl.isKeyPressed(rl.KeyboardKey.key_p)) {
            debug.togglePause();
        }

        if (rl.isKeyPressed(rl.KeyboardKey.key_r)) {
            self.scene.reset();
        }

        if (rl.isKeyPressed(rl.KeyboardKey.key_o)) {
            if (debug.isDebugFlagSet(self.debug_flags[0])) {
                debug.clearDebugFlags();
            } else {
                debug.setDebugFlags(self.debug_flags);
            }
        }

        if (rl.isKeyDown(rl.KeyboardKey.key_left_shift) and rl.isKeyPressed(rl.KeyboardKey.key_t)) {
            self.editor_mode = !self.editor_mode;
            self.viewport.setTargetRect(if (!self.editor_mode) constants.VIEWPORT_BIG_RECT else constants.VIEWPORT_SMALL_RECT);
        }

        self.viewport.update(delta_time);
        self.scene.layer_visibility_treshold = null;
        try self.scene.update(delta_time);
        try self.hud.update(self.scene, delta_time);

        if (self.editor_mode) {
            try self.editor.update(delta_time);
        }
    }
}

pub fn draw(self: *GameState) void {
    const screen_width: f32 = @floatFromInt(rl.getScreenWidth());
    const screen_height: f32 = @floatFromInt(rl.getScreenHeight());
    const scale = @min(
        screen_width / constants.GAME_SIZE_X,
        screen_height / constants.GAME_SIZE_Y,
    );

    rl.beginTextureMode(self.render_texture);
    rl.clearBackground(rl.Color.black);

    self.vmouse.update(scale);

    self.viewport.draw();
    self.scene.draw();
    self.hud.draw(self.scene);

    self.scene.drawDebug();

    if (self.editor_mode) {
        self.editor.draw();
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
        self.render_texture.texture,
        rl.Rectangle.init(0, 0, @as(f32, @floatFromInt(self.render_texture.texture.width)), @as(f32, @floatFromInt(-self.render_texture.texture.height))),
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

fn rebuildAndStoreDefaultTileset(allocator: std.mem.Allocator, tileset_path: []const u8) void {
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

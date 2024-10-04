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
const tracing = @import("tracing.zig");

allocator: std.mem.Allocator = undefined,
current_music: *rl.Music = undefined,
debug_mode: i16 = undefined,
debug_flags: []const debug.DebugFlag = undefined,
debug_sprite_previewer: ?debug.SpriteDebugPreviewer = null,
editor: *Editor = undefined,
editor_mode: bool = false,
font: rl.Font = undefined,
game_over_counter: u32 = 0,
game_over_texts: [][*:0]const u8 = undefined,
hr_recompiling: bool = false,
hud: HUD = undefined,
music_gameover: rl.Music = undefined,
music_level: rl.Music = undefined,
on_save_sfx: rl.Sound = undefined,
player: Actor.Player = undefined,
post_processing_shader: rl.Shader = undefined,
rand: std.rand.DefaultPrng = undefined,
render_texture: rl.RenderTexture2D = undefined,
scene: *Scene = undefined,
scene_file: []const u8 = "data/scenes/level1.scene",
viewport: Viewport = undefined,
vmouse: controls.VirtualMouse = controls.VirtualMouse{},

pub fn create(allocator: std.mem.Allocator) !*GameState {
    var gamestate = try allocator.create(GameState);

    gamestate.allocator = allocator;

    // Init randomizer
    gamestate.rand = helpers.createRandomizer() catch {
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
    gamestate.game_over_texts = try gamestate.allocator.alloc([*:0]const u8, all_game_over_texts.len);
    for (all_game_over_texts) |text| {
        while (true) {
            const idx = gamestate.rand.random().intRangeAtMost(usize, 0, gamestate.game_over_texts.len - 1);
            if (!slots[idx]) {
                slots[idx] = true;
                gamestate.game_over_texts[idx] = text;
                break;
            }
        }
    }

    // Init debug flags
    gamestate.debug_flags = &.{ .ShowHitboxes, .ShowScrollState, .ShowFps, .ShowSpriteOutlines, .ShowTestedTiles, .ShowCollidedTiles, .ShowGridBoxes, .ShowTilemapDebug };
    gamestate.debug_mode = -2;
    gamestate.debug_sprite_previewer = null;
    // debug.setDebugFlags(self.debug_flags);

    // Init game font
    gamestate.font = rl.loadFont("assets/fonts/PixelOperator8-Bold.ttf");

    // Init audio
    gamestate.on_save_sfx = rl.loadSound("assets/sounds/power_up.wav");
    gamestate.music_level = rl.loadMusicStream("assets/music/time_for_adventure.mp3");
    gamestate.music_gameover = rl.loadMusicStream("assets/music/game_over.mp3");
    gamestate.music_gameover.looping = false;
    gamestate.current_music = &gamestate.music_level;

    // Init viewport
    gamestate.viewport = Viewport.init(constants.VIEWPORT_BIG_RECT);

    // Init player actor
    gamestate.player = Actor.Player.Knight.init(.{ .x = 0, .y = 0 });

    // Init virtual mouse
    gamestate.vmouse = controls.VirtualMouse{};

    // Init post processing shader
    gamestate.setupPostProcessing();

    // Uncomment this to regenerate the tileset:
    // rebuildAndStoreDefaultTileset(allocator, "data/tilesets/default.tileset");

    // Init scene
    gamestate.loadSceneFromFile("data/scenes/level1.scene") catch |err| {
        std.log.err("Error loading scene from file: {!}\n", .{err});
        std.process.exit(1);
    };

    // Editor
    gamestate.editor = try Editor.create(gamestate.allocator, gamestate, gamestate.scene, &gamestate.vmouse);
    gamestate.editor_mode = false;

    // Hud
    gamestate.hud = HUD.init(&gamestate.player, gamestate.font);

    return gamestate;
}

pub fn setupPostProcessing(gamestate: *GameState) void {
    gamestate.post_processing_shader = rl.loadShader("", "assets/shaders/bloom.fs");

    const size_loc = rl.getShaderLocation(gamestate.post_processing_shader, "size");
    const samples_loc = rl.getShaderLocation(gamestate.post_processing_shader, "samples");
    const quality_loc = rl.getShaderLocation(gamestate.post_processing_shader, "quality");
    const size = rl.Vector2.init(constants.GAME_SIZE_X, constants.GAME_SIZE_Y);
    const samples: f32 = 7;
    const quality: f32 = 0.1;
    rl.setShaderValue(gamestate.post_processing_shader, size_loc, &size, rl.ShaderUniformDataType.shader_uniform_vec2);
    rl.setShaderValue(gamestate.post_processing_shader, samples_loc, &samples, rl.ShaderUniformDataType.shader_uniform_float);
    rl.setShaderValue(gamestate.post_processing_shader, quality_loc, &quality, rl.ShaderUniformDataType.shader_uniform_float);
}

pub fn deinit(self: *GameState) void {
    self.scene.destroy();
    self.editor.destroy();
    self.allocator.free(self.game_over_texts);
}

pub fn reload(self: *GameState) void {
    self.scene.hotReload();
    self.setDebugMode();
    self.setupPostProcessing();
}

pub fn notifyHRStarted(self: *GameState) void {
    self.hr_recompiling = true;
}

pub fn notifyHRDone(self: *GameState) void {
    self.hr_recompiling = false;
}

pub fn update(self: *GameState) !void {
    const zone = tracing.ZoneN(@src(), "Game Update");
    defer zone.End();

    if (self.current_music == &self.music_gameover and !rl.isMusicStreamPlaying(self.current_music.*)) {
        self.current_music = &self.music_level;
        rl.seekMusicStream(self.current_music.*, 0);
        rl.playMusicStream(self.current_music.*);
    }
    // rl.updateMusicStream(self.current_music.*);
    // Update
    //----------------------------------------------------------------------------------
    // TODO: Update your variables here
    //----------------------------------------------------------------------------------
    const delta_time = rl.getFrameTime();

    if (delta_time > DT_TRESHOLD) {
        std.debug.print("Stutter detected, throwing away frame\n", .{});
        return;
    }

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
            try self.scene.reset();
        }

        if (rl.isKeyPressed(rl.KeyboardKey.key_o)) {
            self.debug_mode = if (self.debug_mode == self.debug_flags.len - 1) -2 else self.debug_mode + 1;
            self.setDebugMode();
        }

        if (rl.isKeyPressed(rl.KeyboardKey.key_u)) {
            self.debug_sprite_previewer = if (self.debug_sprite_previewer == null) debug.SpriteDebugPreviewer.init(Actor.Player.Knight.sprite_reader()) else null;
        }

        if (rl.isKeyDown(rl.KeyboardKey.key_left_shift) and rl.isKeyPressed(rl.KeyboardKey.key_t)) {
            self.editor_mode = !self.editor_mode;
            self.viewport.setTargetRect(if (!self.editor_mode) constants.VIEWPORT_BIG_RECT else constants.VIEWPORT_SMALL_RECT);
        }

        self.viewport.update(delta_time);
        self.scene.layer_visibility_treshold = null;
        try self.scene.update(delta_time, self);
        self.hud.update(delta_time);

        if (self.editor_mode) {
            try self.editor.update(delta_time);
        }
    }
}

pub fn draw(self: *GameState) void {
    const zone = tracing.ZoneN(@src(), "Game Draw");
    defer zone.End();

    const screen_width: f32 = @floatFromInt(rl.getScreenWidth());
    const screen_height: f32 = @floatFromInt(rl.getScreenHeight());
    const scale = @min(
        screen_width / constants.GAME_SIZE_X,
        screen_height / constants.GAME_SIZE_Y,
    );

    rl.beginTextureMode(self.render_texture);
    rl.clearBackground(rl.Color.black);

    self.vmouse.update(scale);

    if (self.debug_sprite_previewer) |previewer| {
        previewer.draw();
    } else {
        self.viewport.draw();
        self.scene.draw(self);
        self.hud.draw(self.scene);

        self.scene.drawDebug();

        if (self.editor_mode) {
            self.editor.draw();
        }
    }

    if (debug.isDebugFlagSet(.ShowFps)) {
        rl.drawFPS(constants.GAME_SIZE_X - 150, constants.GAME_SIZE_Y - 20);
    }

    if (self.hr_recompiling) {
        rl.drawTextEx(self.font, "Recompiling...", .{ .x = 30, .y = 30 }, 30, 0, rl.Color.white);
    }

    rl.endTextureMode();

    // Draw render texture to screen
    //----------------------------------------------------------------------------------
    const raylib_draw_zone = tracing.ZoneN(@src(), "Raylib Draw");
    defer raylib_draw_zone.End();

    rl.beginDrawing();
    defer rl.endDrawing();

    // const rl_shader_mode_zone = tracing.ZoneN(@src(), "Raylib Shader Mode");
    // defer rl_shader_mode_zone.End();
    //
    // rl.beginShaderMode(self.post_processing_shader);
    // defer rl.endShaderMode();

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

fn setDebugMode(self: *const GameState) void {
    debug.clearDebugFlags();
    if (self.debug_mode == -1) {
        debug.setDebugFlags(self.debug_flags);
    } else if (self.debug_mode >= 0) {
        debug.setDebugFlags(self.debug_flags[@as(usize, @intCast(self.debug_mode)) .. @as(usize, @intCast(self.debug_mode)) + 1]);
    }
}

pub fn loadSceneFromFile(gamestate: *GameState, file_path: []const u8) !void {
    const file = try helpers.openFile(file_path, .{ .mode = .read_only });
    defer file.close();
    gamestate.scene = try Scene.readBytes(gamestate.allocator, file.reader(), gamestate);
    gamestate.scene_file = file_path;
}

pub const MIN_ACCEPTABLE_FPS = 20;
pub const DT_TRESHOLD: f32 = 1.0 / @as(f32, @floatFromInt(MIN_ACCEPTABLE_FPS));

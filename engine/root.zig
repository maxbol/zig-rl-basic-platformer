const Actor = @import("actor/actor.zig");
const Editor = @import("editor.zig");
const GameState = @import("gamestate.zig");
const HUD = @import("hud.zig");
const Scene = @import("scene.zig");
const TileLayer = @import("tile_layer/tile_layer.zig");
const Tileset = @import("tileset/tileset.zig");
const Viewport = @import("viewport.zig");
const an = @import("animation.zig");
const constants = @import("constants.zig");
const controls = @import("controls.zig");
const debug = @import("debug.zig");
const helpers = @import("helpers.zig");
const rl = @import("raylib");
const std = @import("std");

pub fn gameInit(allocator: std.mem.Allocator) *GameState {
    // tracing.InitThread();
    const game_state = GameState.create(allocator) catch @panic("Failed to create game state");
    return game_state;
}

pub fn gameDeinit(gamestate: *GameState) void {
    return gamestate.deinit();
}

pub fn gameReload(gamestate: *GameState) void {
    return gamestate.reload();
}

pub fn gameSetupRaylib(gamestate: *GameState) void {
    rl.setWindowMinSize(constants.GAME_SIZE_X, constants.GAME_SIZE_Y);
    rl.setTargetFPS(120); // Set our game to run at 60 frames-per-second

    gamestate.render_texture = rl.loadRenderTexture(constants.GAME_SIZE_X, constants.GAME_SIZE_Y);
    rl.setTextureFilter(gamestate.render_texture.texture, .texture_filter_bilinear);

    // Play music
    // TODO(23/09/2024): Handle this somewhere else
    rl.playMusicStream(gamestate.current_music.*);
}

pub fn gameTeardownRaylib(gamestate: *GameState) void {
    rl.unloadRenderTexture(gamestate.render_texture);
}

pub fn gameUpdate(gamestate: *GameState) void {
    return gamestate.update() catch @panic("Failed to update game state");
}

pub fn gameDraw(gamestate: *GameState) void {
    return gamestate.draw();
}

pub fn gameNotifyHRStarted(gamestate: *GameState) void {
    return gamestate.notifyHRStarted();
}

pub fn gameNotifyHRDone(gamestate: *GameState) void {
    return gamestate.notifyHRDone();
}

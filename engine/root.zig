const Actor = @import("actor/actor.zig");
const Editor = @import("editor.zig");
const GameState = @import("gamestate.zig");
const HUD = @import("hud.zig");
const Scene = @import("scene.zig");
const Sprite = @import("sprite.zig");
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

export fn gameInit() callconv(.C) *anyopaque {
    const game_state = GameState.create() catch @panic("Failed to create game state");
    return game_state;
}

export fn gameDeinit(ctx: *anyopaque) callconv(.C) void {
    const self: *GameState = @ptrCast(@alignCast(ctx));
    return self.deinit();
}

export fn gameReload(ctx: *anyopaque) callconv(.C) void {
    const self: *GameState = @ptrCast(@alignCast(ctx));
    return self.reload();
}

export fn gameSetupRaylib(ctx: *anyopaque) callconv(.C) void {
    const game_state: *GameState = @ptrCast(@alignCast(ctx));

    rl.setWindowMinSize(constants.GAME_SIZE_X, constants.GAME_SIZE_Y);
    rl.setTargetFPS(120); // Set our game to run at 60 frames-per-second

    game_state.render_texture = rl.loadRenderTexture(constants.GAME_SIZE_X, constants.GAME_SIZE_Y);
    rl.setTextureFilter(game_state.render_texture.texture, .texture_filter_bilinear);

    // Play music
    // TODO(23/09/2024): Handle this somewhere else
    rl.playMusicStream(game_state.current_music.*);
}

export fn gameTeardownRaylib(ctx: *anyopaque) callconv(.C) void {
    const game_state: *GameState = @ptrCast(@alignCast(ctx));

    rl.unloadRenderTexture(game_state.render_texture);
}

export fn gameUpdate(ctx: *anyopaque) callconv(.C) void {
    const game_state: *GameState = @ptrCast(@alignCast(ctx));
    return game_state.update() catch @panic("Failed to update game state");
}

export fn gameDraw(ctx: *anyopaque) callconv(.C) void {
    const game_state: *GameState = @ptrCast(@alignCast(ctx));
    return game_state.draw();
}

export fn gameNotifyHRStarted(ctx: *anyopaque) callconv(.C) void {
    const game_state: *GameState = @ptrCast(@alignCast(ctx));
    return game_state.notifyHRStarted();
}

export fn gameNotifyHRDone(ctx: *anyopaque) callconv(.C) void {
    const game_state: *GameState = @ptrCast(@alignCast(ctx));
    return game_state.notifyHRDone();
}

const builtin = @import("builtin");
const rl = @import("raylib");
const std = @import("std");
const engine = @import("root.zig");
const tracing = @import("tracing.zig");

pub const INITIAL_WINDOW_SIZE_X = 1600;
pub const INITIAL_WINDOW_SIZE_Y = 900;

pub fn main() anyerror!void {
    tracing.AppInfo("Hello world!");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    rl.setConfigFlags(.{
        .fullscreen_mode = true,
        .vsync_hint = true,
        .window_resizable = true,
    });
    rl.initWindow(INITIAL_WINDOW_SIZE_X, INITIAL_WINDOW_SIZE_Y, "knight jumper");
    rl.initAudioDevice();

    const game_state = engine.gameInit(allocator);

    engine.gameSetupRaylib(game_state);
    defer engine.gameTeardownRaylib(game_state);

    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        tracing.FrameMark();
        //
        engine.gameUpdate(game_state);
        engine.gameDraw(game_state);
    }
}

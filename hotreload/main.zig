const builtin = @import("builtin");
const rl = @import("raylib");
const std = @import("std");

pub const INITIAL_WINDOW_SIZE_X = 1600;
pub const INITIAL_WINDOW_SIZE_Y = 900;

var gameInit: *const fn (allocator: std.mem.Allocator) *anyopaque = undefined;
var gameDeinit: *const fn (*anyopaque) void = undefined;
var gameReload: *const fn (*anyopaque) void = undefined;
var gameSetupRaylib: *const fn (*anyopaque) void = undefined;
var gameTeardownRaylib: *const fn (*anyopaque) void = undefined;
var gameUpdate: *const fn (*anyopaque) void = undefined;
var gameDraw: *const fn (*anyopaque) void = undefined;

var game_dyn_lib: ?std.DynLib = null;

fn loadGameDll() !void {
    if (game_dyn_lib != null) return error.AlreadyLoaded;
    const src = switch (builtin.os.tag) {
        .windows => "zig-out/lib/libengine.dll",
        .macos => "zig-out/lib/libengine.dylib",
        .linux => "zig-out/lib/libengine.so",
        else => return error.UnsupportedOS,
    };
    std.debug.print("loading dll from {s}\n", .{src});
    var dyn_lib = std.DynLib.open(src) catch {
        return error.OpenFail;
    };
    game_dyn_lib = dyn_lib;

    gameInit = dyn_lib.lookup(@TypeOf(gameInit), "gameInit") orelse return error.LookupFailed;
    gameDeinit = dyn_lib.lookup(@TypeOf(gameDeinit), "gameDeinit") orelse return error.LookupFailed;
    gameReload = dyn_lib.lookup(@TypeOf(gameReload), "gameReload") orelse return error.LookupFailed;
    gameSetupRaylib = dyn_lib.lookup(@TypeOf(gameSetupRaylib), "gameSetupRaylib") orelse return error.LookupFailed;
    gameTeardownRaylib = dyn_lib.lookup(@TypeOf(gameTeardownRaylib), "gameTeardownRaylib") orelse return error.LookupFailed;
    gameUpdate = dyn_lib.lookup(@TypeOf(gameUpdate), "gameUpdate") orelse return error.LookupFailed;
    gameDraw = dyn_lib.lookup(@TypeOf(gameDraw), "gameDraw") orelse return error.LookupFailed;
    std.debug.print("Loaded game dll\n", .{});
}

fn unloadGameDll() void {}
fn recompileGameDll() void {}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    rl.setConfigFlags(.{
        // .fullscreen_mode = true,
        .vsync_hint = true,
        .window_resizable = true,
    });
    rl.initWindow(INITIAL_WINDOW_SIZE_X, INITIAL_WINDOW_SIZE_Y, "knight jumper");
    rl.initAudioDevice();

    loadGameDll() catch @panic("Failed to load game dll");

    const game_state = gameInit(allocator);

    gameSetupRaylib(game_state);
    defer gameTeardownRaylib(game_state);

    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        if (rl.isKeyPressed(rl.KeyboardKey.key_f5)) {
            unloadGameDll();
            recompileGameDll();
            try loadGameDll();
            gameReload(game_state);
        }

        gameUpdate(game_state);
        gameDraw(game_state);
    }
}

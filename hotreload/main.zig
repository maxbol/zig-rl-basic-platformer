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
var gameNotifyHRStarted: *const fn (*anyopaque) void = undefined;
var gameNotifyHRDone: *const fn (*anyopaque) void = undefined;

var game_dyn_lib: ?std.DynLib = null;

fn getDllPath(allocator: std.mem.Allocator, dll_timestamp: ?i64) ![]const u8 {
    const dll_name = if (dll_timestamp) |ts| std.fmt.allocPrint(allocator, "libengine-hr-{d}", .{ts}) catch {
        return error.NameBufferTooSmall;
    } else "libengine";

    const fmt = switch (builtin.os.tag) {
        .windows => "zig-out/lib/{s}.dll",
        .macos => "zig-out/lib/{s}.dylib",
        .linux => "zig-out/lib/{s}.so",
        else => return error.UnsupportedOS,
    };
    return std.fmt.allocPrint(allocator, fmt, .{dll_name}) catch {
        return error.NameBufferTooSmall;
    };
}

fn loadGameDll(dll_path: []const u8) !void {
    std.debug.print("loading dll from \"{s}\"\n", .{dll_path});
    var dyn_lib = std.DynLib.open(dll_path) catch {
        return error.OpenFail;
    };
    game_dyn_lib = dyn_lib;

    // Lookup lifecycle hooks
    gameInit = dyn_lib.lookup(
        @TypeOf(gameInit),
        "gameInit",
    ) orelse return error.LookupFailed;
    gameDeinit = dyn_lib.lookup(
        @TypeOf(gameDeinit),
        "gameDeinit",
    ) orelse return error.LookupFailed;
    gameReload = dyn_lib.lookup(
        @TypeOf(gameReload),
        "gameReload",
    ) orelse return error.LookupFailed;
    gameSetupRaylib = dyn_lib.lookup(
        @TypeOf(gameSetupRaylib),
        "gameSetupRaylib",
    ) orelse return error.LookupFailed;
    gameTeardownRaylib = dyn_lib.lookup(
        @TypeOf(gameTeardownRaylib),
        "gameTeardownRaylib",
    ) orelse return error.LookupFailed;
    gameUpdate = dyn_lib.lookup(
        @TypeOf(gameUpdate),
        "gameUpdate",
    ) orelse return error.LookupFailed;
    gameDraw = dyn_lib.lookup(
        @TypeOf(gameDraw),
        "gameDraw",
    ) orelse return error.LookupFailed;
    gameNotifyHRStarted = dyn_lib.lookup(
        @TypeOf(gameNotifyHRStarted),
        "gameNotifyHRStarted",
    ) orelse return error.LookupFailed;
    gameNotifyHRDone = dyn_lib.lookup(
        @TypeOf(gameNotifyHRDone),
        "gameNotifyHRDone",
    ) orelse return error.LookupFailed;
}

fn unloadGameDll() !void {
    if (game_dyn_lib) |*dyn_lib| {
        dyn_lib.close();
        game_dyn_lib = null;
    } else {
        return error.AlreadyUnloaded;
    }
}

fn recompileGameDll(allocator: std.mem.Allocator, ts: i64) void {
    var ts_arg_buf: [512]u8 = undefined;
    const ts_arg = std.fmt.bufPrint(&ts_arg_buf, "-Dengine_dll_ts={d}", .{ts}) catch @panic("Out of memory");
    const process_args = [_][]const u8{
        "zig",
        "build",
        "-Dgame_only",
        "-Dhotreload",
        ts_arg,
        "--search-prefix",
        "./zig-out",
    };

    var build_process = std.process.Child.init(&process_args, allocator);
    build_process.spawn() catch @panic("Unable to spawn build process");

    const term = build_process.wait() catch @panic("Unable to wait for build process");
    switch (term) {
        .Exited => |exit_code| {
            if (exit_code == 2) {
                @panic("Recompile failed");
            }
        },
        else => return,
    }
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    rl.setConfigFlags(.{
        .fullscreen_mode = true,
        .vsync_hint = true,
        .window_resizable = true,
    });
    rl.initWindow(INITIAL_WINDOW_SIZE_X, INITIAL_WINDOW_SIZE_Y, "knight jumper");
    rl.initAudioDevice();

    const dll_path = getDllPath(allocator, null) catch @panic("Out of memory");
    loadGameDll(dll_path) catch @panic("Failed to load game dll");

    const game_state = gameInit(allocator);

    gameSetupRaylib(game_state);
    defer gameTeardownRaylib(game_state);

    var wg = std.Thread.WaitGroup{};
    defer wg.wait();

    var await_recomp_lib_path: ?[]const u8 = null;

    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        if (rl.isKeyPressed(rl.KeyboardKey.key_f5)) {
            // Get timestamp based library name
            const ts = std.time.milliTimestamp();
            await_recomp_lib_path = getDllPath(allocator, ts) catch @panic("Out of memory");
            gameNotifyHRStarted(game_state);

            wg.spawnManager(
                recompileGameDll,
                .{
                    allocator,
                    ts,
                },
            );
        }

        if (await_recomp_lib_path) |path| blk: {
            std.fs.cwd().access(path, .{ .mode = .read_only }) catch |err| {
                if (err == error.FileNotFound) {
                    break :blk;
                }
            };

            unloadGameDll() catch unreachable;
            loadGameDll(path) catch @panic("Failed to load game dll");
            gameReload(game_state);
            gameNotifyHRDone(game_state);

            await_recomp_lib_path = null;
        }

        gameUpdate(game_state);
        gameDraw(game_state);
    }
}

const std = @import("std");
const rl = @import("raylib");

pub const RAD2DEG = 180.0 / std.math.pi;

pub const KBD_MOVE_RIGHT: *const [1]rl.KeyboardKey = &.{rl.KeyboardKey.key_d};
pub const KBD_MOVE_LEFT: *const [1]rl.KeyboardKey = &.{rl.KeyboardKey.key_a};
pub const KBD_JUMP: *const [1]rl.KeyboardKey = &.{rl.KeyboardKey.key_w};
pub const KBD_ROLL: *const [1]rl.KeyboardKey = &.{rl.KeyboardKey.key_h};
pub const KBD_PAUSE: *const [1]rl.KeyboardKey = &.{rl.KeyboardKey.key_p};

pub const WINDOW_SIZE_X = 1600;
pub const WINDOW_SIZE_Y = 900;

pub const GAME_SIZE_X = 640;
pub const GAME_SIZE_Y = 360;

pub const TILE_SIZE = 16;

pub const VIEWPORT_PADDING_X = TILE_SIZE + (GAME_SIZE_X % TILE_SIZE / 2);
pub const VIEWPORT_PADDING_Y = TILE_SIZE + (GAME_SIZE_Y % TILE_SIZE / 2);

pub const VIEWPORT_BIG_WIDTH = GAME_SIZE_X - (VIEWPORT_PADDING_X * 2);
pub const VIEWPORT_BIG_HEIGHT = GAME_SIZE_Y - (VIEWPORT_PADDING_Y * 2);

pub const VIEWPORT_SMALL_WIDTH = VIEWPORT_BIG_WIDTH - (TILE_SIZE * 10);
pub const VIEWPORT_SMALL_HEIGHT = VIEWPORT_BIG_HEIGHT - (TILE_SIZE * 5);

pub fn isKeyboardControlDown(key_binding: []const rl.KeyboardKey) bool {
    for (key_binding) |key| {
        if (rl.isKeyDown(key)) {
            return true;
        }
    }
    return false;
}

pub fn isKeyboardControlPressed(key_binding: []const rl.KeyboardKey) bool {
    for (key_binding) |key| {
        if (rl.isKeyPressed(key)) {
            return true;
        }
    }
    return false;
}

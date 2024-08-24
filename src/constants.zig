const std = @import("std");
const rl = @import("raylib");

pub const RAD2DEG = 180.0 / std.math.pi;

pub const KBD_MOVE_RIGHT: *const [1]rl.KeyboardKey = &.{rl.KeyboardKey.key_d};
pub const KBD_MOVE_LEFT: *const [1]rl.KeyboardKey = &.{rl.KeyboardKey.key_a};
pub const KBD_JUMP: *const [2]rl.KeyboardKey = &.{ rl.KeyboardKey.key_w, rl.KeyboardKey.key_space };
pub const KBD_PAUSE: *const [1]rl.KeyboardKey = &.{rl.KeyboardKey.key_p};

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

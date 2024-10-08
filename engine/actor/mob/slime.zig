const Mob = @import("../mob.zig");
const an = @import("../../animation.zig");
const rl = @import("raylib");
const scriptFile = @embedFile("slime.luau");
const std = @import("std");
const ziglua = @import("ziglua");

var texture: ?rl.Texture = null;

pub const SpriteBuffer = an.SpriteBuffer(
    Mob.AnimationType,
    &.{
        .Walk,
        .Attack,
        .Hit,
    },
    .{},
    loadTexture,
    .{ .x = 24, .y = 24 },
    6,
);

fn loadTexture() rl.Texture {
    return texture orelse {
        texture = rl.loadTexture("assets/sprites/slime_green.png");
        return texture.?;
    };
}

var sprite_buffer = blk: {
    var buffer = SpriteBuffer{};
    buffer.writeAnimation(.Walk, 1, &.{ 1, 2, 3, 4, 3, 2 });
    buffer.writeAnimation(.Attack, 0.5, &.{ 5, 6, 7, 8 });
    buffer.writeAnimation(.Hit, 0.1, &.{ 9, 10, 11, 12 });
    break :blk buffer;
};

pub fn getSpriteReader() an.AnySpriteBuffer {
    sprite_buffer.prebakeBuffer();
    return sprite_buffer.reader();
}

fn getScript(allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
    return ziglua.compile(allocator, scriptFile, .{}) catch error.OutOfMemory;
}

pub const green_slime_behavior = Mob.MobBehavior{
    .walk_speed = 1 * 60,
    .fall_speed = 3.6 * 60,
    .hunt_speed = 2 * 60,
    .jump_speed = -4 * 60,
    .hunt_acceleration = 10 * 60,
    .line_of_sight = 10, // See 10 tiles ahead
};

pub const GreenSlime = Mob.Prefab(
    // ID
    0,
    // Hitbox
    .{
        .x = 0,
        .y = 0,
        .width = 12,
        .height = 12,
    },
    // Sprite offset
    .{
        .x = -6,
        .y = -12,
    },
    // Behavior
    &green_slime_behavior,
    getSpriteReader,
    getScript,
);

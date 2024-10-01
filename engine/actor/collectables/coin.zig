const Collectable = @import("../collectable.zig");
const Player = @import("../../actor/player.zig");
const Sprite = @import("../../sprite.zig");
const an = @import("../../animation.zig");
const rl = @import("raylib");
const std = @import("std");

const SpriteBuffer = an.SpriteBuffer(
    Collectable.AnimationType,
    &.{.Static},
    .{},
    loadTexture,
    .{ .x = 16, .y = 16 },
    12,
);

var sound: ?rl.Sound = null;
var texture: ?rl.Texture = null;

fn loadSound() rl.Sound {
    if (sound) |s| {
        return s;
    }
    sound = rl.loadSound("assets/sounds/coin.wav");
    return sound.?;
}

fn loadTexture() rl.Texture2D {
    if (texture) |t| {
        return t;
    }
    texture = rl.loadTexture("assets/sprites/coin.png");
    return texture.?;
}

var sprite_buffer: SpriteBuffer = blk: {
    var buffer = SpriteBuffer{};

    buffer.writeAnimation(.Static, 0.6, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 });

    break :blk buffer;
};

fn getSpriteReader() an.AnySpriteBuffer {
    sprite_buffer.prebakeBuffer();
    return sprite_buffer.reader();
}

fn onCollected(_: *Collectable, player: *Player) bool {
    return player.gainScore(100);
}

pub const Coin = Collectable.Prefab(
    0,
    .{
        .x = 0,
        .y = 0,
        .width = 10,
        .height = 10,
    },
    .{
        .x = -3,
        .y = -3,
    },
    getSpriteReader,
    loadSound,
    onCollected,
);

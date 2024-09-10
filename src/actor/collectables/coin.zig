const Collectable = @import("../collectable.zig");
const Player = @import("../../actor/player.zig");
const Sprite = @import("../../sprite.zig");
const an = @import("../../animation.zig");
const rl = @import("raylib");
const std = @import("std");

const AnimationBuffer = an.AnimationBuffer(&.{.Idle}, 12);

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

fn getAnimationBuffer() AnimationBuffer {
    var buffer = AnimationBuffer{};

    buffer.writeAnimation(.Idle, 0.6, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 });

    return buffer;
}

fn onCollected(_: *Collectable, player: *Player) void {
    player.score += 100;
    std.debug.print("Your score is {d}\n", .{player.score});
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
        .x = 3,
        .y = 3,
    },
    Sprite.Prefab(
        16,
        16,
        loadTexture,
        getAnimationBuffer(),
        .Idle,
        rl.Vector2{ .x = 0, .y = 0 },
    ),
    loadSound,
    onCollected,
);

const Collectable = @import("../collectable.zig");
const Player = @import("../../actor/player.zig");
const Sprite = @import("../../sprite.zig");
const an = @import("../../animation.zig");
const rl = @import("raylib");
const std = @import("std");

const AnimationType = enum(u8) {
    Idle,
};

const AnimationBuffer = an.AnimationBuffer(AnimationType, &.{.Idle}, 1);

var sound: ?rl.Sound = null;
var texture: ?rl.Texture = null;

fn loadSound() rl.Sound {
    if (sound) |s| {
        return s;
    }
    sound = rl.loadSound("assets/sounds/power_up.wav");
    return sound.?;
}

fn loadTexture() rl.Texture2D {
    if (texture) |t| {
        return t;
    }
    texture = rl.loadTexture("assets/sprites/fruit.png");
    return texture.?;
}

fn getAnimationBuffer(offset: usize) AnimationBuffer {
    var buffer = AnimationBuffer{};
    buffer.writeAnimation(.Idle, 1, &.{offset});
    return buffer;
}

fn onHealthGrapeCollected(_: *Collectable, player: *Player) void {
    player.lives += 1;
    std.debug.print("Your lives are {d}\n", .{player.lives});
}

pub fn Fruit(offset: usize, on_collected: fn (*Collectable, *Player) void) type {
    return Collectable.Prefab(
        1,
        .{
            .x = 0,
            .y = 0,
            .width = 16,
            .height = 16,
        },
        .{
            .x = 0,
            .y = 0,
        },
        Sprite.Prefab(
            16,
            16,
            loadTexture,
            getAnimationBuffer(offset),
            an.NoAnimationsType.Idle,
            rl.Vector2{ .x = 0, .y = 0 },
        ),
        loadSound,
        on_collected,
    );
}

pub const HealthGrape = Fruit(15, onHealthGrapeCollected);

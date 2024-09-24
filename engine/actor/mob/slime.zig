const Mob = @import("../mob.zig");
const Sprite = @import("../../sprite.zig");
const an = @import("../../animation.zig");
const rl = @import("raylib");

var texture: ?rl.Texture = null;

fn loadTexture() rl.Texture {
    return texture orelse {
        texture = rl.loadTexture("assets/sprites/slime_green.png");
        return texture.?;
    };
}

fn getAnimations() Mob.AnimationBuffer {
    var buffer = Mob.AnimationBuffer{};

    buffer.writeAnimation(.Walk, 1, &.{ 1, 2, 3, 4, 3, 2 });
    buffer.writeAnimation(.Attack, 0.5, &.{ 5, 6, 7, 8 });
    buffer.writeAnimation(.Hit, 0.1, &.{ 9, 10, 11, 12 });

    return buffer;
}

pub const green_slime_behavior = Mob.MobBehavior{
    .walk_speed = 3 * 60,
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
        .x = 6,
        .y = 12,
    },
    // Behavior
    &green_slime_behavior,
    // Sprite
    Sprite.Prefab(
        // Width
        24,
        // Height
        24,
        // Texture path
        loadTexture,
        // Animation buffer
        getAnimations(),
        // Initial animation
        Mob.AnimationType.Walk,
        rl.Vector2{ .x = 0, .y = 0 },
    ),
);

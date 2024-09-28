const Effect = @import("../effect.zig");
const Sprite = @import("../sprite.zig");
const an = @import("../animation.zig");
const rl = @import("raylib");

var texture: ?rl.Texture2D = null;

fn loadTexture() rl.Texture2D {
    return texture orelse {
        texture = rl.loadTexture("assets/sprites/dust.png");
        return texture.?;
    };
}

fn getAnimationBuffer() Effect.AnimationBuffer {
    // @compileLog("Building effect/dust animation buffer...");
    var buffer = Effect.AnimationBuffer{};
    buffer.writeAnimation(.Invisible, 1, &.{});
    buffer.writeAnimation(.Playing, 0.3, &.{ 2, 3, 4, 5, 6 });
    return buffer;
}

pub const Dust = Effect.Prefab(
    Sprite.Prefab(
        8,
        8,
        loadTexture,
        getAnimationBuffer(),
        Effect.AnimationType.Playing,
        .{ .x = 0, .y = 0 },
    ),
);

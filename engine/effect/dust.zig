const Effect = @import("../effect.zig");
const an = @import("../animation.zig");
const rl = @import("raylib");

pub const SpriteBuffer = an.SpriteBuffer(
    Effect.AnimationType,
    &.{
        .Stopped,
        .Playing,
    },
    .{},
    loadTexture,
    .{ .x = 8, .y = 8 },
    6,
);

var texture: ?rl.Texture2D = null;

fn loadTexture() rl.Texture2D {
    return texture orelse {
        texture = rl.loadTexture("assets/sprites/dust.png");
        return texture.?;
    };
}

var sprite_buffer = blk: {
    var buffer = SpriteBuffer{};
    buffer.writeAnimation(.Stopped, 1, &.{});
    buffer.writeAnimation(.Playing, 0.3, &.{ 2, 3, 4, 5, 6 });
    break :blk buffer;
};

fn getSpriteReader() an.AnySpriteBuffer {
    sprite_buffer.prebakeBuffer();
    return sprite_buffer.reader();
}

pub const Dust = Effect.Prefab(getSpriteReader, SpriteBuffer.size, true);

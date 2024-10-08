const Effect = @import("../../effect.zig");
const an = @import("../../animation.zig");
const rl = @import("raylib");

pub const Transforms = struct {
    pub fn rotate90Deg(frame: rl.RenderTexture2D) rl.RenderTexture2D {
        return an.Transforms.rotate(frame, -90, .BottomCenter);
    }
};

pub const SpriteBuffer = an.SpriteBuffer(
    Effect.AnimationType,
    &.{
        .Stopped,
        .Playing,
    },
    &.{
        Transforms.rotate90Deg,
    },
    loadTexture,
    .{ .x = 32, .y = 32 },
    5,
);

var texture: ?rl.Texture2D = null;
fn loadTexture() rl.Texture2D {
    return texture orelse {
        texture = rl.loadTexture("assets/sprites/excalibur.png");
        return texture.?;
    };
}

var sprite_buffer = blk: {
    var buffer = SpriteBuffer{};
    buffer.writeAnimation(.Stopped, 1, &.{1});
    buffer.writeAnimation(.Playing, 0.3, &.{
        5,
        an.f(.{ .transform_mask = 0b1, .frame_pointer = 5 }),
        an.f(.{ .transform_mask = 0b1, .frame_pointer = 6 }),
        an.f(.{ .transform_mask = 0b1, .frame_pointer = 7 }),
        an.f(.{ .transform_mask = 0b1, .frame_pointer = 8 }),
    });
    break :blk buffer;
};

fn getSpriteReader() an.AnySpriteBuffer {
    sprite_buffer.prebakeBuffer();
    return sprite_buffer.reader();
}

pub const WeaponExcalibur = Effect.Prefab(getSpriteReader, SpriteBuffer.size, false);

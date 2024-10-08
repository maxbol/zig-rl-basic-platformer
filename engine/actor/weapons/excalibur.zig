const Weapon = @import("../weapon.zig");
const an = @import("../../animation.zig");
const rl = @import("raylib");

pub const Transforms = struct {
    pub fn flipX(frame: rl.RenderTexture2D) rl.RenderTexture2D {
        return an.Transforms.flip(frame, true, false);
    }
    pub fn extendCanvas(frame: rl.RenderTexture2D) rl.RenderTexture2D {
        // return an.Transforms.resizeCanvas(frame, )
        return frame;
    }
    pub fn rotate90Deg(frame: rl.RenderTexture2D) rl.RenderTexture2D {
        return an.Transforms.rotate(frame, -90, .BottomCenter);
    }
};

pub const SpriteBuffer = an.SpriteBuffer(
    Weapon.AnimationType,
    &.{ .CarriedLeft, .CarriedRight, .AttackLeft, .AttackRight },
    &.{
        Transforms.flipX,
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
    buffer.writeAnimation(.CarriedLeft, 1, &.{an.f(.{
        .transform_mask = 0b1,
        .frame_pointer = 1,
    })});
    buffer.writeAnimation(.CarriedRight, 1, &.{1});
    buffer.writeAnimation(.AttackLeft, 0.3, &.{
        5,
        an.f(.{ .transform_mask = 0b11, .frame_pointer = 5 }),
        an.f(.{ .transform_mask = 0b11, .frame_pointer = 6 }),
        an.f(.{ .transform_mask = 0b11, .frame_pointer = 7 }),
        an.f(.{ .transform_mask = 0b11, .frame_pointer = 8 }),
    });
    buffer.writeAnimation(.AttackRight, 0.3, &.{
        5,
        an.f(.{ .transform_mask = 0b10, .frame_pointer = 5 }),
        an.f(.{ .transform_mask = 0b10, .frame_pointer = 6 }),
        an.f(.{ .transform_mask = 0b10, .frame_pointer = 7 }),
        an.f(.{ .transform_mask = 0b10, .frame_pointer = 8 }),
    });
    break :blk buffer;
};

fn getSpriteReader() an.AnySpriteBuffer {
    sprite_buffer.prebakeBuffer();
    return sprite_buffer.reader();
}

pub const WeaponExcalibur = Weapon.Prefab(0, getSpriteReader);

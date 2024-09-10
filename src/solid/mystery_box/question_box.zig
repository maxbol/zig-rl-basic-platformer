const MysteryBox = @import("../mystery_box.zig");
const Sprite = @import("../../sprite.zig");
const an = @import("../../animation.zig");
const rl = @import("raylib");

var texture: ?rl.Texture2D = null;

fn loadTexture() rl.Texture2D {
    return texture orelse {
        texture = rl.loadTexture("assets/sprites/mystery-boxes.png");
        return texture.?;
    };
}

fn SpritePrefab(offset: usize) type {
    return Sprite.Prefab(
        16,
        16,
        loadTexture,
        an.getNoAnimationsBuffer(),
        an.NoAnimationsType.Idle,
        .{
            .x = offset,
            .y = 0,
        },
    );
}

const SpringSprite = SpritePrefab(0);
const SummerSprite = SpritePrefab(48);
const FallSprite = SpritePrefab(64);
const WinterSprite = SpritePrefab(96);

pub const QSpringC5 = MysteryBox.Prefab(
    &.{
        .{
            .prefab_idx = 0,
            .amount = 5,
        },
    },
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
    SpringSprite,
);

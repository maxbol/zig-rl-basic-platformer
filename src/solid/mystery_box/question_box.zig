const MysteryBox = @import("../mystery_box.zig");
const Sprite = @import("../../sprite.zig");
const an = @import("../../animation.zig");
const rl = @import("raylib");

var sound_dud: ?rl.Sound = null;
var texture: ?rl.Texture2D = null;

fn loadTexture() rl.Texture2D {
    return texture orelse {
        texture = rl.loadTexture("assets/sprites/mystery-boxes.png");
        return texture.?;
    };
}

fn loadSoundDud() rl.Sound {
    return sound_dud orelse {
        sound_dud = rl.loadSound("assets/sounds/hurt.wav");
        return sound_dud.?;
    };
}

fn getAnimationBuffer(hidden_box: bool) MysteryBox.AnimationBuffer {
    var buffer = MysteryBox.AnimationBuffer{};

    buffer.writeAnimation(.Initial, 1, &.{if (hidden_box) 2 else 1});
    buffer.writeAnimation(.Active, 1, &.{1});
    buffer.writeAnimation(.Depleted, 1, &.{2});

    return buffer;
}

fn SpritePrefab(offset: usize, hidden_box: bool) type {
    return Sprite.Prefab(
        16,
        16,
        loadTexture,
        getAnimationBuffer(hidden_box),
        MysteryBox.AnimationType.Initial,
        .{
            .x = offset,
            .y = 0,
        },
    );
}

const SpringSprite = SpritePrefab(0, false);
const SummerSprite = SpritePrefab(32, false);
const FallSprite = SpritePrefab(64, false);
const WinterSprite = SpritePrefab(96, false);

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
    loadSoundDud,
);

const MysteryBox = @import("../mystery_box.zig");
const an = @import("../../animation.zig");
const rl = @import("raylib");

pub const SpriteBuffer = an.SpriteBuffer(
    MysteryBox.AnimationType,
    &.{
        .Initial,
        .Active,
        .Depleted,
    },
    .{},
    loadTexture,
    .{ .x = 16, .y = 16 },
    1,
);

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

fn getSpriteBuffer(offset: usize, hidden_box: bool) SpriteBuffer {
    // @compileLog("Building mysterybox/question_box animation buffer...");
    var buffer = SpriteBuffer{};

    const active = offset + 1;
    const depleted = offset + 2;

    buffer.writeAnimation(.Initial, 1, &.{if (hidden_box) depleted else active});
    buffer.writeAnimation(.Active, 1, &.{active});
    buffer.writeAnimation(.Depleted, 1, &.{depleted});

    return buffer;
}

var spring_spritebuf = getSpriteBuffer(0, false);
var summer_spritebuf = getSpriteBuffer(32, false);
var fall_spritebuf = getSpriteBuffer(64, false);
var winter_spritebuf = getSpriteBuffer(96, false);

fn getSpringSpriteReader() an.AnySpriteBuffer {
    spring_spritebuf.prebakeBuffer();
    return spring_spritebuf.reader();
}

pub const QSpringC5 = MysteryBox.Prefab(
    0,
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
    getSpringSpriteReader,
    loadSoundDud,
);

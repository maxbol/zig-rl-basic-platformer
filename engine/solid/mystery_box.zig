const Actor = @import("../actor/actor.zig");
const GameState = @import("../gamestate.zig");
const MysteryBox = @This();
const Scene = @import("../scene.zig");
const Solid = @import("solid.zig");
const Sprite = @import("../sprite.zig");
const an = @import("../animation.zig");
const constants = @import("../constants.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");
const types = @import("../types.zig");
const shapes = @import("../shapes.zig");
const std = @import("std");

pub const AnimationType = enum(u8) {
    Initial,
    Active,
    Depleted,
};

pub const AnimationBuffer = an.AnimationBuffer(AnimationType, &.{
    .Initial,
    .Active,
    .Depleted,
}, .{}, 1);

pub fn Prefab(
    mystery_box_type: u8,
    contents: []const Content,
    hitbox: rl.Rectangle,
    sprite_offset: rl.Vector2,
    SpritePrefab: type,
    loadSoundDud: *const fn () rl.Sound,
) type {
    return struct {
        pub const Sprite = SpritePrefab;
        pub const Hitbox = hitbox;
        pub const spr_offset = sprite_offset;

        pub fn init(pos: shapes.IPos) MysteryBox {
            const sprite = SpritePrefab.init();

            var mystery_box_hitbox = hitbox;
            mystery_box_hitbox.x = @floatFromInt(pos.x);
            mystery_box_hitbox.y = @floatFromInt(pos.y);

            const sound_dud = loadSoundDud();

            return MysteryBox.init(mystery_box_type, contents, mystery_box_hitbox, sprite, sprite_offset, sound_dud);
        }
    };
}

pub const Content = struct {
    prefab_idx: usize,
    amount: u8,
};

pub const MAX_AMOUNT_OF_CONTENTS = 5;

contents: [MAX_AMOUNT_OF_CONTENTS]Content,
contents_amount: u3,
content_idx: u3 = 0,
content_step: u8 = 0,
initial_hitbox: rl.Rectangle,
is_collidable: bool = true,
is_depleted: bool = false,
is_deleted: bool = false,
mystery_box_type: u8,
hitbox: rl.Rectangle,
sprite: Sprite,
sprite_offset: rl.Vector2,
sound_dud: rl.Sound,

pub const launch_speed: f32 = -3 * 60;

pub fn init(
    mystery_box_type: u8,
    contents: []const Content,
    hitbox: rl.Rectangle,
    sprite: Sprite,
    sprite_offset: rl.Vector2,
    sound_dud: rl.Sound,
) MysteryBox {
    const contents_amount: u3 = @intCast(contents.len);
    var _contents: [MAX_AMOUNT_OF_CONTENTS]Content = undefined;
    for (contents, 0..) |content, i| {
        _contents[i] = content;
    }
    return .{
        .contents = _contents,
        .contents_amount = contents_amount,
        .hitbox = hitbox,
        .initial_hitbox = hitbox,
        .mystery_box_type = mystery_box_type,
        .sprite = sprite,
        .sprite_offset = sprite_offset,
        .sound_dud = sound_dud,
    };
}

pub fn reset(self: *MysteryBox) void {
    self.content_idx = 0;
    self.content_step = 0;
    self.is_depleted = false;
    self.hitbox = self.initial_hitbox;
    self.sprite.reset();
}

pub fn delete(self: *MysteryBox) void {
    self.is_deleted = true;
}

pub fn solid(self: *MysteryBox) Solid {
    return .{ .ptr = self, .impl = &.{
        .getHitboxRect = getHitboxRectCast,
        .handlePlayerCollision = handlePlayerCollision,
        .isCollidable = isCollidableCast,
        .setIsCollidable = setIsCollidableCast,
    } };
}

pub inline fn getHitboxRect(self: *const MysteryBox) rl.Rectangle {
    return self.hitbox;
}

pub inline fn getInitialPos(self: *const MysteryBox) rl.Vector2 {
    return rl.Vector2.init(self.initial_hitbox.x, self.initial_hitbox.y);
}

pub inline fn isCollidable(self: *const MysteryBox) bool {
    return self.is_collidable;
}

pub inline fn setIsCollidable(self: *MysteryBox, is_collidable: bool) void {
    self.is_collidable = is_collidable;
}

fn getHitboxRectCast(ctx: *const anyopaque) rl.Rectangle {
    const self: *const MysteryBox = @ptrCast(@alignCast(ctx));
    return self.getHitboxRect();
}

fn isCollidableCast(ctx: *const anyopaque) bool {
    const self: *const MysteryBox = @ptrCast(@alignCast(ctx));
    return self.isCollidable();
}

fn setIsCollidableCast(ctx: *anyopaque, is_collidable: bool) void {
    const self: *MysteryBox = @ptrCast(@alignCast(ctx));
    self.setIsCollidable(is_collidable);
}

fn handlePlayerCollision(ctx: *anyopaque, scene: *Scene, axis: types.Axis, sign: i8, flags: u8, player: *Actor.Player) void {
    const self: *MysteryBox = @ptrCast(@alignCast(ctx));
    _ = axis; // autofix
    _ = flags; // autofix
    if (sign != -1) {
        // Only handle collision if player is moving up
        return;
    }

    if (self.is_depleted) {
        // Already depleted, let's move on!
        rl.playSound(self.sound_dud);
        return;
    }

    if (!self.isPlayingAnimation(.Active)) {
        self.sprite.setAnimation(AnimationType.Active, .{});
    }

    const content = self.contents[self.content_idx];

    if (self.content_step >= content.amount) {
        return;
    }

    const item_hitbox = blk: {
        inline for (Actor.Collectable.prefabs, 0..) |CollectablePrefab, i| {
            if (i == content.prefab_idx) {
                break :blk CollectablePrefab.Hitbox;
            }
        }
        @panic("Collectable prefab not found");
    };

    const loadSound = blk: {
        inline for (Actor.Collectable.prefabs, 0..) |CollectablePrefab, i| {
            if (i == content.prefab_idx) {
                break :blk CollectablePrefab._loadSound;
            }
        }
        @panic("Collectable prefab not found");
    };
    const sound = loadSound();
    rl.playSound(sound);

    const pos = rl.Vector2.init(
        self.hitbox.x + (self.hitbox.width / 2) - (item_hitbox.width / 2),
        self.hitbox.y - item_hitbox.height,
    );

    const item = scene.spawnCollectable(content.prefab_idx, pos) catch |err| {
        std.log.err("Error spawning collectable from mystery box: {!}", .{err});
        std.process.exit(1);
    };

    item.rigid_body.mode = .Rigid;
    item.speed.x = player.speed.x / std.math.pi;
    item.speed.y = launch_speed;

    self.content_step += 1;

    while (self.content_step >= self.contents[self.content_idx].amount) {
        self.content_idx += 1;
        self.content_step = 0;

        if (self.content_idx >= self.contents_amount) {
            self.is_depleted = true;
            return;
        }
    }
}

fn isPlayingAnimation(self: *MysteryBox, animation: AnimationType) bool {
    return self.sprite.current_animation.data.type == @as(u8, @intFromEnum(animation));
}

pub fn update(self: *MysteryBox, scene: *Scene, delta_time: f32) !void {
    if (self.is_deleted) {
        return;
    }
    if (self.is_depleted) {
        if (!self.isPlayingAnimation(AnimationType.Depleted)) {
            self.sprite.setAnimation(AnimationType.Depleted, .{});
        }
    }
    try self.sprite.update(scene, delta_time);
}

pub fn draw(self: *const MysteryBox, scene: *const Scene) void {
    if (self.is_deleted) {
        return;
    }
    const sprite_pos = helpers.getRelativePos(self.sprite_offset, self.hitbox);
    self.sprite.draw(scene, sprite_pos, rl.Color.white);
}

pub const QSpringC5 = @import("mystery_box/question_box.zig").QSpringC5;

pub const prefabs = [_]type{
    QSpringC5,
};

pub fn initMysteryBoxByIndex(index: usize, pos: shapes.IPos, _: *GameState) !MysteryBox {
    inline for (prefabs, 0..) |MysteryBoxPrefab, i| {
        if (i == index) {
            return MysteryBoxPrefab.init(pos);
        }
    }
    return Scene.SpawnError.NoSuchItem;
}

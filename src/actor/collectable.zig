const Actor = @import("actor.zig");
const Collectable = @This();
const Player = @import("player.zig");
const RigidBody = @import("rigid_body.zig");
const Scene = @import("../scene.zig");
const Sprite = @import("../sprite.zig");
const Solid = @import("../solid/solid.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");
const shapes = @import("../shapes.zig");
const types = @import("../types.zig");

const approach = helpers.approach;

onCollected: *const fn (self: *Collectable, player: *Player) void,

collectable_type: u8,
rigid_body: RigidBody,
initial_hitbox: rl.Rectangle,
sprite: Sprite,
sprite_offset: rl.Vector2,
is_collected: bool = false,
is_deleted: bool = false,
speed: rl.Vector2 = .{ .x = 0, .y = 0 },
sound: rl.Sound,

const fall_speed: f32 = 3.6 * 60;

pub fn stub() Collectable {
    return .{
        .collectable_type = undefined,
        .rigid_body = undefined,
        .initial_hitbox = undefined,
        .sound = undefined,
        .sprite = undefined,
        .sprite_offset = undefined,
        .onCollected = undefined,
        .is_collected = false,
        .is_deleted = true,
    };
}

pub fn Prefab(
    collectable_type: u8,
    hitbox: rl.Rectangle,
    sprite_offset: rl.Vector2,
    SpritePrefab: anytype,
    loadSound: *const fn () rl.Sound,
    onCollected: *const fn (self: *Collectable, player: *Player) void,
) type {
    return struct {
        pub const Sprite = SpritePrefab;
        pub const Hitbox = hitbox;
        pub const spr_offset = sprite_offset;
        pub const _loadSound = loadSound;

        pub fn init(pos: shapes.IPos) Collectable {
            const sprite = SpritePrefab.init();

            var collectable_hitbox = hitbox;
            collectable_hitbox.x = @floatFromInt(pos.x);
            collectable_hitbox.y = @floatFromInt(pos.y);

            const sound = loadSound();

            return Collectable.init(
                collectable_type,
                collectable_hitbox,
                sprite,
                sprite_offset,
                sound,
                onCollected,
            );
        }
    };
}

pub fn init(
    collectable_type: u8,
    hitbox: rl.Rectangle,
    sprite: Sprite,
    sprite_offset: rl.Vector2,
    sound: rl.Sound,
    onCollected: *const fn (
        self: *Collectable,
        player: *Player,
    ) void,
) Collectable {
    var rigid_body = RigidBody.init(hitbox);
    rigid_body.mode = .Static;

    return .{
        .collectable_type = collectable_type,
        .initial_hitbox = hitbox,
        .rigid_body = rigid_body,
        .sound = sound,
        .sprite = sprite,
        .sprite_offset = sprite_offset,
        .onCollected = onCollected,
    };
}

pub fn actor(self: *Collectable) Actor {
    return .{ .ptr = self, .impl = &.{
        .getRigidBody = getRigidBodyCast,
        .getHitboxRect = getHitboxRectCast,
        .getGridRect = getGridRectCast,
        .isHostile = isHostile,
        .setPos = setPosCast,
    } };
}

pub fn reset(self: *Collectable) void {
    if (self.is_deleted) {
        return;
    }

    self.* = Collectable.init(self.collectable_type, self.initial_hitbox, self.sprite, self.sprite_offset, self.sound, self.onCollected);
    self.sprite.reset();
}

fn getRigidBodyCast(ctx: *anyopaque) *RigidBody {
    const self: *Collectable = @ptrCast(@alignCast(ctx));
    return self.getRigidBody();
}

fn getGridRectCast(ctx: *const anyopaque) shapes.IRect {
    const self: *const Collectable = @ptrCast(@alignCast(ctx));
    return self.getGridRect();
}

fn getHitboxRectCast(ctx: *const anyopaque) rl.Rectangle {
    const self: *const Collectable = @ptrCast(@alignCast(ctx));
    return self.getHitboxRect();
}

fn setPosCast(ctx: *anyopaque, pos: rl.Vector2) void {
    const self: *Collectable = @ptrCast(@alignCast(ctx));
    self.setPos(pos);
}

fn isHostile() bool {
    return false;
}

pub inline fn getRigidBody(self: *Collectable) *RigidBody {
    return &self.rigid_body;
}

pub inline fn getGridRect(self: *const Collectable) shapes.IRect {
    return self.rigid_body.grid_rect;
}

pub inline fn getHitboxRect(self: *const Collectable) rl.Rectangle {
    return self.rigid_body.hitbox;
}

pub inline fn getInitialPos(self: *const Collectable) rl.Vector2 {
    return .{
        .x = self.initial_hitbox.x,
        .y = self.initial_hitbox.y,
    };
}

pub inline fn setPos(self: *Collectable, pos: rl.Vector2) void {
    self.rigid_body.hitbox.x = pos.x;
    self.rigid_body.hitbox.y = pos.y;
}

pub fn delete(self: *Collectable) void {
    self.is_deleted = true;
}

pub fn handleCollision(self: *Collectable, scene: *Scene, axis: types.Axis, sign: i8, flags: u8, _: ?Solid) void {
    _ = scene; // autofix
    _ = flags; // autofix
    if (self.is_collected or self.is_deleted) {
        return;
    }

    if (axis == types.Axis.Y) {
        if (sign == 1) {
            // Bounce!
            if (self.speed.y > 60) {
                self.speed.y *= -0.8;
            } else {
                self.speed.y = 0;
            }
        } else {
            self.speed.y = 0;
        }
    }
}

pub fn update(self: *Collectable, scene: *Scene, delta_time: f32) !void {
    if (self.is_collected or self.is_deleted) {
        return;
    }

    if (rl.checkCollisionRecs(scene.player.actor().getHitboxRect(), self.rigid_body.hitbox)) {
        self.is_collected = true;
        rl.playSound(self.sound);
        self.onCollected(self, scene.player);
    }

    // Apply forces if rigid_body is rigid
    if (self.rigid_body.mode == .Rigid) {
        self.speed.y = approach(self.speed.y, fall_speed, scene.gravity * delta_time);

        if (self.speed.x != 0) {
            self.rigid_body.move(scene, types.Axis.X, self.speed.x * delta_time, self);
        }
        if (self.speed.y != 0) {
            self.rigid_body.move(scene, types.Axis.Y, self.speed.y * delta_time, self);
        }
    }

    try self.sprite.update(scene, delta_time);
}

pub fn draw(self: *const Collectable, scene: *const Scene) void {
    if (self.is_collected or self.is_deleted) {
        return;
    }
    const sprite_pos = helpers.getRelativePos(self.sprite_offset, self.rigid_body.hitbox);
    self.sprite.draw(scene, sprite_pos, rl.Color.white);
}

pub const Coin = @import("collectables/coin.zig").Coin;
pub const HealthGrape = @import("collectables/fruit.zig").HealthGrape;

pub const prefabs: [2]type = .{
    Coin,
    HealthGrape,
};

pub fn initCollectableByIndex(index: usize, pos: rl.Vector2) !Collectable {
    inline for (prefabs, 0..) |CollectablePrefab, i| {
        if (i == index) {
            return CollectablePrefab.init(shapes.IPos.fromVec2(pos));
        }
    }
    return Scene.SpawnError.NoSuchItem;
}

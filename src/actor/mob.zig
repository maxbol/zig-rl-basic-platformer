const Actor = @import("actor.zig");
const CollidableBody = @import("collidable_body.zig");
const Entity = @import("../entity.zig");
const Mob = @This();
const Scene = @import("../scene.zig");
const Sprite = @import("../sprite.zig");
const an = @import("../animation.zig");
const globals = @import("../globals.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");
const std = @import("std");
const shapes = @import("../shapes.zig");

const approach = helpers.approach;

collidable: CollidableBody,
sprite: Sprite,
sprite_offset: rl.Vector2,
speed: rl.Vector2,
is_hunting: bool = false,
is_jumping: bool = false,
did_huntjump: bool = false,
next_huntjump_distance: f32 = 80,
behavior: MobBehavior,

pub const MobBehavior = struct {
    walk_speed: f32 = 1 * 60,
    fall_speed: f32 = 3.6 * 60,
    hunt_speed: f32 = 2 * 60,
    jump_speed: f32 = -4 * 60,
    hunt_acceleration: f32 = 10 * 60,
    line_of_sight: i32 = 10, // See 10 tiles ahead
};

pub fn Prefab(
    hitbox: rl.Rectangle,
    sprite_offset: rl.Vector2,
    behavior: MobBehavior,
    SpritePrefab: anytype,
) type {
    return struct {
        pub const Sprite = SpritePrefab;

        pub fn init() Mob {
            const sprite = SpritePrefab.init();
            return Mob.init(hitbox, sprite, sprite_offset, behavior);
        }
    };
}

pub fn init(hitbox: rl.Rectangle, sprite: Sprite, sprite_offset: rl.Vector2, mob_attributes: MobBehavior) Mob {
    var mob = Mob{
        .speed = rl.Vector2.init(0, 0),
        .sprite = sprite,
        .sprite_offset = sprite_offset,
        .collidable = CollidableBody.init(hitbox),
        .behavior = mob_attributes,
    };

    mob.randomlyAcquireNextHuntjumpDistance();

    return mob;
}

pub fn handleCollision(self: *Mob, axis: CollidableBody.MoveAxis, sign: i8) void {
    if (axis == CollidableBody.MoveAxis.X) {
        // Reverse direction when hitting an obstacle (unless we are hunting the player)
        if (!self.is_hunting) {
            self.speed.x = -@as(f32, @floatFromInt(sign)) * self.behavior.walk_speed;
        }
    } else {
        if (sign == 1) {
            // Stop falling when hitting the ground
            self.is_jumping = false;
        }
        self.speed.y = 0;
    }
}

pub fn getGridRect(self: *const Mob) shapes.IRect {
    return self.collidable.grid_rect;
}

pub fn getHitboxRect(self: *const Mob) rl.Rectangle {
    return self.collidable.hitbox;
}

fn move(self: *Mob, scene: *const Scene, comptime axis: CollidableBody.MoveAxis, amount: f32) void {
    self.collidable.move(scene, axis, amount, self);
}

inline fn detectOnNextTile(lookahead: i32, sign: i8, mob_gridbox: shapes.IRect, player_gridbox: shapes.IRect) bool {
    const next_x = mob_gridbox.x + (sign * lookahead);
    const next_y = mob_gridbox.y;
    const next_gridbox = shapes.IRect.init(next_x, next_y, mob_gridbox.width, mob_gridbox.height);
    return player_gridbox.isColliding(next_gridbox);
}

fn detectNearbyPlayer(self: *Mob, scene: *Scene, delta_time: f32) void {
    const player_gridbox = scene.player.getGridRect();
    const mob_gridbox = getGridRect(self);
    var lookahead = self.behavior.line_of_sight;
    var is_hunting = false;

    while (lookahead > 0) : (lookahead -= 1) {
        if (detectOnNextTile(lookahead, 1, mob_gridbox, player_gridbox)) {
            is_hunting = true;
            self.speed.x = approach(self.speed.x, self.behavior.hunt_speed, self.behavior.hunt_acceleration * delta_time);
            break;
        }
        if (detectOnNextTile(lookahead, -1, mob_gridbox, player_gridbox)) {
            is_hunting = true;
            self.speed.x = approach(self.speed.x, -self.behavior.hunt_speed, self.behavior.hunt_acceleration * delta_time);
            break;
        }
    }
    self.is_hunting = is_hunting;
}

fn randomlyAcquireNextHuntjumpDistance(self: *Mob) void {
    self.next_huntjump_distance = @floatFromInt(globals.rand.intRangeAtMostBiased(u8, 80, 160));
}

pub fn setPos(self: *Mob, pos: rl.Vector2) void {
    self.collidable.hitbox.x = pos.x;
    self.collidable.hitbox.y = pos.y;
}

pub fn update(self: *Mob, scene: *Scene, delta_time: f32) Entity.UpdateError!void {
    // Start walking if standing still
    if (self.speed.x == 0) {
        self.speed.x = self.behavior.walk_speed;
    }

    // Try to spot the player by raycasting
    self.detectNearbyPlayer(scene, delta_time);

    // Hunt jumping
    if (!self.is_jumping) {
        if (!self.is_hunting and self.did_huntjump) {
            self.did_huntjump = false;
        }
        if (self.is_hunting and !self.did_huntjump) {
            const player_hitbox = scene.player.getHitboxRect();
            const mob_hitbox = getHitboxRect(self);

            if (@abs(player_hitbox.x - mob_hitbox.x) < self.next_huntjump_distance) {
                self.speed.y = self.behavior.jump_speed;
                self.is_jumping = true;
                self.did_huntjump = true;
                self.randomlyAcquireNextHuntjumpDistance();
            }
        }
    }

    // Slow down when hunt is over
    if (!self.is_hunting) {
        self.speed.x = std.math.sign(self.speed.x) * self.behavior.walk_speed;
    }

    // Gravity
    self.speed.y = approach(self.speed.y, self.behavior.fall_speed, scene.gravity * delta_time);

    // Set animation and flip sprite
    if (self.is_hunting) {
        self.sprite.setAnimation(.Attack, null, false);
    } else {
        self.sprite.setAnimation(.Walk, null, false);
    }

    if (self.speed.x > 0) {
        self.sprite.setFlip(Sprite.FlipState.XFlip, false);
    } else if (self.speed.x < 0) {
        self.sprite.setFlip(Sprite.FlipState.XFlip, true);
    }

    // Move the mob
    self.move(scene, CollidableBody.MoveAxis.X, self.speed.x * delta_time);
    self.move(scene, CollidableBody.MoveAxis.Y, self.speed.y * delta_time);

    try self.sprite.update(scene, delta_time);
}

pub fn draw(self: *const Mob, scene: *const Scene) void {
    const sprite_pos = helpers.getRelativePos(self.sprite_offset, self.collidable.hitbox);
    self.sprite.draw(scene, sprite_pos, rl.Color.white);
}

pub fn drawDebug(self: *const Mob, scene: *const Scene) void {
    const sprite_pos = helpers.getRelativePos(self.sprite_offset, self.collidable.hitbox);

    self.sprite.drawDebug(scene, sprite_pos);
    self.collidable.drawDebug(scene);
}

pub const GreenSlime = @import("mob/slime.zig").GreenSlime;

pub const bestiary: [1]type = .{
    GreenSlime,
};
pub fn initMobByIndex(index: usize) !Mob {
    inline for (bestiary, 0..) |MobPrefab, i| {
        if (i == index) {
            return MobPrefab.init();
        }
    }
    return error.NoSuchMob;
}

pub inline fn getBiggestMobSpriteSize() f32 {
    var max: f32 = 0;
    inline for (bestiary, 0..) |MobPrefab, i| {
        _ = i; // autofix
        const SpritePrefab = MobPrefab.Sprite;
        const biggest_size_dim = @max(SpritePrefab.SIZE_X, SpritePrefab.SIZE_Y);
        max = @max(max, biggest_size_dim);
    }
    return max;
}

const Actor = @import("actor.zig");
const CollidableBody = @import("collidable_body.zig");
const Entity = @import("../entity.zig");
const Mob = @This();
const Scene = @import("../scene.zig");
const Sprite = @import("../sprite.zig");
const Tileset = @import("../tileset/tileset.zig");
const an = @import("../animation.zig");
const globals = @import("../globals.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");
const std = @import("std");
const shapes = @import("../shapes.zig");
const types = @import("../types.zig");

const approach = helpers.approach;

initial_hitbox: rl.Rectangle,
collidable: CollidableBody,
sprite: Sprite,
sprite_offset: rl.Vector2,
speed: rl.Vector2,
is_hunting: bool = false,
is_jumping: bool = false,
did_huntjump: bool = false,
next_huntjump_distance: f32 = 80,
behavior: MobBehavior,

is_deleted: bool = false,
is_dead: bool = false,

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
        pub const Hitbox = hitbox;
        pub const spr_offset = sprite_offset;

        pub fn init(pos: rl.Vector2) Mob {
            const sprite = SpritePrefab.init();

            var mob_hitbox = hitbox;
            mob_hitbox.x = pos.x;
            mob_hitbox.y = pos.y;

            return Mob.init(mob_hitbox, sprite, sprite_offset, behavior);
        }
    };
}

pub fn init(hitbox: rl.Rectangle, sprite: Sprite, sprite_offset: rl.Vector2, mob_attributes: MobBehavior) Mob {
    var mob = Mob{
        .initial_hitbox = hitbox,
        .speed = rl.Vector2.init(0, 0),
        .sprite = sprite,
        .sprite_offset = sprite_offset,
        .collidable = CollidableBody.init(hitbox),
        .behavior = mob_attributes,
    };

    mob.randomlyAcquireNextHuntjumpDistance();

    return mob;
}

pub fn actor(self: *Mob) Actor {
    return .{ .ptr = self, .impl = &.{
        .getCollidableBody = getCollidableBodyCast,
        .getHitboxRect = getHitboxRectCast,
        .getGridRect = getGridRectCast,
        .setPos = setPosCast,
        .squish = handleSquish,
    } };
}

fn getCollidableBodyCast(ctx: *const anyopaque) CollidableBody {
    const self: *const Mob = @ptrCast(@alignCast(ctx));
    return self.getCollidableBody();
}

fn getGridRectCast(ctx: *const anyopaque) shapes.IRect {
    const self: *const Mob = @ptrCast(@alignCast(ctx));
    return self.getGridRect();
}

fn getHitboxRectCast(ctx: *const anyopaque) rl.Rectangle {
    const self: *const Mob = @ptrCast(@alignCast(ctx));
    return self.getHitboxRect();
}

fn setPosCast(ctx: *anyopaque, pos: rl.Vector2) void {
    const self: *Mob = @ptrCast(@alignCast(ctx));
    self.setPos(pos);
}

pub fn reset(self: *Mob) void {
    if (self.is_deleted) {
        return;
    }

    self.* = Mob.init(self.initial_hitbox, self.sprite, self.sprite_offset, self.behavior);
    self.sprite.reset();
}

fn handleSquish(_: *anyopaque, _: types.Axis, _: i8, _: u8) void {
    // TODO 07/09/2024: Implement squish
}

pub fn handleCollision(self: *Mob, axis: types.Axis, sign: i8, _: u8) void {
    if (axis == types.Axis.X) {
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

pub inline fn getCollidableBody(self: *const Mob) CollidableBody {
    return self.collidable;
}

pub inline fn getGridRect(self: *const Mob) shapes.IRect {
    return self.collidable.grid_rect;
}

pub inline fn getHitboxRect(self: *const Mob) rl.Rectangle {
    return self.collidable.hitbox;
}

pub fn getInitialPos(self: *const Mob) rl.Vector2 {
    return .{
        .x = self.initial_hitbox.x,
        .y = self.initial_hitbox.y,
    };
}

fn move(self: *Mob, scene: *Scene, comptime axis: types.Axis, amount: f32) void {
    self.collidable.move(scene, axis, amount, self);
}

fn detectGapOnNextTile(self: *Mob, scene: *Scene, _: f32) bool {
    const hitbox = self.getHitboxRect();
    const sign = std.math.sign(self.speed.x);
    const next_x = hitbox.x + (hitbox.width * sign);
    const next_y = hitbox.y + 1;
    const next = shapes.IRect.fromRect(rl.Rectangle.init(next_x, next_y, hitbox.width, hitbox.height));
    const grid_rect = helpers.getGridRect(
        shapes.IPos.fromVec2(scene.main_layer.getTileset().getTileSize()),
        next,
    );
    const collision_flags = scene.collideAt(next, grid_rect);
    if (collision_flags) |flags| {
        return flags & @intFromEnum(Tileset.TileFlag.Collidable) == 0;
    }
    return true;
}

inline fn detectPlayerOnNextTile(lookahead: i32, sign: i8, mob_gridbox: shapes.IRect, player_gridbox: shapes.IRect) bool {
    const next_x = mob_gridbox.x + (sign * lookahead);
    const next_y = mob_gridbox.y;
    const next_gridbox = shapes.IRect.init(next_x, next_y, mob_gridbox.width, mob_gridbox.height);
    return player_gridbox.isColliding(next_gridbox);
}

fn detectNearbyPlayer(self: *Mob, scene: *Scene, delta_time: f32) void {
    const player_gridbox = scene.player.actor().getGridRect();
    const mob_gridbox = getGridRect(self);
    var lookahead = self.behavior.line_of_sight;
    var is_hunting = false;

    while (lookahead > 0) : (lookahead -= 1) {
        if (detectPlayerOnNextTile(lookahead, 1, mob_gridbox, player_gridbox)) {
            is_hunting = true;
            self.speed.x = approach(self.speed.x, self.behavior.hunt_speed, self.behavior.hunt_acceleration * delta_time);
            break;
        }
        if (detectPlayerOnNextTile(lookahead, -1, mob_gridbox, player_gridbox)) {
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

pub inline fn setPos(self: *Mob, pos: rl.Vector2) void {
    self.collidable.hitbox.x = pos.x;
    self.collidable.hitbox.y = pos.y;
}

pub fn delete(self: *Mob) void {
    self.is_deleted = true;
}

pub fn kill(self: *Mob) void {
    self.is_dead = true;
}

pub fn update(self: *Mob, scene: *Scene, delta_time: f32) Entity.UpdateError!void {
    if (self.is_deleted or self.is_dead) {
        return;
    }

    // Start walking if standing still
    if (self.speed.x == 0) {
        self.speed.x = self.behavior.walk_speed;
    }

    // Try to spot the player by raycasting
    self.detectNearbyPlayer(scene, delta_time);

    // Reverse direction to avoid walking down gaps if not hunting
    if (!self.is_jumping and !self.is_hunting and self.detectGapOnNextTile(scene, delta_time)) {
        self.speed.x = -self.speed.x;
    }

    // Hunt jumping
    if (!self.is_jumping) {
        if (!self.is_hunting and self.did_huntjump) {
            self.did_huntjump = false;
        }
        if (self.is_hunting and !self.did_huntjump) {
            const player_hitbox = scene.player.actor().getHitboxRect();
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
        self.sprite.setAnimation(.{ .animation = .Attack });
    } else {
        self.sprite.setAnimation(.{ .animation = .Walk });
    }

    if (self.speed.x > 0) {
        self.sprite.setFlip(Sprite.FlipState.XFlip, false);
    } else if (self.speed.x < 0) {
        self.sprite.setFlip(Sprite.FlipState.XFlip, true);
    }

    // Move the mob
    self.move(scene, types.Axis.X, self.speed.x * delta_time);
    self.move(scene, types.Axis.Y, self.speed.y * delta_time);

    try self.sprite.update(scene, delta_time);
}

pub fn draw(self: *const Mob, scene: *const Scene) void {
    if (self.is_deleted or self.is_dead) {
        return;
    }
    const sprite_pos = helpers.getRelativePos(self.sprite_offset, self.collidable.hitbox);
    self.sprite.draw(scene, sprite_pos, rl.Color.white);
}

pub fn drawDebug(self: *const Mob, scene: *const Scene) void {
    if (self.is_deleted or self.is_dead) {
        return;
    }
    const sprite_pos = helpers.getRelativePos(self.sprite_offset, self.collidable.hitbox);

    self.sprite.drawDebug(scene, sprite_pos);
    self.collidable.drawDebug(scene);
}

pub const GreenSlime = @import("mob/slime.zig").GreenSlime;

pub const prefabs: [1]type = .{
    GreenSlime,
};
pub fn initMobByIndex(index: usize, pos: rl.Vector2) Scene.SpawnError!Mob {
    inline for (prefabs, 0..) |MobPrefab, i| {
        if (i == index) {
            return MobPrefab.init(pos);
        }
    }
    return Scene.SpawnError.NoSuchItem;
}

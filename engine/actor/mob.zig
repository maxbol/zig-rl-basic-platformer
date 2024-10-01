const Actor = @import("actor.zig");
const GameState = @import("../gamestate.zig");
const Mob = @This();
const RigidBody = @import("rigid_body.zig");
const Scene = @import("../scene.zig");
const Solid = @import("../solid/solid.zig");
const Sprite = @import("../sprite.zig");
const Tileset = @import("../tileset/tileset.zig");
const an = @import("../animation.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");
const shapes = @import("../shapes.zig");
const std = @import("std");
const types = @import("../types.zig");

const approach = helpers.approach;

pub const AnimationType = enum(u8) {
    Walk,
    Attack,
    Hit,
};

pub const RespawnFn = *const fn (pos: shapes.IPos) Mob;

behavior: *const MobBehavior,
did_huntjump: bool = false,
initial_hitbox: rl.Rectangle,
is_hunting: bool = false,
is_jumping: bool = false,
mob_type: u8,
next_huntjump_distance: f32 = 80,
respawn: RespawnFn,
rigid_body: RigidBody,
speed: rl.Vector2,
sprite: an.Sprite,
sprite_offset: rl.Vector2,

is_deleted: bool = false,
is_dead: bool = false,

pub const MobBehavior = struct {
    walk_speed: f32,
    fall_speed: f32,
    hunt_speed: f32,
    jump_speed: f32,
    hunt_acceleration: f32,
    line_of_sight: i32, // See 10 tiles ahead
};

pub fn Prefab(
    mob_type: u8,
    hitbox: rl.Rectangle,
    sprite_offset: rl.Vector2,
    behavior: *const MobBehavior,
    getSpriteReader: *const fn () an.AnySpriteBuffer,
) type {
    return struct {
        pub const Hitbox = hitbox;
        pub const sprite_reader = getSpriteReader;
        pub const spr_offset = sprite_offset;

        pub fn init(pos: shapes.IPos) Mob {
            const sprite = sprite_reader().sprite() catch @panic("Failed to read sprite");
            var mob_hitbox = hitbox;
            mob_hitbox.x = @floatFromInt(pos.x);
            mob_hitbox.y = @floatFromInt(pos.y);

            return Mob.init(
                mob_type,
                mob_hitbox,
                sprite,
                sprite_offset,
                behavior,
                @This().init,
            );
        }
    };
}

pub fn init(
    mob_type: u8,
    hitbox: rl.Rectangle,
    sprite: an.Sprite,
    sprite_offset: rl.Vector2,
    behavior: *const MobBehavior,
    respawn: RespawnFn,
) Mob {
    return .{
        .mob_type = mob_type,
        .initial_hitbox = hitbox,
        .speed = rl.Vector2.init(0, 0),
        .sprite = sprite,
        .sprite_offset = sprite_offset,
        .rigid_body = RigidBody.init(hitbox),
        .behavior = behavior,
        .respawn = respawn,
    };

    // mob.randomlyAcquireNextHuntjumpDistance();

    // return mob;
}

pub fn actor(self: *Mob) Actor {
    return .{ .ptr = self, .impl = &.{
        .getRigidBody = getRigidBodyCast,
        .getHitboxRect = getHitboxRectCast,
        .getGridRect = getGridRectCast,
        .isHostile = isHostile,
        .setPos = setPosCast,
    } };
}

fn getRigidBodyCast(ctx: *anyopaque) *RigidBody {
    const self: *Mob = @ptrCast(@alignCast(ctx));
    return self.getRigidBody();
}

fn getGridRectCast(ctx: *const anyopaque) shapes.IRect {
    const self: *const Mob = @ptrCast(@alignCast(ctx));
    return self.getGridRect();
}

fn getHitboxRectCast(ctx: *const anyopaque) rl.Rectangle {
    const self: *const Mob = @ptrCast(@alignCast(ctx));
    return self.getHitboxRect();
}

fn isHostile() bool {
    return true;
}

fn setPosCast(ctx: *anyopaque, pos: rl.Vector2) void {
    const self: *Mob = @ptrCast(@alignCast(ctx));
    self.setPos(pos);
}

pub fn reset(self: *Mob) !void {
    if (self.is_deleted) {
        return;
    }

    self.* = Mob.init(self.mob_type, self.initial_hitbox, self.sprite, self.sprite_offset, self.behavior, self.respawn);
    try self.sprite.reset();
}

pub fn hotReload(self: *Mob) void {
    if (self.is_deleted) {
        return;
    }

    const is_dead = self.is_dead;

    self.* = self.respawn(.{
        .x = @intFromFloat(self.rigid_body.hitbox.x),
        .y = @intFromFloat(self.rigid_body.hitbox.y),
    });
    self.is_dead = is_dead;
}

pub fn handleCollision(self: *Mob, scene: *Scene, axis: types.Axis, sign: i8, flags: u8, _: ?Solid) void {
    const deadly_fall = flags & @intFromEnum(Tileset.TileFlag.Deadly) != 0;
    if (axis == types.Axis.X) {
        // Reverse direction when hitting an obstacle (unless we are hunting the player)
        if (!self.is_hunting) {
            self.speed.x = -@as(f32, @floatFromInt(sign)) * self.behavior.walk_speed;
        }
    } else {
        if (sign == 1) {
            // Stop falling when hitting the ground
            self.is_jumping = false;
            if (deadly_fall) {
                self.die(scene);
            }
        }
        self.speed.y = 0;
    }
}

pub fn die(self: *Mob, scene: *Scene) void {
    _ = scene; // autofix
    self.is_dead = true;
}

pub inline fn getRigidBody(self: *Mob) *RigidBody {
    return &self.rigid_body;
}

pub inline fn getGridRect(self: *const Mob) shapes.IRect {
    return self.rigid_body.grid_rect;
}

pub inline fn getHitboxRect(self: *const Mob) rl.Rectangle {
    return self.rigid_body.hitbox;
}

pub fn getInitialPos(self: *const Mob) rl.Vector2 {
    return .{
        .x = self.initial_hitbox.x,
        .y = self.initial_hitbox.y,
    };
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
    const collision = scene.collideAt(next, grid_rect);
    if (collision) |c| {
        return c.flags & @intFromEnum(Tileset.TileFlag.Collidable) == 0;
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
    const player_gridbox = scene.gamestate.player.actor().getGridRect();
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

fn randomlyAcquireNextHuntjumpDistance(self: *Mob, scene: *const Scene) void {
    self.next_huntjump_distance = @floatFromInt(scene.gamestate.rand.random().intRangeAtMostBiased(u8, 80, 160));
}

pub inline fn setPos(self: *Mob, pos: rl.Vector2) void {
    self.rigid_body.hitbox.x = pos.x;
    self.rigid_body.hitbox.y = pos.y;
}

pub fn delete(self: *Mob) void {
    self.is_deleted = true;
}

pub fn kill(self: *Mob) void {
    self.is_dead = true;
}

pub fn update(self: *Mob, scene: *Scene, delta_time: f32) !void {
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
            const player_hitbox = scene.gamestate.player.actor().getHitboxRect();
            const mob_hitbox = getHitboxRect(self);

            if (@abs(player_hitbox.x - mob_hitbox.x) < self.next_huntjump_distance) {
                self.speed.y = self.behavior.jump_speed;
                self.is_jumping = true;
                self.did_huntjump = true;
                self.randomlyAcquireNextHuntjumpDistance(scene);
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
        self.sprite.setAnimation(AnimationType.Attack, .{});
    } else {
        self.sprite.setAnimation(AnimationType.Walk, .{});
    }

    if (self.speed.x > 0) {
        self.sprite.flip_mask.x = false;
    } else if (self.speed.x < 0) {
        self.sprite.flip_mask.x = true;
    }

    // Move the mob
    self.rigid_body.move(scene, types.Axis.X, self.speed.x * delta_time, self);
    self.rigid_body.move(scene, types.Axis.Y, self.speed.y * delta_time, self);

    self.sprite.update(delta_time);
}

pub fn draw(self: *const Mob, scene: *const Scene) void {
    if (self.is_deleted or self.is_dead) {
        return;
    }
    const sprite_pos = an.DrawPosition.init(self.rigid_body.hitbox, .TopLeft, self.sprite_offset);
    self.sprite.draw(scene, sprite_pos, rl.Color.white);
}

pub fn drawDebug(self: *const Mob, scene: *const Scene) void {
    if (self.is_deleted or self.is_dead) {
        return;
    }
    const sprite_pos = an.DrawPosition.init(self.rigid_body.hitbox, .TopLeft, self.sprite_offset);

    self.sprite.drawDebug(scene, sprite_pos);
    self.rigid_body.drawDebug(scene);
}

pub const GreenSlime = @import("mob/slime.zig").GreenSlime;

pub const prefabs: [1]type = .{
    GreenSlime,
};
pub fn initMobByIndex(index: usize, pos: rl.Vector2) Scene.SpawnError!Mob {
    inline for (prefabs, 0..) |MobPrefab, i| {
        if (i == index) {
            return MobPrefab.init(shapes.IPos.fromVec2(pos));
        }
    }
    return Scene.SpawnError.NoSuchItem;
}

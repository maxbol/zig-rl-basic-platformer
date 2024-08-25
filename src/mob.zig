const Actor = @import("actor.zig");
const CollidableBody = @import("collidable_body.zig");
const Entity = @import("entity.zig");
const Mob = @This();
const Scene = @import("scene.zig");
const Sprite = @import("sprite.zig");
const an = @import("animation.zig");
const helpers = @import("helpers.zig");
const rl = @import("raylib");
const std = @import("std");
const tl = @import("tiles.zig");
const shapes = @import("shapes.zig");

const approach = helpers.approach;

collidable: CollidableBody,
sprite: Sprite,
sprite_offset: rl.Vector2,
speed: rl.Vector2,
is_hunting: bool = false,
is_jumping: bool = false,
did_huntjump: bool = false,

const walk_speed: f32 = 1 * 60;
const fall_speed: f32 = 3.6 * 60;
const hunt_speed: f32 = 2 * 60;
const jump_speed: f32 = -4 * 60;
const hunt_acceleration: f32 = 10 * 60;
const line_of_sight: i32 = 10; // See 10 tiles ahead

pub fn init(hitbox: rl.Rectangle, sprite: Sprite, sprite_offset: rl.Vector2) Mob {
    return .{
        .speed = rl.Vector2.init(0, 0),
        .sprite = sprite,
        .sprite_offset = sprite_offset,
        .collidable = CollidableBody.init(hitbox),
    };
}

pub fn actor(self: *Mob) Actor {
    return .{ .ptr = self, .impl = &.{
        .entity = entityCast,
        .getHitboxRect = getHitboxRect,
        .getGridRect = getGridRect,
    } };
}

pub fn entity(self: *Mob) Entity {
    return .{
        .ptr = self,
        .impl = &.{
            .update = update,
            .draw = draw,
            .drawDebug = drawDebug,
        },
    };
}

pub fn handleCollision(self: *Mob, axis: CollidableBody.MoveAxis, sign: i8) void {
    if (axis == CollidableBody.MoveAxis.X) {
        // Reverse direction when hitting an obstacle (unless we are hunting the player)
        if (!self.is_hunting) {
            self.speed.x = -@as(f32, @floatFromInt(sign)) * walk_speed;
        }
    } else {
        if (sign == 1) {
            // Stop falling when hitting the ground
            self.is_jumping = false;
        }
        self.speed.y = 0;
    }
}

fn getGridRect(ctx: *anyopaque) shapes.IRect {
    const self: *Mob = @ptrCast(@alignCast(ctx));
    return self.collidable.grid_rect;
}

fn getHitboxRect(ctx: *anyopaque) rl.Rectangle {
    const self: *Mob = @ptrCast(@alignCast(ctx));
    return self.collidable.hitbox;
}

fn entityCast(ctx: *anyopaque) Entity {
    const self: *Mob = @ptrCast(@alignCast(ctx));
    return self.entity();
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
    const player_gridbox = scene.getPlayer().getGridRect();
    const mob_gridbox = getGridRect(self);
    var lookahead = line_of_sight;
    var is_hunting = false;

    while (lookahead > 0) : (lookahead -= 1) {
        if (detectOnNextTile(lookahead, 1, mob_gridbox, player_gridbox)) {
            is_hunting = true;
            self.speed.x = approach(self.speed.x, hunt_speed, hunt_acceleration * delta_time);
            break;
        }
        if (detectOnNextTile(lookahead, -1, mob_gridbox, player_gridbox)) {
            is_hunting = true;
            self.speed.x = approach(self.speed.x, -hunt_speed, hunt_acceleration * delta_time);
            break;
        }
    }
    self.is_hunting = is_hunting;
}

fn update(ctx: *anyopaque, scene: *Scene, delta_time: f32) Entity.EntityUpdateError!void {
    const self: *Mob = @ptrCast(@alignCast(ctx));

    // Start walking if standing still
    if (self.speed.x == 0) {
        self.speed.x = walk_speed;
    }

    // Try to spot the player by raycasting
    self.detectNearbyPlayer(scene, delta_time);

    // Hunt jumping
    if (!self.is_hunting and self.did_huntjump and !self.is_jumping) {
        self.did_huntjump = false;
    }
    if (self.is_hunting and !self.did_huntjump and !self.is_jumping) {
        const player_hitbox = scene.getPlayer().getHitboxRect();
        const mob_hitbox = getHitboxRect(ctx);

        if (@abs(player_hitbox.x - mob_hitbox.x) < 80) {
            self.speed.y = jump_speed;
            self.is_jumping = true;
            self.did_huntjump = true;
        }
    }

    // Slow down when hunt is over
    if (!self.is_hunting) {
        self.speed.x = std.math.sign(self.speed.x) * walk_speed;
    }

    // Gravity
    self.speed.y = approach(self.speed.y, fall_speed, scene.gravity * delta_time);

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

fn draw(ctx: *anyopaque, scene: *const Scene) void {
    const self: *Mob = @ptrCast(@alignCast(ctx));
    const sprite_pos = helpers.getRelativePos(self.sprite_offset, self.collidable.hitbox);

    self.sprite.draw(scene, sprite_pos);
}

fn drawDebug(ctx: *anyopaque, scene: *const Scene) void {
    const self: *Mob = @ptrCast(@alignCast(ctx));
    const sprite_pos = helpers.getRelativePos(self.sprite_offset, self.collidable.hitbox);

    self.sprite.drawDebug(scene, sprite_pos);
    self.collidable.drawDebug(scene);
}

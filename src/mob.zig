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

const walk_speed: f32 = 1 * 60;
const fall_speed: f32 = 3.6 * 60;

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
        // Reverse direction when hitting an obstacle
        std.debug.print("reversing direction of mob sign={d}\n", .{sign});
        self.speed.x = -@as(f32, @floatFromInt(sign)) * walk_speed;
    } else {
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

fn move(self: *Mob, comptime axis: CollidableBody.MoveAxis, layer: tl.TileLayer, amount: f32) void {
    self.collidable.move(axis, layer, amount, self);
}

fn update(ctx: *anyopaque, scene: *Scene, delta_time: f32) Entity.EntityUpdateError!void {
    const self: *Mob = @ptrCast(@alignCast(ctx));

    // Start walking if standing still
    if (self.speed.x == 0) {
        self.speed.x = walk_speed;
    }

    // Try to spot the player by raycasting
    const player_hitbox = scene.getPlayer().getHitboxRect();
    _ = player_hitbox; // autofix

    // Gravity
    self.speed.y = approach(self.speed.y, fall_speed, scene.gravity * delta_time);

    // Set animation and flip sprite
    if (self.speed.x > 0) {
        self.sprite.setAnimation(.Walk, null, false);
        self.sprite.setFlip(Sprite.FlipState.XFlip, false);
    } else if (self.speed.x < 0) {
        self.sprite.setAnimation(.Walk, null, false);
        self.sprite.setFlip(Sprite.FlipState.XFlip, true);
    }

    // Move the mob
    self.move(CollidableBody.MoveAxis.X, scene.main_layer, self.speed.x * delta_time);
    self.move(CollidableBody.MoveAxis.Y, scene.main_layer, self.speed.y * delta_time);

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

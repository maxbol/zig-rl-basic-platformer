const Entity = @import("entity.zig");
const ActorMoveable = @import("actor_moveable.zig");
const Player = @This();
const Scene = @import("scene.zig");
const Sprite = @import("sprite.zig");
const co = @import("collisions.zig");
const constants = @import("constants.zig");
const debug = @import("debug.zig");
const helpers = @import("helpers.zig");
const rl = @import("raylib");
const shapes = @import("shapes.zig");
const std = @import("std");
const tl = @import("tiles.zig");

const approach = helpers.approach;

moveable: ActorMoveable,
sprite: Sprite,
sprite_offset: rl.Vector2,
is_grounded: bool = false,
speed: rl.Vector2,
world_collision_mask: u4 = 0,
jump_counter: u2 = 0,

const run_speed: f32 = 3 * 60;
const run_acceleration: f32 = 10 * 60;
const run_reduce: f32 = 22 * 60;
const fly_reduce: f32 = 12 * 60;
const fall_speed: f32 = 3.6 * 60;
const jump_speed: f32 = -6 * 60;

pub fn init(hitbox: rl.Rectangle, sprite: Sprite, sprite_offset: rl.Vector2) Player {
    return .{
        .speed = rl.Vector2.init(0, 0),
        .sprite = sprite,
        .sprite_offset = sprite_offset,
        .moveable = ActorMoveable.init(hitbox),
    };
}

pub fn entity(self: *Player) Entity {
    return .{
        .ptr = self,
        .impl = &.{
            .update = update,
            .draw = draw,
            .drawDebug = drawDebug,
        },
    };
}

pub fn move(self: *Player, comptime axis: ActorMoveable.MoveAxis, layer: tl.TileLayer, amount: f32) void {
    self.moveable.move(axis, layer, amount, self);
}

pub fn handleCollision(self: *Player, axis: ActorMoveable.MoveAxis, sign: i8) void {
    if (axis == ActorMoveable.MoveAxis.X) {
        self.speed.x = 0;

        switch (sign) {
            1 => self.world_collision_mask |= @intFromEnum(co.CollisionDirection.Right),
            -1 => self.world_collision_mask |= @intFromEnum(co.CollisionDirection.Left),
            else => {},
        }
    } else {
        self.speed.y = 0;
        self.jump_counter = 0;
        // self.is_grounded = true;

        switch (sign) {
            1 => self.world_collision_mask |= @intFromEnum(co.CollisionDirection.Down),
            -1 => self.world_collision_mask |= @intFromEnum(co.CollisionDirection.Up),
            else => {},
        }
    }
}

pub fn update(ctx: *anyopaque, scene: *Scene, delta_time: f32) !void {
    const self: *Player = @ptrCast(@alignCast(ctx));

    self.world_collision_mask = 0;

    // Jumping
    if (constants.isKeyboardControlPressed(constants.KBD_JUMP) and self.jump_counter < 2) {
        self.speed.y = jump_speed;
        self.jump_counter += 1;
    }

    const is_grounded = self.jump_counter == 0;

    // Left/right movement
    if (constants.isKeyboardControlDown(constants.KBD_MOVE_LEFT)) {
        const mult: f32 = if (self.speed.x > 0) 3 else 1;
        self.speed.x = approach(self.speed.x, -run_speed, run_acceleration * mult * delta_time);
    } else if (constants.isKeyboardControlDown(constants.KBD_MOVE_RIGHT)) {
        const mult: f32 = if (self.speed.x < 0) 3 else 1;
        self.speed.x = approach(self.speed.x, run_speed, run_acceleration * mult * delta_time);
    } else {
        if (is_grounded) {
            self.speed.x = approach(self.speed.x, 0, run_reduce * delta_time);
        } else {
            self.speed.x = approach(self.speed.x, 0, fly_reduce * delta_time);
        }
    }

    // Gravity
    self.speed.y = approach(self.speed.y, fall_speed, scene.gravity * delta_time);

    // Set animation and direction
    if (!is_grounded) {
        self.sprite.setAnimation(.Jump, null, true);
    } else if (self.speed.x == 0) {
        self.sprite.setAnimation(.Idle, null, false);
    } else if (self.speed.x > 0) {
        self.sprite.setFlip(Sprite.FlipState.XFlip, false);
        self.sprite.setAnimation(.Walk, null, false);
    } else if (self.speed.x < 0) {
        self.sprite.setFlip(Sprite.FlipState.XFlip, true);
        self.sprite.setAnimation(.Walk, null, false);
    }

    // Move the player hitbox
    self.move(ActorMoveable.MoveAxis.X, scene.main_layer, self.speed.x * delta_time);
    self.move(ActorMoveable.MoveAxis.Y, scene.main_layer, self.speed.y * delta_time);

    scene.centerViewportOnPos(self.moveable.hitbox);

    try self.sprite.update(scene, delta_time);
}

pub fn draw(ctx: *anyopaque, scene: *const Scene) void {
    const self: *Player = @ptrCast(@alignCast(ctx));
    const sprite_pos = helpers.getRelativePos(self.sprite_offset, rl.Vector2.init(self.moveable.hitbox.x, self.moveable.hitbox.y));

    self.sprite.draw(scene, sprite_pos);
}

pub fn drawDebug(ctx: *anyopaque, scene: *const Scene) void {
    const self: *Player = @ptrCast(@alignCast(ctx));
    const sprite_pos = helpers.getRelativePos(self.sprite_offset, rl.Vector2.init(self.moveable.hitbox.x, self.moveable.hitbox.y));

    self.sprite.drawDebug(scene, sprite_pos);

    if (debug.isDebugFlagSet(.ShowHitboxes)) {
        const rect = scene.getViewportAdjustedPos(rl.Rectangle, self.moveable.hitbox);
        rl.drawRectangleLinesEx(rect, 1, rl.Color.red);
    }
}

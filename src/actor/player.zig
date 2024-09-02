const Actor = @import("actor.zig");
const CollidableBody = @import("collidable_body.zig");
const Entity = @import("../entity.zig");
const Player = @This();
const Scene = @import("../scene.zig");
const Sprite = @import("../sprite.zig");
const constants = @import("../constants.zig");
const controls = @import("../controls.zig");
const debug = @import("../debug.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");
const shapes = @import("../shapes.zig");
const std = @import("std");

const approach = helpers.approach;

collidable: CollidableBody,
sprite: Sprite,
sprite_offset: rl.Vector2,
speed: rl.Vector2,
jump_counter: u2 = 0,
lives: u8 = 10,
is_stunlocked: bool = false,

sfx_hurt: rl.Sound,
sfx_jump: rl.Sound,

const run_speed: f32 = 3 * 60;
const run_acceleration: f32 = 10 * 60;
const run_reduce: f32 = 22 * 60;
const fly_reduce: f32 = 12 * 60;
const fall_speed: f32 = 3.6 * 60;
const jump_speed: f32 = -5 * 60;
const knockback_x_speed: f32 = 6 * 60;
const knockback_y_speed: f32 = -2 * 60;
const roll_speed: f32 = 7 * 60;
const roll_reduce: f32 = 2 * 60;

pub fn init(hitbox: rl.Rectangle, sprite: Sprite, sprite_offset: rl.Vector2) Player {
    const sfx_hurt = rl.loadSound("assets/sounds/hurt.wav");
    const sfx_jump = rl.loadSound("assets/sounds/jump.wav");

    return .{
        .sfx_hurt = sfx_hurt,
        .sfx_jump = sfx_jump,
        .speed = rl.Vector2.init(0, 0),
        .sprite = sprite,
        .sprite_offset = sprite_offset,
        .collidable = CollidableBody.init(hitbox),
    };
}

pub fn actor(self: *Player) Actor {
    return .{ .ptr = self, .impl = &.{
        .entity = entityCast,
        .getHitboxRect = getHitboxRect,
        .getGridRect = getGridRect,
        .setPos = setPos,
    } };
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

fn entityCast(ctx: *anyopaque) Entity {
    const self: *Player = @ptrCast(@alignCast(ctx));
    return self.entity();
}

fn getHitboxRect(ctx: *anyopaque) rl.Rectangle {
    const self: *Player = @ptrCast(@alignCast(ctx));
    return self.collidable.hitbox;
}

fn getGridRect(ctx: *anyopaque) shapes.IRect {
    const self: *Player = @ptrCast(@alignCast(ctx));
    return self.collidable.grid_rect;
}

fn move(self: *Player, scene: *const Scene, comptime axis: CollidableBody.MoveAxis, amount: f32) void {
    self.collidable.move(scene, axis, amount, self);
}

pub fn handleCollision(self: *Player, axis: CollidableBody.MoveAxis, sign: i8) void {
    if (axis == CollidableBody.MoveAxis.X) {
        self.speed.x = 0;
    } else {
        self.speed.y = 0;

				if (sign == 1) {
					// Only reset jump counter when colliding with something below player
	        self.jump_counter = 0;
	        self.is_stunlocked = false;
	
	        if (self.lives == 0) {
	            self.sprite.setAnimation(.Death, null, true);
	        }
				}
    }
}

fn setPos(ctx: *anyopaque, pos: rl.Vector2) void {
    const self: *Player = @ptrCast(@alignCast(ctx));
    self.collidable.hitbox.x = pos.x;
    self.collidable.hitbox.y = pos.y;
}

fn update(ctx: *anyopaque, scene: *Scene, delta_time: f32) !void {
    const self: *Player = @ptrCast(@alignCast(ctx));

    if (self.sprite.current_animation == .Death) {
        try self.sprite.update(scene, delta_time);
        return;
    }

    // Jumping
    if (!self.is_stunlocked and controls.isKeyboardControlPressed(controls.KBD_JUMP) and self.jump_counter < 2) {
        rl.playSound(self.sfx_jump);
        self.speed.y = jump_speed;
        self.jump_counter += 1;
    }
    const is_grounded = self.jump_counter == 0;

    // Rolling
    if (self.speed.x != 0 and self.sprite.current_animation != .Roll and !self.is_stunlocked and is_grounded and controls.isKeyboardControlPressed(controls.KBD_ROLL)) {
        self.sprite.setAnimation(.Roll, .Idle, false);
        self.speed.x = std.math.sign(self.speed.x) * roll_speed;
        // self.speed.x = approach(self.speed.x, std.math.sign(self.speed.x) * roll_speed, roll_acceleration * delta_time);
    }
    const is_rolling = self.sprite.current_animation == .Roll;

    // Left/right movement
    if (self.is_stunlocked) {
        self.speed.x = approach(self.speed.x, 0, fly_reduce * delta_time);
    } else if (is_rolling) {
        self.speed.x = approach(self.speed.x, 0, roll_reduce * delta_time);
    } else {
        if (controls.isKeyboardControlDown(controls.KBD_MOVE_LEFT)) {
            const turn_multiplier: f32 = if (self.speed.x > 0) 3 else 1;
            self.speed.x = approach(self.speed.x, -run_speed, run_acceleration * turn_multiplier * delta_time);
        } else if (controls.isKeyboardControlDown(controls.KBD_MOVE_RIGHT)) {
            const turn_multiplier: f32 = if (self.speed.x < 0) 3 else 1;
            self.speed.x = approach(self.speed.x, run_speed, run_acceleration * turn_multiplier * delta_time);
        } else {
            if (!is_grounded) {
                self.speed.x = approach(self.speed.x, 0, fly_reduce * delta_time);
            } else {
                self.speed.x = approach(self.speed.x, 0, run_reduce * delta_time);
            }
        }
    }

    // Gravity
    self.speed.y = approach(self.speed.y, fall_speed, scene.gravity * delta_time);

    // Set animation and direction
    if (self.is_stunlocked) {
        self.sprite.setAnimation(.Hit, null, true);
    } else if (!is_rolling) {
        if (!is_grounded) {
            self.sprite.setAnimation(.Jump, null, true);
        } else if (self.speed.x == 0) {
            self.sprite.setAnimation(.Idle, null, false);
        } else {
            self.sprite.setAnimation(.Walk, null, false);
        }
    }

    if (self.speed.x > 0) {
        self.sprite.setFlip(Sprite.FlipState.XFlip, if (self.is_stunlocked) true else false);
    } else if (self.speed.x < 0) {
        self.sprite.setFlip(Sprite.FlipState.XFlip, if (self.is_stunlocked) false else true);
    }

    // Collision with mobs
    if (!self.is_stunlocked and !debug.isPaused()) {
        for (0..scene.mobs_amount) |mob_idx| {
            const mob = scene.mobs[mob_idx];
            var player_hitbox = getHitboxRect(ctx);
            const mob_hitbox = mob.getHitboxRect();

            if (is_rolling) {
                player_hitbox.height /= 2;
                player_hitbox.y += player_hitbox.height;
            }

            if (player_hitbox.checkCollision(mob_hitbox)) {
                rl.playSound(self.sfx_hurt);

                const knockback_direction = std.math.sign((player_hitbox.x + player_hitbox.width / 2) - mob_hitbox.x);
                self.is_stunlocked = true;
                self.speed.x = knockback_direction * knockback_x_speed;
                self.speed.y = knockback_y_speed;
                if (self.lives > 0) {
                    self.lives -= 1;
                }

								// Break out of loop to avoid registering collisions with
								// multiple mobs in a single frame
								break;
            }
        }
    }

    // Move the player hitbox
    self.move(scene, CollidableBody.MoveAxis.X, self.speed.x * delta_time);
    self.move(scene, CollidableBody.MoveAxis.Y, self.speed.y * delta_time);

    scene.centerViewportOnPos(self.collidable.hitbox);

    try self.sprite.update(scene, delta_time);
}

fn draw(ctx: *anyopaque, scene: *const Scene) void {
    const self: *Player = @ptrCast(@alignCast(ctx));
    const sprite_pos = helpers.getRelativePos(self.sprite_offset, self.collidable.hitbox);

    self.sprite.draw(scene, sprite_pos, rl.Color.white);
}

fn drawDebug(ctx: *anyopaque, scene: *const Scene) void {
    const self: *Player = @ptrCast(@alignCast(ctx));
    const sprite_pos = helpers.getRelativePos(self.sprite_offset, self.collidable.hitbox);

    self.sprite.drawDebug(scene, sprite_pos);
    self.collidable.drawDebug(scene);
}

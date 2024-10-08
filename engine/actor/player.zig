const Actor = @import("actor.zig");
const Effect = @import("../effect.zig");
const GameState = @import("../gamestate.zig");
const Player = @This();
const RigidBody = @import("rigid_body.zig");
const Scene = @import("../scene.zig");
const Solid = @import("../solid/solid.zig");
const Tileset = @import("../tileset/tileset.zig");
const Weapon = @import("weapon.zig");
const an = @import("../animation.zig");
const constants = @import("../constants.zig");
const controls = @import("../controls.zig");
const debug = @import("../debug.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");
const shapes = @import("../shapes.zig");
const std = @import("std");
const tracing = @import("../tracing.zig");
const types = @import("../types.zig");

const approach = helpers.approach;

current_effect: ?Effect = null,
weapon: ?Weapon = null,
initial_hitbox: rl.Rectangle,
rigid_body: RigidBody,
face_dir: i2 = 1,
is_slipping: bool = false,
is_stunlocked: bool = false,
jump_counter: u2 = 0,
lives: u8 = max_lives,
score: u32 = 0,
speed: rl.Vector2,
sprite: an.Sprite,
sprite_offset: rl.Vector2,

sfx_hurt: rl.Sound,
sfx_jump: rl.Sound,
sfx_land: rl.Sound,

pub const AnimationType = enum(u8) {
    Idle,
    Walk,
    Roll,
    Hit,
    Death,
    Attack,
    Jump,
};

// pub const AnimationTransform = union {
//     rotation: f32,
//
//     pub fn transform(self: AnimationTransform, )
// };

pub fn Prefab(
    hitbox: rl.Rectangle,
    sprite_offset: rl.Vector2,
    getSpriteReader: *const fn () an.AnySpriteBuffer,
) type {
    return struct {
        pub const sprite_reader = getSpriteReader;
        pub fn init(pos: shapes.IPos) Player {
            const sprite = sprite_reader().sprite() catch @panic("Failed to read sprite");

            var player_hitbox = hitbox;
            player_hitbox.x = @floatFromInt(pos.x);
            player_hitbox.y = @floatFromInt(pos.y);

            return Player.init(player_hitbox, sprite, sprite_offset);
        }
    };
}

const fall_speed: f32 = 3.6 * 60;
const fly_reduce: f32 = 6 * 60;
const jump_speed: f32 = -4 * 60;
const knockback_x_speed: f32 = 6 * 60;
const knockback_y_speed: f32 = -2 * 60;
const roll_reduce: f32 = 2 * 60;
const roll_speed: f32 = 7 * 60;
const run_acceleration: f32 = 10 * 60;
const run_reduce: f32 = 22 * 60;
const run_speed: f32 = 3 * 60;
const slip_acceleration: f32 = 50 * 60;
const slip_reduce: f32 = 3 * 60;
const slip_speed: f32 = 4 * 60;

pub const max_lives = 5;
pub const max_score = 999999;

pub fn init(hitbox: rl.Rectangle, sprite: an.Sprite, sprite_offset: rl.Vector2) Player {
    const sfx_hurt = rl.loadSound("assets/sounds/hurt.wav");
    const sfx_jump = rl.loadSound("assets/sounds/jump.wav");
    const sfx_land = rl.loadSound("assets/sounds/tap.wav");

    const weapon = Weapon.WeaponExcalibur.init();

    return .{
        .initial_hitbox = hitbox,
        .sfx_hurt = sfx_hurt,
        .sfx_jump = sfx_jump,
        .sfx_land = sfx_land,
        .speed = rl.Vector2.init(0, 0),
        .sprite = sprite,
        .sprite_offset = sprite_offset,
        .rigid_body = RigidBody.init(hitbox),
        .weapon = weapon,
    };
}

pub fn reset(self: *Player) !void {
    self.* = Player.init(self.initial_hitbox, self.sprite, self.sprite_offset);
    try self.sprite.reset();
}

pub fn actor(self: *Player) Actor {
    return .{ .ptr = self, .impl = &.{
        .getRigidBody = getRigidBody,
        .getHitboxRect = getHitboxRect,
        .getGridRect = getGridRect,
        .getSprite = getSprite,
        .isHostile = isHostile,
        .squish = handleSquish,
        .setPos = setPos,
    } };
}

fn getRigidBody(ctx: *anyopaque) *RigidBody {
    const self: *Player = @ptrCast(@alignCast(ctx));
    return &self.rigid_body;
}

fn getHitboxRect(ctx: *const anyopaque) rl.Rectangle {
    const self: *const Player = @ptrCast(@alignCast(ctx));
    return self.rigid_body.hitbox;
}

fn getGridRect(ctx: *const anyopaque) shapes.IRect {
    const self: *const Player = @ptrCast(@alignCast(ctx));
    return self.rigid_body.grid_rect;
}

fn getSprite(ctx: *anyopaque) *an.Sprite {
    const self: *Player = @ptrCast(@alignCast(ctx));
    return &self.sprite;
}

fn isHostile() bool {
    return false;
}

fn handleSquish(ctx: *anyopaque, scene: *Scene, _: types.Axis, _: i8, _: u8) void {
    const self: *Player = @ptrCast(@alignCast(ctx));
    self.die(scene);
}

inline fn die(self: *Player, scene: *Scene) void {
    const gamestate = scene.gamestate;
    self.lives = 0;
    self.rigid_body.mode = .Static;
    self.sprite.setAnimation(AnimationType.Death, .{
        .on_animation_finished = .{ .context = self, .call_ptr = handleGameOver },
    });
    scene.game_over_screen_elapsed = 0;
    gamestate.current_music = &gamestate.music_gameover;
    rl.playMusicStream(gamestate.current_music.*);
}

pub fn handleCollision(self: *Player, scene: *Scene, axis: types.Axis, sign: i8, flags: u8, solid: ?Solid) void {
    const deadly_fall = flags & @intFromEnum(Tileset.TileFlag.Deadly) != 0;
    if (deadly_fall) {
        self.die(scene);
    }
    if (axis == types.Axis.X) {
        self.speed.x = 0;
    } else {
        if (sign == 1) {
            if (self.speed.y > 60 and !deadly_fall) {
                // Heavy landing game feel stuff
                rl.playSound(self.sfx_land);

                self.current_effect = Effect.Dust.init(
                    an.DrawPosition.init(
                        self.rigid_body.hitbox,
                        if (self.face_dir == 1) .BottomLeft else .BottomRight,
                        .{ .x = if (self.face_dir == 1) -(Effect.Dust.width / 2) else Effect.Dust.width / 2, .y = 0 },
                    ),
                    .{
                        .call_ptr = handleEffectOver,
                        .context = self,
                    },
                    self.face_dir == 1,
                );
            }
            self.jump_counter = 0;
            self.is_stunlocked = false;
            self.is_slipping = flags & @intFromEnum(Tileset.TileFlag.Slippery) != 0;

            if (self.lives == 0) {
                self.die(scene);
            }
        }

        self.speed.y = 0;
    }

    if (solid) |s| {
        s.handlePlayerCollision(scene, axis, sign, flags, self);
    }
}

pub fn gainLives(self: *Player, amount: u8) bool {
    if (self.lives == max_lives) {
        return false;
    }
    self.lives = @min(max_lives, self.lives + amount);
    return true;
}

pub fn gainScore(self: *Player, amount: u8) bool {
    if (self.score == max_score) {
        return false;
    }
    self.score = @min(max_score, self.score + amount);
    return true;
}

fn setPos(ctx: *anyopaque, pos: rl.Vector2) void {
    const self: *Player = @ptrCast(@alignCast(ctx));
    self.rigid_body.hitbox.x = pos.x;
    self.rigid_body.hitbox.y = pos.y;
}

fn revertToIdle(ctx: *anyopaque, _: *an.Animation) void {
    const self: *Player = @ptrCast(@alignCast(ctx));
    self.sprite.setAnimation(AnimationType.Idle, .{});
}

fn handleGameOver(_: *anyopaque, _: *an.Animation) void {
    std.debug.print("Handling game over\n", .{});
    // Do nothing (for now)
}

fn isCurrentAnimation(self: *Player, animation: AnimationType) bool {
    return self.sprite.animation.anim_data.type == @intFromEnum(animation);
}

fn handleEffectOver(ctx: *anyopaque, _: *an.Animation) void {
    const self: *Player = @ptrCast(@alignCast(ctx));
    self.current_effect = null;
}

pub fn update(self: *Player, scene: *Scene, delta_time: f32) !void {
    const zone = tracing.ZoneN(@src(), "Player Update");
    defer zone.End();

    if (self.isCurrentAnimation(.Death)) {
        self.sprite.update(delta_time);
        return;
    }

    // Jumping
    if (!self.is_stunlocked and controls.isKeyboardControlPressed(controls.KBD_JUMP) and self.jump_counter < 2) {
        rl.playSound(self.sfx_jump);
        self.speed.y = jump_speed;
        self.jump_counter += 1;
    }
    const is_grounded = self.jump_counter == 0;
    const is_slipping = self.is_slipping and is_grounded;

    // Rolling
    if (self.speed.x != 0 and !self.isCurrentAnimation(.Roll) and !self.is_stunlocked and is_grounded and controls.isKeyboardControlPressed(controls.KBD_ROLL)) {
        self.sprite.setAnimation(AnimationType.Roll, .{ .on_animation_finished = .{ .context = self, .call_ptr = revertToIdle } });
        self.speed.x = std.math.sign(self.speed.x) * roll_speed;
    }
    const is_rolling = self.isCurrentAnimation(.Roll);

    // Attacking
    if (controls.isKeyboardControlPressed(controls.KBD_ATTACK)) {
        if (self.weapon) |*weapon| {
            weapon.attack(self.actor());
        }
    }

    // Left/right movement
    if (self.is_stunlocked) {
        self.speed.x = approach(self.speed.x, 0, fly_reduce * delta_time);
    } else if (is_rolling) {
        self.speed.x = approach(self.speed.x, 0, roll_reduce * delta_time);
    } else {
        const turn_multiplier: f32 = if (self.speed.x > 0 and !is_slipping) 3 else 1;
        const speed = if (is_slipping) slip_speed else run_speed;
        const acceleration = if (is_slipping) slip_acceleration else run_acceleration;
        if (controls.isKeyboardControlDown(controls.KBD_MOVE_LEFT)) {
            self.speed.x = approach(self.speed.x, -speed, acceleration * turn_multiplier * delta_time);
            self.face_dir = -1;
        } else if (controls.isKeyboardControlDown(controls.KBD_MOVE_RIGHT)) {
            self.face_dir = 1;
            self.speed.x = approach(self.speed.x, speed, acceleration * turn_multiplier * delta_time);
        } else {
            if (!is_grounded) {
                self.speed.x = approach(self.speed.x, 0, fly_reduce * delta_time);
            } else if (is_slipping) {
                self.speed.x = approach(self.speed.x, 0, slip_reduce * delta_time);
            } else {
                self.speed.x = approach(self.speed.x, 0, run_reduce * delta_time);
            }
        }
    }

    // Gravity
    self.speed.y = approach(self.speed.y, fall_speed, scene.gravity * delta_time);

    // Set animation and direction
    if (self.is_stunlocked) {
        self.sprite.setAnimation(AnimationType.Hit, .{});
    } else if (!is_rolling) {
        if (!is_grounded) {
            self.sprite.setAnimation(AnimationType.Jump, .{});
        } else if (self.speed.x == 0) {
            self.sprite.setAnimation(AnimationType.Idle, .{});
        } else {
            self.sprite.setAnimation(AnimationType.Walk, .{
                .animation_speed = @min(2, @abs(self.speed.x) / 180),
            });
        }
    }

    if (self.is_stunlocked) {
        self.sprite.flip_mask.x = self.speed.x > 0;
    } else {
        self.sprite.flip_mask.x = self.face_dir == -1;
    }

    // Collision with hostile actors
    if (!self.is_stunlocked and !debug.isPaused()) {
        var actor_iter = scene.getActorIterator();
        const player_actor = self.actor();
        while (actor_iter.next()) |a| {
            if (a.is(self) or !a.isHostile()) {
                continue;
            }

            // TODO 07/09/2024: Actually change the hitbox of the
            // actor collidable when rolling, instead of patching it
            // in to the collision calc like this
            //
            // if (is_rolling) {
            //     player_hitbox.height /= 2;
            //     player_hitbox.y += player_hitbox.height;
            // }

            if (player_actor.overlapsActor(a)) {
                rl.playSound(self.sfx_hurt);

                const player_hitbox = getHitboxRect(self);
                const actor_hitbox = a.getHitboxRect();

                const knockback_direction = std.math.sign((player_hitbox.x + player_hitbox.width / 2) - actor_hitbox.x);
                self.is_stunlocked = true;
                self.speed.x = knockback_direction * knockback_x_speed;
                self.speed.y = knockback_y_speed;
                if (self.lives > 0) {
                    self.lives -= 1;
                }

                // Break out of loop to avoid registering collisions with
                // multiple actors in a single frame
                break;
            }
        }
    }

    // Move the player hitbox
    if (self.speed.x != 0) {
        self.rigid_body.move(scene, types.Axis.X, self.speed.x * delta_time, self);
    }
    if (self.speed.y != 0) {
        self.rigid_body.move(scene, types.Axis.Y, self.speed.y * delta_time, self);
    }

    // if (rl.isKeyPressed(rl.KeyboardKey.key_q)) {
    scene.centerViewportOnPos(self.rigid_body.hitbox);
    // }

    self.sprite.update(delta_time);

    // Update weapon position
    if (self.weapon) |*weapon| {
        try weapon.update(scene, self.actor(), delta_time);
    }

    if (self.current_effect != null) {
        try self.current_effect.?.update(scene, delta_time);
    }
}

pub fn draw(self: *const Player, scene: *const Scene) void {
    const zone = tracing.ZoneN(@src(), "Player Draw");
    defer zone.End();

    const sprite_pos = an.DrawPosition.init(self.rigid_body.hitbox, .BottomCenter, self.sprite_offset);

    self.sprite.draw(scene, sprite_pos, rl.Color.white);

    if (self.weapon) |*weapon| {
        weapon.draw(scene);
    }

    if (self.current_effect != null) {
        self.current_effect.?.draw(scene);
    }
}

pub fn drawDebug(self: *const Player, scene: *const Scene) void {
    const zone = tracing.ZoneN(@src(), "Player Draw Debug");
    defer zone.End();

    const sprite_pos = an.DrawPosition.init(self.rigid_body.hitbox, .BottomCenter, self.sprite_offset);

    self.sprite.drawDebug(scene, sprite_pos);
    self.rigid_body.drawDebug(scene);
}

pub const Knight = @import("player/knight.zig").Knight;

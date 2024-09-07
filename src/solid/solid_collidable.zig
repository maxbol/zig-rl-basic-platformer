const Scene = @import("../scene.zig");
const Solid = @import("solid.zig");
const SolidCollidable = @This();
const rl = @import("raylib");
const std = @import("std");
const types = @import("../types.zig");

collidable: bool = true,
x_remainder: f32 = 0,
y_remainder: f32 = 0,
hitbox: rl.Rectangle,

pub fn init(hitbox: rl.Rectangle) SolidCollidable {
    return .{
        .hitbox = hitbox,
    };
}

inline fn moveOnAxis(self: *SolidCollidable, riding_it: Solid.RidingActorIterator, scene: *const Scene, solid: *Solid, axis: types.Axis, amount: i32) void {
    const remainder = if (axis == .X) &self.x_remainder else &self.y_remainder;
    const hitbox_loc = if (axis == .X) &self.hitbox.x else &self.hitbox.y;
    const hitbox_size = if (axis == .X) &self.hitbox.width else &self.hitbox.height;

    remainder.* -= @floatFromInt(amount);
    hitbox_loc.* += amount;

    const mov_dir = std.math.sign(amount);

    while (riding_it.next()) |actor| {
        if (solid.overlapsActor(actor)) {
            // Push the actor out of the way

            const actor_hitbox = actor.getHitboxRect();
            const mov_amount = if (mov_dir == 1)
                hitbox_loc.* + hitbox_size.* - (if (axis == .X) actor_hitbox.x else actor_hitbox.y)
            else
                hitbox_loc.* - hitbox_size.* - (if (axis == .X) actor_hitbox.width else actor_hitbox.height);

            actor.getCollidableBody().move(
                scene,
                scene,
                axis,
                mov_amount,
            );
        }
        if (actor.isRiding(solid)) {
            actor.getCollidableBody().move(scene, axis, amount, null);
        }
    }
}

pub fn move(self: *SolidCollidable, scene: *const Scene, solid: *Solid, x: f32, y: f32) void {
    self.x_remainder += x;
    self.y_remainder += y;

    const x_mov: i32 = @intFromFloat(@round(self.x_remainder));
    const y_mov: i32 = @intFromFloat(@round(self.y_remainder));
    const riding_it = solid.getRidingActorsIterator();

    self.collidable = false;

    if (x_mov != 0) {
        self.moveOnAxis(riding_it, scene, solid, .X, x_mov);
    }

    if (y_mov != 0) {
        self.moveOnAxis(riding_it, scene, solid, .Y, y_mov);
    }

    self.collidable = true;
}

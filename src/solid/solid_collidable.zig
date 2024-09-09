const Actor = @import("../actor/actor.zig");
const Scene = @import("../scene.zig");
const Solid = @import("solid.zig");
const SolidCollidable = @This();
const rl = @import("raylib");
const std = @import("std");
const types = @import("../types.zig");

x_remainder: f32 = 0,
y_remainder: f32 = 0,
hitbox: rl.Rectangle,

pub fn init(hitbox: rl.Rectangle) SolidCollidable {
    return .{
        .hitbox = hitbox,
    };
}

inline fn moveOnAxis(self: *SolidCollidable, all_actors: []Actor, riding_actors: []usize, scene: *Scene, solid: Solid, axis: types.Axis, amount: i32) void {
    const remainder = if (axis == .X) &self.x_remainder else &self.y_remainder;
    const hitbox_loc = if (axis == .X) &self.hitbox.x else &self.hitbox.y;
    const hitbox_size = if (axis == .X) &self.hitbox.width else &self.hitbox.height;

    remainder.* -= @floatFromInt(amount);
    hitbox_loc.* += @floatFromInt(amount);

    const mov_dir = std.math.sign(amount);

    for (all_actors, 0..) |actor, i| {
        const actor_rigid = actor.getRigidBody();

        if (solid.overlapsActor(actor)) {
            // Push the actor out of the way

            const actor_hitbox = actor_rigid.hitbox;
            const mov_amount = if (mov_dir == 1)
                hitbox_loc.* + hitbox_size.* - (if (axis == .X) (actor_hitbox.x) else (actor_hitbox.y))
            else
                hitbox_loc.* - if (axis == .X) (actor_hitbox.x + actor_hitbox.width) else (actor_hitbox.y + actor_hitbox.height);

            actor_rigid.move(
                scene,
                axis,
                mov_amount,
                actor.squishCollider(),
            );

            continue;
        }

        for (riding_actors) |idx| {
            if (idx != i) {
                continue;
            }

            actor_rigid.move(scene, axis, @floatFromInt(amount), null);
            break;
        }
    }
}

pub fn move(self: *SolidCollidable, scene: *Scene, solid: Solid, x: f32, y: f32) void {
    self.x_remainder += x;
    self.y_remainder += y;

    const x_mov: i32 = @intFromFloat(@round(self.x_remainder));
    const y_mov: i32 = @intFromFloat(@round(self.y_remainder));

    var actor_it = scene.getActorIterator();
    var all_actors: [1000]Actor = undefined;
    var riding_actors: [10]usize = undefined;
    var actors_idx: usize = 0;
    var riding_idx: usize = 0;

    while (actor_it.next()) |actor| {
        all_actors[actors_idx] = actor;
        if (actor.isRiding(solid)) {
            riding_actors[riding_idx] = actors_idx;
            riding_idx += 1;
        }
        actors_idx += 1;
    }

    const all_actors_slice = all_actors[0..actors_idx];
    const riding_actors_slice = riding_actors[0..riding_idx];

    solid.setIsCollidable(false);

    if (x_mov != 0) {
        self.moveOnAxis(
            all_actors_slice,
            riding_actors_slice,
            scene,
            solid,
            .X,
            x_mov,
        );
    }

    if (y_mov != 0) {
        self.moveOnAxis(
            all_actors_slice,
            riding_actors_slice,
            scene,
            solid,
            .Y,
            y_mov,
        );
    }

    solid.setIsCollidable(true);
}

const Entity = @import("entity.zig");
const ActorMoveable = @This();
const Scene = @import("scene.zig");
const helpers = @import("helpers.zig");
const rl = @import("raylib");
const shapes = @import("shapes.zig");
const std = @import("std");
const tiles = @import("tiles.zig");

hitbox: rl.Rectangle,
x_remainder: f32 = 0,
y_remainder: f32 = 0,

pub fn init(hitbox: rl.Rectangle) ActorMoveable {
    return .{
        .hitbox = hitbox,
    };
}

pub fn move(
    self: *ActorMoveable,
    comptime axis: MoveAxis,
    layer: tiles.TileLayer,
    amount: f32,
    collider: anytype,
) void {
    const remainder = if (axis == MoveAxis.X) &self.x_remainder else &self.y_remainder;

    remainder.* += amount;

    var mov: i32 = @intFromFloat(@round(remainder.*));

    if (mov == 0) {
        return;
    }

    remainder.* -= @floatFromInt(mov);

    const sign: i8 = @intCast(std.math.sign(mov));

    while (mov != 0) {
        var next_hitbox = shapes.IRect.fromRect(self.hitbox);

        if (axis == MoveAxis.X) {
            next_hitbox.x += sign;
        } else {
            next_hitbox.y += sign;
        }

        if (!layer.collideAt(next_hitbox)) {
            if (axis == MoveAxis.X) {
                self.hitbox.x += @floatFromInt(sign);
            } else {
                self.hitbox.y += @floatFromInt(sign);
            }

            mov -= sign;
        } else {
            collider.handleCollision(axis, sign);
            break;
        }
    }
}

pub const MoveAxis = enum {
    X,
    Y,
};

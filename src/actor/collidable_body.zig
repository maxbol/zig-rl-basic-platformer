const CollidableBody = @This();
const Entity = @import("../entity.zig");
const Scene = @import("../scene.zig");
const debug = @import("../debug.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");
const shapes = @import("../shapes.zig");
const std = @import("std");
const types = @import("../types.zig");

hitbox: rl.Rectangle,
x_remainder: f32 = 0,
y_remainder: f32 = 0,
grid_rect: shapes.IRect = shapes.IRect{ .x = 0, .y = 0, .width = 0, .height = 0 },

pub fn init(hitbox: rl.Rectangle) CollidableBody {
    return .{
        .hitbox = hitbox,
    };
}

pub fn move(
    self: *CollidableBody,
    scene: *Scene,
    comptime axis: types.Axis,
    amount: f32,
    collider: anytype,
) void {
    const remainder = if (axis == types.Axis.X) &self.x_remainder else &self.y_remainder;

    remainder.* += amount;

    var mov: i32 = @intFromFloat(remainder.*);

    if (mov == 0) {
        return;
    }

    remainder.* -= @floatFromInt(mov);

    const sign: i8 = @intCast(std.math.sign(mov));

    var grid_rect: shapes.IRect = undefined;

    while (mov != 0) {
        var next_hitbox = shapes.IRect.fromRect(self.hitbox);

        if (axis == types.Axis.X) {
            next_hitbox.x += sign;
        } else {
            next_hitbox.y += sign;
        }

        grid_rect = helpers.getGridRect(
            shapes.IPos.fromVec2(scene.main_layer.getTileset().getTileSize()),
            next_hitbox,
        );

        if (scene.collideAt(next_hitbox, grid_rect)) |tile_flags| {
            collider.handleCollision(axis, sign, tile_flags);
            break;
        } else {
            if (axis == types.Axis.X) {
                self.hitbox.x += @floatFromInt(sign);
            } else {
                self.hitbox.y += @floatFromInt(sign);
            }

            mov -= sign;
        }
    }

    self.grid_rect = grid_rect;
}

pub fn drawDebug(self: *const CollidableBody, scene: *const Scene) void {
    if (debug.isDebugFlagSet(.ShowHitboxes)) {
        const rect = scene.getViewportAdjustedPos(rl.Rectangle, self.hitbox);
        rl.drawRectangleLinesEx(rect, 1, rl.Color.red);
    }

    if (debug.isDebugFlagSet(.ShowGridBoxes)) {
        const pixel_rect = helpers.getPixelRect(
            scene.main_layer.getTileset().getTileSize(),
            self.grid_rect.toRect(),
        );
        const rect = scene.getViewportAdjustedPos(rl.Rectangle, pixel_rect);
        rl.drawRectangleLinesEx(rect, 1, rl.Color.gray);
    }
}

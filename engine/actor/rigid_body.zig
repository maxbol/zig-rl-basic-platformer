const RigidBody = @This();
const Scene = @import("../scene.zig");
const debug = @import("../debug.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");
const shapes = @import("../shapes.zig");
const std = @import("std");
const types = @import("../types.zig");

mode: MovementMode = MovementMode.Rigid,
hitbox: rl.Rectangle,
x_remainder: f32 = 0,
y_remainder: f32 = 0,
grid_rect: shapes.IRect = shapes.IRect{ .x = 0, .y = 0, .width = 0, .height = 0 },

pub const MovementMode = enum {
    Rigid,
    Static,
};

pub fn init(hitbox: rl.Rectangle) RigidBody {
    return .{
        .hitbox = hitbox,
    };
}

pub fn move(self: *RigidBody, scene: *Scene, comptime axis: types.Axis, amount: f32, collider: anytype) void {
    switch (self.mode) {
        .Static => self.moveStatic(axis, amount),
        .Rigid => self.moveRigid(scene, axis, amount, collider),
    }
}

fn moveStatic(self: *RigidBody, comptime axis: types.Axis, amount: f32) void {
    if (axis == types.Axis.X) {
        self.hitbox.x += amount;
    } else {
        self.hitbox.y += amount;
    }
}

fn moveRigid(
    self: *RigidBody,
    scene: *Scene,
    comptime axis: types.Axis,
    amount: f32,
    collider: anytype,
) void {
    std.debug.print("moveRigid()\n", .{});
    const remainder = if (axis == types.Axis.X) &self.x_remainder else &self.y_remainder;

    remainder.* += amount;

    var mov: i32 = @intFromFloat(@round(remainder.*));

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
        std.debug.print("next_hitbox {any}\n", .{next_hitbox});

        std.debug.print("Getting tile size\n", .{});

        grid_rect = helpers.getGridRect(
            shapes.IPos.fromVec2(scene.main_layer.getTileset().getTileSize()),
            next_hitbox,
        );

        std.debug.print("Checking collideAt() with grid_rect {any}\n", .{grid_rect});

        if (scene.collideAt(next_hitbox, grid_rect)) |c| {
            switch (@typeInfo(@TypeOf(collider))) {
                .Null => {},
                inline else => {
                    collider.handleCollision(scene, axis, sign, c.flags, c.solid);
                },
            }
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

    // Store the grid rect to be able to display it with drawDebug()
    // TODO 09/09/2024: Remove?
    self.grid_rect = grid_rect;

    std.debug.print("moveRigid() end\n", .{});
}

pub fn drawDebug(self: *const RigidBody, scene: *const Scene) void {
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

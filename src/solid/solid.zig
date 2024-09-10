const Actor = @import("../actor/actor.zig");
const Scene = @import("../scene.zig");
const Solid = @This();
const SolidCollidable = @import("solid_collidable.zig");
const rl = @import("raylib");
const shapes = @import("../shapes.zig");
const std = @import("std");
const types = @import("../types.zig");

ptr: *anyopaque,
impl: *const Interface,

pub const Interface = struct {
    isCollidable: *const fn (*const anyopaque) bool,
    setIsCollidable: *const fn (*anyopaque, bool) void,
    getHitboxRect: *const fn (*const anyopaque) rl.Rectangle,
    handlePlayerCollision: ?*const fn (*anyopaque, *Scene, types.Axis, i8, u8, Actor) void = null,
};

pub fn isCollidable(self: Solid) bool {
    return self.impl.isCollidable(self.ptr);
}

pub fn setIsCollidable(self: Solid, collidable: bool) void {
    return self.impl.setIsCollidable(self.ptr, collidable);
}

pub fn getHitboxRect(self: Solid) rl.Rectangle {
    return self.impl.getHitboxRect(self.ptr);
}

pub fn overlapsActor(self: Solid, actor: Actor) bool {
    return self.getHitboxRect().checkCollision(actor.getHitboxRect());
}

pub fn handlePlayerCollision(self: Solid, scene: *Scene, axis: types.Axis, sign: i8, flags: u8, player: Actor) void {
    if (self.impl.handlePlayerCollision) |call| {
        return call(self.ptr, scene, axis, sign, flags, player);
    }
}

pub fn collideAt(self: Solid, rect: shapes.IRect) bool {
    if (!self.isCollidable()) {
        return false;
    }

    const solid_rect = shapes.IRect.fromRect(self.getHitboxRect());

    return rect.isColliding(solid_rect);
}

pub const MysteryBox = @import("mystery_box.zig");
pub const Platform = @import("platform.zig");

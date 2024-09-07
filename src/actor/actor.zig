const Actor = @This();
const CollidableBody = @import("collidable_body.zig");
const Entity = @import("../entity.zig");
const Solid = @import("../solid/solid.zig");
const rl = @import("raylib");
const shapes = @import("../shapes.zig");
const types = @import("../types.zig");

ptr: *anyopaque,
impl: *const Interface,

pub const Interface = struct {
    getCollidableBody: *const fn (ctx: *anyopaque) *CollidableBody,
    getHitboxRect: *const fn (ctx: *const anyopaque) rl.Rectangle,
    getGridRect: *const fn (ctx: *const anyopaque) shapes.IRect,
    isRiding: *const fn (*anyopaque, Solid) bool,
    setPos: *const fn (ctx: *anyopaque, pos: rl.Vector2) void,
    squish: *const fn (*anyopaque, types.Axis, i8, u8) void,
};

pub const SquishCollider = struct {
    actor: Actor,
    pub fn handleCollision(self: SquishCollider, axis: types.Axis, sign: i8, flags: u8, _: ?Solid) void {
        return self.actor.squish(axis, sign, flags);
    }
};

pub fn is(self: Actor, ptr: *const anyopaque) bool {
    return self.ptr == ptr;
}

pub fn isRiding(self: Actor, solid: Solid) bool {
    return self.impl.isRiding(self.ptr, solid);
}

pub fn squish(self: Actor, axis: types.Axis, sign: i8, flags: u8) void {
    return self.impl.squish(self.ptr, axis, sign, flags);
}

pub fn squishCollider(self: Actor) SquishCollider {
    return .{ .actor = self };
}

pub fn getCollidableBody(self: Actor) *CollidableBody {
    return self.impl.getCollidableBody(self.ptr);
}

pub fn getHitboxRect(self: Actor) rl.Rectangle {
    return self.impl.getHitboxRect(self.ptr);
}

pub fn getGridRect(self: Actor) shapes.IRect {
    return self.impl.getGridRect(self.ptr);
}

pub fn overlapsActor(self: Actor, other: Actor) bool {
    return self.getHitboxRect().checkCollision(other.getHitboxRect());
}

pub fn setPos(self: Actor, pos: rl.Vector2) void {
    return self.impl.setPos(self.ptr, pos);
}

pub const Player = @import("player.zig");
pub const Mob = @import("mob.zig");

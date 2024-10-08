const Actor = @This();
const RigidBody = @import("rigid_body.zig");
const Scene = @import("../scene.zig");
const Solid = @import("../solid/solid.zig");
const an = @import("../animation.zig");
const rl = @import("raylib");
const shapes = @import("../shapes.zig");
const types = @import("../types.zig");

ptr: *anyopaque,
impl: *const Interface,

pub const Interface = struct {
    getRigidBody: *const fn (ctx: *anyopaque) *RigidBody,
    getHitboxRect: *const fn (ctx: *const anyopaque) rl.Rectangle,
    getGridRect: *const fn (ctx: *const anyopaque) shapes.IRect,
    getSprite: *const fn (ctx: *anyopaque) *an.Sprite,
    isHostile: *const fn () bool,
    setPos: *const fn (ctx: *anyopaque, pos: rl.Vector2) void,
    squish: ?*const fn (*anyopaque, *Scene, types.Axis, i8, u8) void = null,
};

pub const SquishCollider = struct {
    actor: Actor,
    pub fn handleCollision(self: SquishCollider, scene: *Scene, axis: types.Axis, sign: i8, flags: u8, _: ?Solid) void {
        return self.actor.squish(scene, axis, sign, flags);
    }
};

pub fn is(self: Actor, ptr: *const anyopaque) bool {
    return self.ptr == ptr;
}

pub fn isRiding(self: Actor, solid: Solid) bool {
    const solid_hitbox = solid.getHitboxRect();

    const hitbox = self.getHitboxRect();

    if (hitbox.x > solid_hitbox.x + solid_hitbox.width) {
        return false;
    }

    if (solid_hitbox.x > hitbox.x + hitbox.width) {
        return false;
    }

    if (hitbox.y + hitbox.height != solid_hitbox.y) {
        return false;
    }

    return true;
}

pub fn squish(self: Actor, scene: *Scene, axis: types.Axis, sign: i8, flags: u8) void {
    if (self.impl.squish) |call| {
        call(self.ptr, scene, axis, sign, flags);
    }
}

pub fn squishCollider(self: Actor) SquishCollider {
    return .{ .actor = self };
}

pub fn getRigidBody(self: Actor) *RigidBody {
    return self.impl.getRigidBody(self.ptr);
}

pub fn getHitboxRect(self: Actor) rl.Rectangle {
    return self.impl.getHitboxRect(self.ptr);
}

pub fn getGridRect(self: Actor) shapes.IRect {
    return self.impl.getGridRect(self.ptr);
}

pub fn getSprite(self: Actor) *an.Sprite {
    return self.impl.getSprite(self.ptr);
}

pub fn isHostile(self: Actor) bool {
    return self.impl.isHostile();
}

pub fn overlapsActor(self: Actor, other: Actor) bool {
    return self.getHitboxRect().checkCollision(other.getHitboxRect());
}

pub fn setPos(self: Actor, pos: rl.Vector2) void {
    return self.impl.setPos(self.ptr, pos);
}

pub const Player = @import("player.zig");
pub const Mob = @import("mob.zig");
pub const Collectable = @import("collectable.zig");

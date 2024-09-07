const Actor = @import("../actor/actor.zig");
const Scene = @import("../scene.zig");
const Solid = @This();
const SolidCollidable = @import("solid_collidable.zig");
const rl = @import("raylib");
const shapes = @import("../shapes.zig");

ptr: *anyopaque,
impl: *const Interface,

pub const Interface = struct {
    getCollidable: *const fn (*const anyopaque) SolidCollidable,
    getHitboxRect: *const fn (*const anyopaque) rl.Rectangle,
};

pub fn getCollidable(self: Solid) SolidCollidable {
    return self.impl.getCollidable(self.ptr);
}

pub fn getHitboxRect(self: Solid) rl.Rectangle {
    return self.impl.getHitboxRect(self.ptr);
}

pub fn overlapsActor(self: Solid, actor: Actor) bool {
    return self.getHitboxRect().checkCollision(actor.getHitboxRect());
}

pub fn collideAt(self: Solid, rect: shapes.IRect) bool {
    const collidable = self.getCollidable();

    if (!collidable.collidable) {
        return false;
    }

    const solid_rect = shapes.IRect.fromRect(self.getHitboxRect());

    return rect.isColliding(solid_rect);
}

pub const Platform = @import("platform.zig");

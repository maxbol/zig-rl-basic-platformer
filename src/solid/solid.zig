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

pub const RidingActorIterator = struct {
    iterator: Scene.SceneActorIterator,
    solid: *const Solid,

    pub fn init(scene: *const Scene, solid: *const Solid) RidingActorIterator {
        return .{
            .iterator = scene.getActorIterator(),
            .solid = solid,
        };
    }

    pub fn next(self: *RidingActorIterator) ?Actor {
        const n = self.iterator.next() orelse return null;

        if (n.isRiding(self.solid)) {
            return n;
        }

        return self.next();
    }
};

pub fn getCollidable(self: Solid) SolidCollidable {
    return self.impl.getCollidable(self.ptr);
}

pub fn getHitboxRect(self: Solid) rl.Rectangle {
    return self.impl.getHitboxRect(self.ptr);
}

pub fn getRidingActorsIterator(self: Solid, scene: *const Scene) RidingActorIterator {
    return RidingActorIterator.init(scene, self);
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

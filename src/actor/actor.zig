const Actor = @This();
const Entity = @import("../entity.zig");
const rl = @import("raylib");
const shapes = @import("../shapes.zig");

ptr: *anyopaque,
impl: *const Interface,

pub const Interface = struct {
    entity: *const fn (ctx: *anyopaque) Entity,
    getHitboxRect: *const fn (ctx: *anyopaque) rl.Rectangle,
    getGridRect: *const fn (ctx: *anyopaque) shapes.IRect,
    setPos: *const fn (ctx: *anyopaque, pos: rl.Vector2) void,
};

pub fn entity(self: *const Actor) Entity {
    return self.impl.entity(self.ptr);
}

pub fn getHitboxRect(self: *const Actor) rl.Rectangle {
    return self.impl.getHitboxRect(self.ptr);
}

pub fn getGridRect(self: *const Actor) shapes.IRect {
    return self.impl.getGridRect(self.ptr);
}

pub fn setPos(self: *const Actor, pos: rl.Vector2) void {
    return self.impl.setPos(self.ptr, pos);
}

pub const Player = @import("player.zig");
pub const Mob = @import("mob.zig");

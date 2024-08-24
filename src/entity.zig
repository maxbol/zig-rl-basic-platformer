const Entity = @This();
const Scene = @import("scene.zig");
const an = @import("animation.zig");
const rl = @import("raylib");

ptr: *anyopaque,
impl: *const Interface,

pub const Interface = struct {
    update: *const fn (ctx: *anyopaque, scene: *Scene, delta_time: f32) an.AnimationBufferError!void,
    draw: *const fn (ctx: *anyopaque, scene: *const Scene) void,
    drawDebug: *const fn (ctx: *anyopaque, scene: *const Scene) void,
};

pub fn update(self: *const Entity, scene: *Scene, delta_time: f32) an.AnimationBufferError!void {
    try self.impl.update(self.ptr, scene, delta_time);
}

pub fn draw(self: *const Entity, scene: *const Scene) void {
    self.impl.draw(self.ptr, scene);
}

pub fn drawDebug(self: *const Entity, scene: *const Scene) void {
    self.impl.drawDebug(self.ptr, scene);
}

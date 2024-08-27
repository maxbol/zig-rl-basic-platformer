const Entity = @This();
const Scene = @import("scene.zig");
const an = @import("animation.zig");
const rl = @import("raylib");

ptr: *anyopaque,
impl: *const Interface,

pub const UpdateError = an.AnimationBufferError;

fn noopUpdate(_: *anyopaque, _: *Scene, _: f32) UpdateError!void {}
fn noopDraw(_: *anyopaque, _: *const Scene) void {}
fn noopDrawDebug(_: *anyopaque, _: *const Scene) void {}

pub const Interface = struct {
    update: *const fn (ctx: *anyopaque, scene: *Scene, delta_time: f32) UpdateError!void = noopUpdate,
    draw: *const fn (ctx: *anyopaque, scene: *const Scene) void = noopDraw,
    drawDebug: *const fn (ctx: *anyopaque, scene: *const Scene) void = noopDrawDebug,
};

pub fn update(self: Entity, scene: *Scene, delta_time: f32) UpdateError!void {
    try self.impl.update(self.ptr, scene, delta_time);
}

pub fn draw(self: Entity, scene: *const Scene) void {
    self.impl.draw(self.ptr, scene);
}

pub fn drawDebug(self: Entity, scene: *const Scene) void {
    self.impl.drawDebug(self.ptr, scene);
}

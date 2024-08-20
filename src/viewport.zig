const rl = @import("raylib");
const Viewport = @This();
const Scene = @import("scene.zig");

rectangle: rl.Rectangle,
pos_normal: rl.Vector2 = undefined,

pub fn init(rectangle: rl.Rectangle) Viewport {
    return .{ .rectangle = rectangle };
}

pub fn update(self: *Viewport, delta_time: f32) void {
    _ = delta_time; // autofix
    self.pos_normal = rl.Vector2.init(self.rectangle.x, self.rectangle.y).normalize();
}

pub fn draw(self: *const Viewport) void {
    rl.drawRectangleLines(@intFromFloat(self.rectangle.x - 1), @intFromFloat(self.rectangle.y - 1), @intFromFloat(self.rectangle.width + 2), @intFromFloat(self.rectangle.height + 2), rl.Color.white);
}

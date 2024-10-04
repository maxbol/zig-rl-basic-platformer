const helpers = @import("helpers.zig");
const rl = @import("raylib");
const Viewport = @This();
const Scene = @import("scene.zig");
const tracing = @import("tracing.zig");

const approach = helpers.approach;

rectangle: rl.Rectangle,
target_rect: rl.Rectangle,

const resize_speed = 400;

pub fn init(rectangle: rl.Rectangle) Viewport {
    return .{ .rectangle = rectangle, .target_rect = rectangle };
}

pub fn update(self: *Viewport, delta_time: f32) void {
    const zone = tracing.ZoneN(@src(), "Viewport Update");
    defer zone.End();

    if (self.target_rect.width != self.rectangle.width or self.target_rect.width != self.rectangle.width) {
        self.rectangle.width = approach(self.rectangle.width, self.target_rect.width, resize_speed * delta_time);
    }

    if (self.target_rect.height != self.rectangle.height) {
        self.rectangle.height = approach(self.rectangle.height, self.target_rect.height, resize_speed * delta_time);
    }
}

pub fn draw(self: *const Viewport) void {
    const zone = tracing.ZoneN(@src(), "Viewport Draw");
    defer zone.End();

    helpers.drawRectBorder(self.rectangle, 1, rl.Color.white);
}

pub fn setTargetRect(self: *Viewport, target_rect: rl.Rectangle) void {
    self.target_rect = target_rect;
}

const rl = @import("raylib");
const std = @import("std");
const Scene = @This();
const Viewport = @import("viewport.zig");
const tl = @import("tiles.zig");
const Sprite = @import("sprite.zig");
const controls = @import("controls.zig");
const debug = @import("debug.zig");

// Initial state
scroll_state: rl.Vector2,
viewport: *Viewport,
layers: []tl.TileLayer,
allocator: std.mem.Allocator,
size: rl.Vector2 = undefined,
sprites: []Sprite = undefined,
gravity_vector: rl.Vector2 = rl.Vector2.init(0, 1),
gravity_force: f32 = 200,

max_x_scroll: f32 = 0,
max_y_scroll: f32 = 0,
viewport_x_offset: f32 = 0,
viewport_y_offset: f32 = 0,
viewport_x_limit: f32 = 0,
viewport_y_limit: f32 = 0,

pub fn create(layers: []tl.TileLayer, viewport: *Viewport, sprites: []Sprite, allocator: std.mem.Allocator) !*Scene {
    const scene = try allocator.create(Scene);

    scene.* = .{
        .layers = layers,
        .scroll_state = rl.Vector2.init(0, 0),
        .viewport = viewport,
        .allocator = allocator,
        .sprites = sprites,
    };

    scene.updateSceneSize();

    return scene;
}

inline fn updateSceneSize(self: *Scene) void {
    var scene_size: rl.Vector2 = .{ .x = 0, .y = 0 };
    for (self.layers) |layer| {
        if (layer.pixel_size.x > scene_size.x) {
            scene_size.x = layer.pixel_size.x;
        }
        if (layer.pixel_size.y > scene_size.y) {
            scene_size.y = layer.pixel_size.y;
        }
    }
    self.size = scene_size;
}

pub fn destroy(self: *Scene) void {
    self.allocator.destroy(self);
}

pub fn update(self: *Scene, delta_time: f32) !void {
    // Do we need to run this every frame? Only if the layers
    // ever get updated, which they don't atm.
    // self.updateSceneSize();

    self.max_x_scroll = @max(self.size.x - self.viewport.rectangle.width, 0);
    self.max_y_scroll = @max(self.size.y - self.viewport.rectangle.height, 0);

    self.viewport_x_offset = @round(self.scroll_state.x * self.max_x_scroll);
    self.viewport_y_offset = @round(self.scroll_state.y * self.max_y_scroll);

    self.viewport_x_limit = self.viewport_x_offset + self.viewport.rectangle.width;
    self.viewport_y_limit = self.viewport_y_offset + self.viewport.rectangle.height;

    for (0..self.layers.len) |i| {
        self.layers[i].update(self, delta_time);
    }

    if (!debug.isPaused()) {
        for (0..self.sprites.len) |i| {
            try self.sprites[i].update(self, delta_time);
        }
    }
}

pub fn draw(self: *const Scene) void {
    for (self.layers) |layer| {
        layer.draw();
    }

    for (self.sprites) |sprite| {
        sprite.draw(self);
    }

    for (self.sprites) |sprite| {
        sprite.drawDebug(self);
    }
}

pub fn drawDebug(self: *const Scene) void {
    if (!debug.isDebugFlagSet(.ShowScrollState)) {
        return;
    }
    var debug_label_buf: [32]u8 = undefined;
    const debug_label = std.fmt.bufPrintZ(&debug_label_buf, "scroll state: {d},{d}", .{ self.scroll_state.x, self.scroll_state.y }) catch {
        std.log.err("Error: failed to format debug label\n", .{});
        return;
    };
    rl.drawText(
        debug_label,
        @intFromFloat(self.viewport.rectangle.x + self.viewport.rectangle.width - 200),
        @intFromFloat(self.viewport.rectangle.y + self.viewport.rectangle.height - 100),
        16,
        rl.Color.red,
    );
}

pub fn getSceneAdjustedPos(self: *const Scene, comptime T: type, pos: T) T {
    var new_pos = pos;

    new_pos.x *= self.size.x;
    new_pos.y *= self.size.y;

    return new_pos;
}

pub fn getViewportAdjustedPos(self: *const Scene, comptime T: type, pos: T) T {
    var new_pos = pos;

    new_pos.x += self.viewport.rectangle.x;
    new_pos.x -= self.viewport_x_offset;

    new_pos.y += self.viewport.rectangle.y;
    new_pos.y -= self.viewport_y_offset;

    return new_pos;
}

pub fn isRectInViewport(self: *const Scene, rect: rl.Rectangle) bool {
    if (rect.x + rect.width < self.viewport_x_offset) {
        return false;
    }

    if (rect.x > self.viewport_x_limit) {
        return false;
    }

    if (rect.y + rect.height < self.viewport_y_offset) {
        return false;
    }

    if (rect.y > self.viewport_y_limit) {
        return false;
    }

    return true;
}

pub fn isPointInViewport(self: *const Scene, point: anytype) bool {
    if (point.x < self.viewport_x_offset) {
        return false;
    }

    if (point.x > self.viewport_x_limit) {
        return false;
    }

    if (point.y < self.viewport_y_offset) {
        return false;
    }

    if (point.y > self.viewport_y_limit) {
        return false;
    }

    return true;
}

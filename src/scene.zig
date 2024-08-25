const Actor = @import("actor.zig");
const Entity = @import("entity.zig");
const Scene = @This();
const Sprite = @import("sprite.zig");
const Viewport = @import("viewport.zig");
const controls = @import("controls.zig");
const debug = @import("debug.zig");
const rl = @import("raylib");
const shapes = @import("shapes.zig");
const std = @import("std");
const tl = @import("tiles.zig");

// Initial state
scroll_state: rl.Vector2,
viewport: *Viewport,
main_layer: tl.TileLayer,
bg_layers: []tl.TileLayer,
fg_layers: []tl.TileLayer,
allocator: std.mem.Allocator,
player: Actor = undefined,
mobs: []Actor = undefined,
gravity: f32 = 13 * 60,

max_x_scroll: f32 = 0,
max_y_scroll: f32 = 0,
viewport_x_offset: f32 = 0,
viewport_y_offset: f32 = 0,
viewport_x_limit: f32 = 0,
viewport_y_limit: f32 = 0,

pub fn create(main_layer: tl.TileLayer, bg_layers: []tl.TileLayer, fg_layers: []tl.TileLayer, viewport: *Viewport, player: Actor, mobs: []Actor, allocator: std.mem.Allocator) !*Scene {
    const scene = try allocator.create(Scene);

    scene.* = .{
        .main_layer = main_layer,
        .bg_layers = bg_layers,
        .fg_layers = fg_layers,
        .scroll_state = rl.Vector2.init(0, 0),
        .viewport = viewport,
        .allocator = allocator,
        .mobs = mobs,
        .player = player,
    };

    return scene;
}

pub fn getPixelSize(self: *const Scene) rl.Vector2 {
    return self.main_layer.getPixelSize();
}

pub fn getGridSize(self: *const Scene) rl.Vector2 {
    return self.main_layer.getSize();
}

pub fn getPlayer(self: *const Scene) Actor {
    return self.player;
}

pub fn getMobs(self: *const Scene) []Actor {
    return self.mobs;
}

pub fn destroy(self: *Scene) void {
    self.allocator.destroy(self);
}

pub fn update(self: *Scene, delta_time: f32) !void {
    const pixel_size = self.main_layer.getPixelSize();
    self.max_x_scroll = @max(pixel_size.x - self.viewport.rectangle.width, 0);
    self.max_y_scroll = @max(pixel_size.y - self.viewport.rectangle.height, 0);

    self.viewport_x_offset = @round(self.scroll_state.x * self.max_x_scroll);
    self.viewport_y_offset = @round(self.scroll_state.y * self.max_y_scroll);

    self.viewport_x_limit = self.viewport_x_offset + self.viewport.rectangle.width;
    self.viewport_y_limit = self.viewport_y_offset + self.viewport.rectangle.height;

    for (0..self.bg_layers.len) |i| {
        try self.bg_layers[i].entity().update(self, delta_time);
    }

    try self.main_layer.entity().update(self, delta_time);

    for (0..self.fg_layers.len) |i| {
        try self.fg_layers[i].entity().update(self, delta_time);
    }

    if (!debug.isPaused()) {
        for (0..self.mobs.len) |i| {
            try self.mobs[i].entity().update(self, delta_time);
        }
    }

    try self.player.entity().update(self, delta_time);
}

pub fn draw(self: *const Scene) void {
    for (self.bg_layers) |layer| {
        layer.entity().draw(self);
    }

    self.main_layer.entity().draw(self);

    for (self.mobs) |actor| {
        actor.entity().draw(self);
    }

    self.player.entity().draw(self);

    for (self.fg_layers) |layer| {
        layer.entity().draw(self);
    }
}

pub fn drawDebug(self: *const Scene) void {
    for (self.bg_layers) |layer| {
        layer.entity().drawDebug(self);
    }

    self.main_layer.entity().drawDebug(self);

    for (self.mobs) |actor| {
        actor.entity().drawDebug(self);
    }

    self.player.entity().drawDebug(self);

    for (self.fg_layers) |layer| {
        layer.entity().drawDebug(self);
    }

    if (!debug.isDebugFlagSet(.ShowScrollState)) {
        return;
    }

    var debug_label_buf: [128]u8 = undefined;
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

    new_pos.x *= self.main_layer.pixel_size.x;
    new_pos.y *= self.main_layer.pixel_size.y;

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

pub fn centerViewportOnPos(self: *Scene, pos: anytype) void {
    self.scroll_state.x = @min(
        @max(
            pos.x - (self.viewport.rectangle.width / 2),
            0,
        ) / self.max_x_scroll,
        self.max_x_scroll,
    );
    self.scroll_state.y = @min(
        @max(
            pos.y - (self.viewport.rectangle.height / 2),
            0,
        ) / self.max_y_scroll,
        self.max_y_scroll,
    );
}

pub fn collideAt(self: *const Scene, rect: shapes.IRect, grid_rect: shapes.IRect) bool {
    return self.main_layer.collideAt(rect, grid_rect);
}

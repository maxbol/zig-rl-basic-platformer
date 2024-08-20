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
gravity_force: f32 = 0.1,

viewport_x_offset: f32 = 0,
viewport_y_offset: f32 = 0,
viewport_x_limit: f32 = 0,
viewport_y_limit: f32 = 0,

pub fn create(layers: []tl.TileLayer, viewport: *Viewport, sprites: []Sprite, allocator: std.mem.Allocator) !*Scene {
    // This does not belong here, temporary solution
    controls.movement_vectors = controls.getMovementVectors();

    const scene = try allocator.create(Scene);

    scene.* = .{
        .layers = layers,
        .scroll_state = rl.Vector2.init(0, 0),
        .viewport = viewport,
        .allocator = allocator,
        .sprites = sprites,
    };

    scene.updateSceneSize();

    for (0..scene.sprites.len) |i| {
        scene.sprites[i].updatePixelPos(scene);
    }

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

    var dir_mask: u4 = @intFromEnum(controls.MovementKeyBitmask.None);

    if (rl.isKeyDown(rl.KeyboardKey.key_w)) {
        dir_mask |= @intFromEnum(controls.MovementKeyBitmask.Up);
    } else if (rl.isKeyDown(rl.KeyboardKey.key_s)) {
        dir_mask |= @intFromEnum(controls.MovementKeyBitmask.Down);
    }

    if (rl.isKeyDown(rl.KeyboardKey.key_a)) {
        dir_mask |= @intFromEnum(controls.MovementKeyBitmask.Left);
    } else if (rl.isKeyDown(rl.KeyboardKey.key_d)) {
        dir_mask |= @intFromEnum(controls.MovementKeyBitmask.Right);
    }

    const dir_vec = controls.movement_vectors[dir_mask];
    const scroll_speed = 0.46;

    if (dir_vec.length() > 0) {
        self.scroll_state = self.scroll_state.add(dir_vec.scale(scroll_speed * delta_time)).clamp(rl.Vector2.init(0, 0), rl.Vector2.init(1, 1));
    }

    const max_x_scroll: f32 = @max(self.size.x - self.viewport.rectangle.width, 0);
    const max_y_scroll: f32 = @max(self.size.y - self.viewport.rectangle.height, 0);

    self.viewport_x_offset = @round(self.scroll_state.x * max_x_scroll);
    self.viewport_y_offset = @round(self.scroll_state.y * max_y_scroll);

    self.viewport_x_limit = self.viewport_x_offset + self.viewport.rectangle.width;
    self.viewport_y_limit = self.viewport_y_offset + self.viewport.rectangle.height;

    for (0..self.sprites.len) |i| {
        self.sprites[i].clearWorldCollisions();
    }

    for (0..self.layers.len) |i| {
        self.layers[i].update(self, delta_time);
    }

    for (0..self.sprites.len) |i| {
        for (self.layers) |layer| {
            self.sprites[i].checkCollisions(layer);
        }
        try self.sprites[i].update(self, delta_time);
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

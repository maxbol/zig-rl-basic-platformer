const Actor = @import("actor/actor.zig");
const Entity = @import("entity.zig");
const Scene = @This();
const Sprite = @import("sprite.zig");
const Viewport = @import("viewport.zig");
const constants = @import("constants.zig");
const debug = @import("debug.zig");
const globals = @import("globals.zig");
const helpers = @import("helpers.zig");
const rl = @import("raylib");
const shapes = @import("shapes.zig");
const std = @import("std");
const TileLayer = @import("tile_layer/tile_layer.zig");

// Initial state
allocator: std.mem.Allocator,
scroll_state: rl.Vector2,
viewport: *Viewport,
main_layer: TileLayer,
bg_layers: std.ArrayList(TileLayer),
fg_layers: std.ArrayList(TileLayer),
player: Actor = undefined,
player_starting_pos: rl.Vector2,
mobs: [constants.MAX_AMOUNT_OF_MOBS]Actor,
mobs_starting_pos: [constants.MAX_AMOUNT_OF_MOBS]rl.Vector2,
mobs_amount: usize,
gravity: f32 = 13 * 60,
first_frame_initialization_done: bool = false,

max_x_scroll: f32 = 0,
max_y_scroll: f32 = 0,
viewport_x_offset: f32 = 0,
viewport_y_offset: f32 = 0,
viewport_x_limit: f32 = 0,
viewport_y_limit: f32 = 0,

pub const data_format_version = 1;

pub fn create(
    allocator: std.mem.Allocator,
    main_layer: TileLayer,
    bg_layers: []const TileLayer,
    fg_layers: []const TileLayer,
    viewport: *Viewport,
    player: Actor,
    player_starting_pos: rl.Vector2,
    mobs: []Actor,
    mobs_starting_pos: []rl.Vector2,
) !*Scene {
    if (mobs.len != mobs_starting_pos.len) {
        std.log.err("Error: mob and mob starting pos count mismatch\n", .{});
        return error.MobStartingPosCountMismatch;
    }
    const mobs_amount = mobs.len;

    var mobs_buf: [constants.MAX_AMOUNT_OF_MOBS]Actor = undefined;
    var mobs_starting_pos_buf: [constants.MAX_AMOUNT_OF_MOBS]rl.Vector2 = undefined;
    std.mem.copyForwards(Actor, &mobs_buf, mobs);
    std.mem.copyForwards(rl.Vector2, &mobs_starting_pos_buf, mobs_starting_pos);

    var bg_layer_list = std.ArrayList(TileLayer).init(allocator);
    var fg_layer_list = std.ArrayList(TileLayer).init(allocator);

    for (bg_layers) |layer| {
        try bg_layer_list.append(layer);
    }

    for (fg_layers) |layer| {
        try fg_layer_list.append(layer);
    }

    const new = try allocator.create(Scene);

    new.* = .{
        .allocator = allocator,
        .main_layer = main_layer,
        .bg_layers = bg_layer_list,
        .fg_layers = fg_layer_list,
        .scroll_state = rl.Vector2.init(0, 0),
        .viewport = viewport,
        .mobs = mobs_buf,
        .mobs_starting_pos = mobs_starting_pos_buf,
        .mobs_amount = mobs_amount,
        .player = player,
        .player_starting_pos = player_starting_pos,
    };

    return new;
}

pub fn destroy(self: *const Scene) void {
    self.main_layer.destroy();
    for (self.bg_layers.items) |layer| {
        layer.destroy();
    }
    for (self.fg_layers.items) |layer| {
        layer.destroy();
    }
    self.allocator.destroy(self);
}

pub fn readBytes(allocator: std.mem.Allocator, reader: anytype) !*Scene {
    // Read version
    const version = try reader.readByte();

    if (version != data_format_version) {
        std.log.err("Error: invalid data format version {d}, expected {d}\n", .{ version, data_format_version });
        return error.InvalidDataFormatVersion;
    }

    // Read number of bg layers
    const bg_layers_len = try reader.readInt(usize, .big);

    // Read number of fg fg_layers
    const fg_layers_len = try reader.readInt(usize, .big);

    // Read main layer
    const main_layer = try TileLayer.readBytes(allocator, reader);

    // Read bg layers
    var bg_layers = std.ArrayList(TileLayer).init(allocator);
    for (0..bg_layers_len) |_| {
        const layer = try TileLayer.readBytes(allocator, reader);
        try bg_layers.append(layer);
    }

    // Read fg layers
    var fg_layers = std.ArrayList(TileLayer).init(allocator);
    for (0..fg_layers_len) |_| {
        const layer = try TileLayer.readBytes(allocator, reader);
        try fg_layers.append(layer);
    }

    // Temp solution: generate mob starting positions from hitbox locations
    var mobs_starting_pos: [constants.MOB_AMOUNT]rl.Vector2 = undefined;
    for (0..constants.MOB_AMOUNT) |i| {
        const x = globals.mobs[i].collidable.hitbox.x;
        const y = globals.mobs[i].collidable.hitbox.y;
        mobs_starting_pos[i] = rl.Vector2.init(x, y);
    }

    return Scene.create(allocator, main_layer, try bg_layers.toOwnedSlice(), try fg_layers.toOwnedSlice(), &globals.viewport, globals.player.actor(), rl.Vector2.init(0, 0), &globals.mob_actors, mobs_starting_pos);
}

pub fn writeBytes(self: *const Scene, writer: anytype) !void {
    // Write version
    try writer.writeByte(data_format_version);

    // Write number of bg layers
    const bg_layers_len: u8 = @intCast(self.bg_layers.items.len);
    try writer.writeInt(usize, bg_layers_len, .big);

    // Write number of fg layers
    const fg_layers_len: u8 = @intCast(self.fg_layers.items.len);
    try writer.writeInt(usize, fg_layers_len, .big);

    // Write main layer
    try self.main_layer.writeBytes(writer.any());

    // Write bg layers
    for (self.bg_layers.items) |layer| {
        try layer.writeBytes(writer.any());
    }

    // Write fg layers
    for (self.fg_layers.items) |layer| {
        try layer.writeBytes(writer.any());
    }
}

pub fn update(self: *Scene, delta_time: f32) !void {
    if (!self.first_frame_initialization_done) {
        self.first_frame_initialization_done = true;
        self.player.setPos(self.player_starting_pos);
    }

    const pixel_size = self.main_layer.getPixelSize();
    self.max_x_scroll = @max(pixel_size.x - self.viewport.rectangle.width, 0);
    self.max_y_scroll = @max(pixel_size.y - self.viewport.rectangle.height, 0);

    self.viewport_x_offset = @round(self.scroll_state.x * self.max_x_scroll);
    self.viewport_y_offset = @round(self.scroll_state.y * self.max_y_scroll);

    self.viewport_x_limit = self.viewport_x_offset + self.viewport.rectangle.width;
    self.viewport_y_limit = self.viewport_y_offset + self.viewport.rectangle.height;

    for (0..self.bg_layers.items.len) |i| {
        try self.bg_layers.items[i].update(self, delta_time);
    }

    try self.main_layer.update(self, delta_time);

    for (0..self.fg_layers.items.len) |i| {
        try self.fg_layers.items[i].update(self, delta_time);
    }

    if (!debug.isPaused()) {
        for (0..self.mobs.len) |i| {
            try self.mobs[i].entity().update(self, delta_time);
        }
    }

    try self.player.entity().update(self, delta_time);
}

pub fn draw(self: *const Scene) void {
    for (self.bg_layers.items) |layer| {
        layer.draw(self);
    }

    self.main_layer.draw(self);

    for (self.mobs) |actor| {
        actor.entity().draw(self);
    }

    self.player.entity().draw(self);

    for (self.fg_layers.items) |layer| {
        layer.draw(self);
    }
}

pub fn drawDebug(self: *const Scene) void {
    for (self.bg_layers.items) |layer| {
        layer.drawDebug(self);
    }

    self.main_layer.drawDebug(self);

    for (self.mobs) |actor| {
        actor.entity().drawDebug(self);
    }

    self.player.entity().drawDebug(self);

    for (self.fg_layers.items) |layer| {
        layer.drawDebug(self);
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

pub fn loadSceneFromFile(allocator: std.mem.Allocator, file_path: []const u8) !*Scene {
    const file = try helpers.openFile(file_path, .{ .mode = .read_only });
    defer file.close();
    return readBytes(allocator, file.reader());
}

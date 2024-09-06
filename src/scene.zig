const Actor = @import("actor/actor.zig");
const Collectable = @import("collectable/collectable.zig");
const Entity = @import("entity.zig");
const Scene = @This();
const Sprite = @import("sprite.zig");
const Tileset = @import("tileset/tileset.zig");
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
player: *Actor.Player = undefined,
player_starting_pos: rl.Vector2,
mobs: [constants.MAX_AMOUNT_OF_MOBS]Actor.Mob,
mobs_starting_pos: [constants.MAX_AMOUNT_OF_MOBS]rl.Vector2,
mobs_amount: usize,
gravity: f32 = 13 * 60,
first_frame_initialization_done: bool = false,
collectables: [constants.MAX_AMOUNT_OF_COLLECTABLES]Collectable = undefined,
collectables_amount: usize,
layer_visibility_treshold: ?i16 = null,

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
    player: *Actor.Player,
    player_starting_pos: rl.Vector2,
    mobs: [constants.MAX_AMOUNT_OF_MOBS]Actor.Mob,
    mobs_starting_pos: [constants.MAX_AMOUNT_OF_MOBS]rl.Vector2,
    mobs_amount: usize,
    collectables: [constants.MAX_AMOUNT_OF_COLLECTABLES]Collectable,
    collectables_amount: usize,
) !*Scene {
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
        .mobs = mobs,
        .mobs_starting_pos = mobs_starting_pos,
        .mobs_amount = mobs_amount,
        .player = player,
        .player_starting_pos = player_starting_pos,
        .collectables_amount = collectables_amount,
        .collectables = collectables,
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

    // Read verbosity
    const verbose = try reader.readByte();
    // const verbose = 0;

    // Read number of bg layers
    if (verbose > 0) try reader.skipBytes(BYTE_NO_BG_LAYERS_HEADER.len, .{});
    const bg_layers_len = try reader.readByte();

    // Read number of fg fg_layers
    if (verbose > 0) try reader.skipBytes(BYTE_NO_FG_LAYERS_HEADER.len, .{});
    const fg_layers_len = try reader.readByte();

    // Read number of mobs
    if (verbose > 0) try reader.skipBytes(BYTE_NO_MOBS_HEADER.len, .{});
    const mob_amount: usize = @intCast(try reader.readInt(u16, .big));

    // Read number of collectables
    if (verbose > 0) try reader.skipBytes(BYTE_NO_COLLECTABLES_HEADER.len, .{});
    const collectables_amount: usize = @intCast(try reader.readInt(u16, .big));

    // Read main layer
    if (verbose > 0) try reader.skipBytes(BYTE_MAIN_LAYER_HEADER.len, .{});
    const main_layer = try TileLayer.readBytes(allocator, reader);

    // Read bg layers
    if (verbose > 0) try reader.skipBytes(BYTE_BG_LAYERS_HEADER.len, .{});
    var bg_layers = std.ArrayList(TileLayer).init(allocator);
    for (0..bg_layers_len) |_| {
        const layer = try TileLayer.readBytes(allocator, reader);
        try bg_layers.append(layer);
    }

    // Read fg layers
    if (verbose > 0) try reader.skipBytes(BYTE_FG_LAYERS_HEADER.len, .{});
    var fg_layers = std.ArrayList(TileLayer).init(allocator);
    for (0..fg_layers_len) |_| {
        const layer = try TileLayer.readBytes(allocator, reader);
        try fg_layers.append(layer);
    }

    // Read mobs
    if (verbose > 0) try reader.skipBytes(BYTE_MOB_HEADER.len, .{});
    var mobs_pos: [constants.MAX_AMOUNT_OF_MOBS]rl.Vector2 = undefined;
    var mobs: [constants.MAX_AMOUNT_OF_MOBS]Actor.Mob = undefined;
    for (0..mob_amount) |i| {
        const mob_type = try reader.readByte();
        const mob_pos_bytes = try reader.readBytesNoEof(8);
        mobs_pos[i] = std.mem.bytesToValue(rl.Vector2, &mob_pos_bytes);
        mobs[i] = try Actor.Mob.initMobByIndex(mob_type, mobs_pos[i]);
    }

    // Read collectables
    if (verbose > 0) try reader.skipBytes(BYTE_COLLECTABLE_HEADER.len, .{});
    var collectables: [constants.MAX_AMOUNT_OF_COLLECTABLES]Collectable = undefined;
    for (0..collectables_amount) |i| {
        const collectable_type = try reader.readByte();
        const collectable_pos_bytes = try reader.readBytesNoEof(8);
        const collectable_pos = std.mem.bytesToValue(rl.Vector2, &collectable_pos_bytes);
        collectables[i] = Collectable.initCollectableByIndex(collectable_type, collectable_pos) catch |err| blk: {
            std.log.err("{d} Error: failed to init collectable by type: {d}: {!}\n", .{ i, collectable_type, err });
            break :blk Collectable.stub();
        };
    }

    return Scene.create(
        allocator,
        main_layer,
        try bg_layers.toOwnedSlice(),
        try fg_layers.toOwnedSlice(),
        &globals.viewport,
        &globals.player,
        rl.Vector2.init(0, 0),
        mobs,
        mobs_pos,
        mob_amount,
        collectables,
        collectables_amount,
    );
}

const BYTE_NO_BG_LAYERS_HEADER = "\nNO_BG_LAYERS\n";
const BYTE_NO_FG_LAYERS_HEADER = "\nNO_FG_LAYERS\n";
const BYTE_NO_MOBS_HEADER = "\nNO_MOBS\n";
const BYTE_NO_COLLECTABLES_HEADER = "\nNO_COLLECTABLES\n";
const BYTE_MAIN_LAYER_HEADER = "\nMAIN_LAYER\n";
const BYTE_BG_LAYERS_HEADER = "\nBG_LAYERS\n";
const BYTE_FG_LAYERS_HEADER = "\nFG_LAYERS\n";
const BYTE_MOB_HEADER = "\nMOBS\n";
const BYTE_COLLECTABLE_HEADER = "\nCOLLECTABLES\n";

pub fn writeBytes(self: *const Scene, writer: anytype, verbose: bool) !void {
    // Write version
    try writer.writeByte(data_format_version);

    // Write verbosity (1 - verbose, 0 - silent)
    try writer.writeByte(if (verbose) 1 else 0);

    // Write n)umber of bg layers
    if (verbose) {
        _ = try writer.write(BYTE_NO_BG_LAYERS_HEADER);
    }
    const bg_layers_len: u8 = @intCast(self.bg_layers.items.len);
    try writer.writeByte(bg_layers_len);

    // Write number of fg layers
    if (verbose) {
        _ = try writer.write(BYTE_NO_FG_LAYERS_HEADER);
    }
    const fg_layers_len: u8 = @intCast(self.fg_layers.items.len);
    try writer.writeByte(fg_layers_len);

    // Write number of mobs
    if (verbose) {
        _ = try writer.write(BYTE_NO_MOBS_HEADER);
    }
    var mobs_amount: u16 = 0;
    for (0..self.mobs_amount) |i| {
        if (!self.mobs[i].is_deleted) {
            mobs_amount += 1;
        }
    }
    try writer.writeInt(u16, mobs_amount, .big);

    // Write number of collectables
    if (verbose) {
        _ = try writer.write(BYTE_NO_COLLECTABLES_HEADER);
    }
    var collectables_amount: u16 = 0;
    for (0..self.collectables_amount) |i| {
        if (!self.collectables[i].is_deleted) {
            collectables_amount += 1;
        }
    }
    try writer.writeInt(u16, collectables_amount, .big);

    // Write main layer
    if (verbose) {
        _ = try writer.write(BYTE_MAIN_LAYER_HEADER);
    }
    try self.main_layer.writeBytes(writer.any());

    // Write bg layers
    if (verbose) {
        _ = try writer.write(BYTE_BG_LAYERS_HEADER);
    }
    for (self.bg_layers.items) |layer| {
        try layer.writeBytes(writer.any());
    }

    // Write fg layers
    if (verbose) {
        _ = try writer.write(BYTE_FG_LAYERS_HEADER);
    }
    for (self.fg_layers.items) |layer| {
        try layer.writeBytes(writer.any());
    }

    // Write mob locations
    if (verbose) {
        _ = try writer.write(BYTE_MOB_HEADER);
    }
    for (0..self.mobs_amount) |i| {
        if (self.mobs[i].is_deleted) {
            continue;
        }

        // Mob type
        try writer.writeByte(0);

        // Mob position
        const mob_pos = self.mobs_starting_pos[i];
        const mob_pos_bytes = std.mem.toBytes(mob_pos);
        _ = try writer.write(&mob_pos_bytes);
    }

    // Write collectible locations
    if (verbose) {
        _ = try writer.write(BYTE_COLLECTABLE_HEADER);
    }
    for (0..self.collectables_amount) |i| {
        if (self.collectables[i].is_deleted) {
            continue;
        }

        // Collectable type
        try writer.writeByte(0);

        // Collectable position
        const collectable_pos = self.collectables[i].getInitialPos();
        const collectable_pos_bytes = std.mem.toBytes(collectable_pos);
        _ = try writer.write(&collectable_pos_bytes);
    }
}

pub fn reset(self: *Scene) void {
    for (0..self.mobs.len) |i| {
        self.mobs[i].reset();
    }

    for (0..self.collectables.len) |i| {
        self.collectables[i].reset();
    }

    self.player.reset();
}

pub fn spawnCollectable(self: *Scene, collectable_type: usize, pos: rl.Vector2) SpawnError!void {
    const collectable: Collectable = try Collectable.initCollectableByIndex(collectable_type, pos);
    self.collectables[self.collectables_amount] = collectable;
    self.collectables_amount += 1;
}

pub fn spawnMob(self: *Scene, mob_type: usize, pos: rl.Vector2) SpawnError!void {
    const mob: Actor.Mob = try Actor.Mob.initMobByIndex(mob_type, pos);

    self.mobs[self.mobs_amount] = mob;
    self.mobs_starting_pos[self.mobs_amount] = pos;
    self.mobs_amount += 1;
}

pub fn removeMob(self: *Scene, mob_idx: usize) void {
    self.mobs[mob_idx].delete();
}

pub fn update(self: *Scene, delta_time: f32) !void {
    if (!self.first_frame_initialization_done) {
        self.first_frame_initialization_done = true;
        self.player.actor().setPos(self.player_starting_pos);
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
        for (0..self.mobs_amount) |i| {
            try self.mobs[i].update(self, delta_time);
        }
    }

    for (0..self.collectables_amount) |i| {
        try self.collectables[i].update(self, delta_time);
    }

    try self.player.entity().update(self, delta_time);
}

pub fn draw(self: *const Scene) void {
    for (self.bg_layers.items, 0..) |layer, i| {
        const layer_mask_index = -@as(i16, @intCast(self.bg_layers.items.len - i));
        if (self.layer_visibility_treshold != null and layer_mask_index > self.layer_visibility_treshold.?) {
            break;
        }
        layer.draw(self);
    }

    if (self.layer_visibility_treshold == null or self.layer_visibility_treshold.? >= 0) {
        self.main_layer.draw(self);
    }

    for (0..self.mobs_amount) |i| {
        self.mobs[i].draw(self);
    }

    for (0..self.collectables_amount) |i| {
        self.collectables[i].draw(self);
    }

    self.player.entity().draw(self);

    for (self.fg_layers.items, 0..) |layer, i| {
        const layer_mask_index: i16 = @intCast(i + 1);
        if (self.layer_visibility_treshold != null and layer_mask_index > self.layer_visibility_treshold.?) {
            break;
        }
        layer.draw(self);
    }
}

pub fn drawDebug(self: *const Scene) void {
    for (self.bg_layers.items) |layer| {
        layer.drawDebug(self);
    }

    self.main_layer.drawDebug(self);

    for (0..self.mobs_amount) |i| {
        self.mobs[i].drawDebug(self);
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
        1,
    );
    self.scroll_state.y = @min(
        @max(
            pos.y - (self.viewport.rectangle.height / 2),
            0,
        ) / self.max_y_scroll,
        1,
    );
}

pub fn collideAt(self: *const Scene, rect: shapes.IRect, grid_rect: shapes.IRect) ?u8 {
    const tile_flags = self.main_layer.collideAt(rect, grid_rect);
    if (tile_flags) |flags| {
        return flags;
    }

    if (rect.x < 0 or rect.y < 0) {
        return @intFromEnum(Tileset.TileFlag.Collidable);
    }

    if (@as(f32, @floatFromInt(rect.x + rect.width)) > self.main_layer.getPixelSize().x or @as(f32, @floatFromInt(rect.y + rect.height)) > self.main_layer.getPixelSize().y) {
        return @intFromEnum(Tileset.TileFlag.Collidable);
    }

    return null;
}

pub fn loadSceneFromFile(allocator: std.mem.Allocator, file_path: []const u8) !*Scene {
    const file = try helpers.openFile(file_path, .{ .mode = .read_only });
    defer file.close();
    return readBytes(allocator, file.reader());
}

pub const SpawnError = error{
    NoSuchItem,
};

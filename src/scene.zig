const Actor = @import("actor/actor.zig");
const Scene = @This();
const Sprite = @import("sprite.zig");
const Solid = @import("solid/solid.zig");
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
viewport: *Viewport,
main_layer: TileLayer,
bg_layers: std.ArrayList(TileLayer),
fg_layers: std.ArrayList(TileLayer),
player: *Actor.Player = undefined,
player_starting_pos: rl.Vector2,
mobs: std.ArrayList(Actor.Mob),
collectables: std.ArrayList(Actor.Collectable),
platforms: std.ArrayList(Solid.Platform),
mystery_boxes: std.ArrayList(Solid.MysteryBox),
gravity: f32 = 13 * 60,
first_frame_initialization_done: bool = false,
layer_visibility_treshold: ?i16 = null,
game_over_screen_elapsed: f32 = -1,

viewport_x_offset: f32 = 0,
viewport_y_offset: f32 = 0,
scroll_state: rl.Vector2 = .{ .x = 0, .y = 0 },
max_x_scroll: f32 = 0,
max_y_scroll: f32 = 0,
viewport_x_limit: f32 = 0,
viewport_y_limit: f32 = 0,

pub const SceneSolidIterator = struct {
    scene: *Scene,
    idx: usize = 0,

    pub fn next(self: *SceneSolidIterator) ?Solid {
        var idx = self.idx;
        if (idx < self.scene.platforms.items.len) {
            for (idx..self.scene.platforms.items.len) |i| {
                self.idx += 1;
                if (!self.scene.platforms.items[i].is_deleted) {
                    return self.scene.platforms.items[i].solid();
                }
            }
        }

        idx -= self.scene.platforms.items.len;

        if (idx < self.scene.mystery_boxes.items.len) {
            for (idx..self.scene.mystery_boxes.items.len) |i| {
                self.idx += 1;
                if (!self.scene.mystery_boxes.items[i].is_deleted) {
                    return self.scene.mystery_boxes.items[i].solid();
                }
            }
        }

        return null;
    }
};

pub const SceneActorIterator = struct {
    scene: *Scene,
    idx: usize = 0,

    pub fn next(self: *SceneActorIterator) ?Actor {
        var idx = self.idx;

        if (idx == 0) {
            self.idx += 1;
            return self.scene.player.actor();
        }

        idx -= 1;

        if (idx < self.scene.mobs.items.len) {
            for (idx..self.scene.mobs.items.len) |i| {
                self.idx += 1;
                if (!self.scene.mobs.items[i].is_deleted and !self.scene.mobs.items[i].is_dead) {
                    return self.scene.mobs.items[i].actor();
                }
            }
        }

        idx -= self.scene.mobs.items.len;

        for (idx..self.scene.collectables.items.len) |i| {
            self.idx += 1;
            if (!self.scene.collectables.items[i].is_deleted and !self.scene.collectables.items[i].is_collected) {
                return self.scene.collectables.items[i].actor();
            }
        }

        return null;
    }
};

pub fn create(
    allocator: std.mem.Allocator,
    main_layer: TileLayer,
    bg_layers: ?std.ArrayList(TileLayer),
    fg_layers: ?std.ArrayList(TileLayer),
    viewport: *Viewport,
    player: *Actor.Player,
    player_starting_pos: rl.Vector2,
    mobs: std.ArrayList(Actor.Mob),
    collectables: std.ArrayList(Actor.Collectable),
    platforms: std.ArrayList(Solid.Platform),
    mystery_boxes: std.ArrayList(Solid.MysteryBox),
) !*Scene {
    const new = try allocator.create(Scene);

    new.* = .{
        .allocator = allocator,
        .main_layer = main_layer,
        .bg_layers = bg_layers orelse std.ArrayList(TileLayer).init(allocator),
        .fg_layers = fg_layers orelse std.ArrayList(TileLayer).init(allocator),
        .viewport = viewport,

        // Actors
        .player = player,
        .player_starting_pos = player_starting_pos,
        .mobs = mobs,
        .collectables = collectables,

        // Solids
        .platforms = platforms,
        .mystery_boxes = mystery_boxes,
    };

    return new;
}

pub fn destroy(self: *const Scene) void {
    self.main_layer.destroy();
    for (self.bg_layers.items) |layer| {
        layer.destroy();
    }
    self.bg_layers.deinit();
    for (self.fg_layers.items) |layer| {
        layer.destroy();
    }
    self.fg_layers.deinit();
    self.mobs.deinit();
    self.collectables.deinit();
    self.platforms.deinit();
    self.mystery_boxes.deinit();
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
    var bg_layers: ?std.ArrayList(TileLayer) = null;
    if (bg_layers_len > 0) {
        bg_layers = std.ArrayList(TileLayer).init(allocator);
        for (0..bg_layers_len) |_| {
            const layer = try TileLayer.readBytes(allocator, reader);
            try bg_layers.?.append(layer);
        }
    }

    // Read fg layers
    if (verbose > 0) try reader.skipBytes(BYTE_FG_LAYERS_HEADER.len, .{});
    var fg_layers: ?std.ArrayList(TileLayer) = null;
    if (fg_layers_len > 0) {
        fg_layers = std.ArrayList(TileLayer).init(allocator);
        for (0..fg_layers_len) |_| {
            const layer = try TileLayer.readBytes(allocator, reader);
            try fg_layers.?.append(layer);
        }
    }

    // Read mobs
    if (verbose > 0) try reader.skipBytes(BYTE_MOB_HEADER.len, .{});
    // var mobs: [constants.MAX_AMOUNT_OF_MOBS]Actor.Mob = undefined;
    var mobs = std.ArrayList(Actor.Mob).init(allocator);
    for (0..mob_amount) |_| {
        const mob_type = try reader.readByte();
        const mob_pos_bytes = try reader.readBytesNoEof(8);
        const mob_pos = std.mem.bytesToValue(rl.Vector2, &mob_pos_bytes);
        try mobs.append(try Actor.Mob.initMobByIndex(mob_type, mob_pos));
    }

    // Read collectables
    if (verbose > 0) try reader.skipBytes(BYTE_COLLECTABLE_HEADER.len, .{});
    var collectables = std.ArrayList(Actor.Collectable).init(allocator);
    for (0..collectables_amount) |i| {
        _ = i; // autofix
        const collectable_type = try reader.readByte();
        const collectable_pos_bytes = try reader.readBytesNoEof(8);
        const collectable_pos = std.mem.bytesToValue(rl.Vector2, &collectable_pos_bytes);
        try collectables.append(try Actor.Collectable.initCollectableByIndex(collectable_type, collectable_pos));
    }

    const platforms = std.ArrayList(Solid.Platform).init(allocator);
    const mystery_boxes = std.ArrayList(Solid.MysteryBox).init(allocator);

    return Scene.create(
        allocator,
        main_layer,
        bg_layers,
        fg_layers,
        &globals.viewport,
        &globals.player,
        rl.Vector2.init(0, 0),
        mobs,
        collectables,
        platforms,
        mystery_boxes,
    );
}

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
    for (0..self.mobs.items.len) |i| {
        if (!self.mobs.items[i].is_deleted) {
            mobs_amount += 1;
        }
    }
    try writer.writeInt(u16, mobs_amount, .big);

    // Write number of collectables
    if (verbose) {
        _ = try writer.write(BYTE_NO_COLLECTABLES_HEADER);
    }
    var collectables_amount: u16 = 0;
    for (0..self.collectables.items.len) |i| {
        if (!self.collectables.items[i].is_deleted) {
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
    for (0..self.mobs.items.len) |i| {
        if (self.mobs.items[i].is_deleted) {
            continue;
        }

        // Mob type
        try writer.writeByte(0);

        // Mob position
        const mob_pos = self.mobs.items[i].getInitialPos();
        const mob_pos_bytes = std.mem.toBytes(mob_pos);
        _ = try writer.write(&mob_pos_bytes);
    }

    // Write collectible locations
    if (verbose) {
        _ = try writer.write(BYTE_COLLECTABLE_HEADER);
    }
    for (0..self.collectables.items.len) |i| {
        if (self.collectables.items[i].is_deleted) {
            continue;
        }

        // Collectable type
        try writer.writeByte(0);

        // Collectable position
        const collectable_pos = self.collectables.items[i].getInitialPos();
        const collectable_pos_bytes = std.mem.toBytes(collectable_pos);
        _ = try writer.write(&collectable_pos_bytes);
    }
}

pub fn reset(self: *Scene) void {
    for (0..self.bg_layers.items.len) |i| {
        self.bg_layers.items[i].setTint(rl.Color.white);
    }

    self.main_layer.setTint(rl.Color.white);

    for (0..self.fg_layers.items.len) |i| {
        self.fg_layers.items[i].setTint(rl.Color.white);
    }

    for (0..self.mobs.items.len) |i| {
        self.mobs.items[i].reset();
    }

    for (0..self.collectables.items.len) |i| {
        self.collectables.items[i].reset();
    }

    self.player.reset();
}

pub fn getActorIterator(self: *Scene) SceneActorIterator {
    return SceneActorIterator{ .scene = self };
}

pub fn getSolidIterator(self: *Scene) SceneSolidIterator {
    return SceneSolidIterator{ .scene = self };
}

pub fn spawnCollectable(self: *Scene, collectable_type: usize, pos: rl.Vector2) !*Actor.Collectable {
    const collectable: Actor.Collectable = try Actor.Collectable.initCollectableByIndex(collectable_type, pos);
    try self.collectables.append(collectable);
    return &self.collectables.items[self.collectables.items.len - 1];
}

pub fn spawnMob(self: *Scene, mob_type: usize, pos: rl.Vector2) !*Actor.Mob {
    const mob: Actor.Mob = try Actor.Mob.initMobByIndex(mob_type, pos);
    try self.mobs.append(mob);
    return &self.mobs.items[self.mobs.items.len - 1];
}

pub fn spawnPlatform(self: *Scene, platform_type: usize, pos: rl.Vector2) !*Solid.Platform {
    const platform: Solid.Platform = try Solid.Platform.initPlatformByIndex(
        platform_type,
        shapes.IPos.fromVec2(pos),
    );
    try self.platforms.append(platform);
    return &self.platforms.items[self.platforms.items.len - 1];
}

pub fn spawnMysteryBox(self: *Scene, mystery_box_type: usize, pos: rl.Vector2) !*Solid.MysteryBox {
    const mystery_box: Solid.MysteryBox = try Solid.MysteryBox.initMysteryBoxByIndex(
        mystery_box_type,
        shapes.IPos.fromVec2(pos),
    );
    try self.mystery_boxes.append(mystery_box);
    return &self.mystery_boxes.items[self.mystery_boxes.items.len - 1];
}

pub fn getGameOverScreenTint(self: *Scene, delta_time: f32) rl.Color {
    self.game_over_screen_elapsed += delta_time;

    const step_len = (255 / game_over_screen_steps);
    const elapsed_quote = @min(
        game_over_screen_duration,
        self.game_over_screen_elapsed,
    ) / game_over_screen_duration;
    const current_step: u8 = @intFromFloat(elapsed_quote * game_over_screen_steps);
    const layer_tint_col = 255 - (current_step * step_len);

    return .{
        .r = layer_tint_col,
        .g = layer_tint_col,
        .b = layer_tint_col,
        .a = 255,
    };
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

    self.scroll_state.x = @min(@max(self.viewport_x_offset / self.max_x_scroll, 0), 1);
    self.scroll_state.y = @min(@max(self.viewport_y_offset / self.max_y_scroll, 0), 1);

    self.viewport_x_limit = self.viewport_x_offset + self.viewport.rectangle.width;
    self.viewport_y_limit = self.viewport_y_offset + self.viewport.rectangle.height;

    var layer_tint: ?rl.Color = null;
    if (self.game_over_screen_elapsed != -1) {
        layer_tint = self.getGameOverScreenTint(delta_time);
    }

    for (0..self.bg_layers.items.len) |i| {
        if (layer_tint) |tint| {
            self.bg_layers.items[i].setTint(tint);
        }
        try self.bg_layers.items[i].update(self, delta_time);
    }

    if (layer_tint) |tint| {
        self.main_layer.setTint(tint);
    }
    try self.main_layer.update(self, delta_time);

    for (0..self.fg_layers.items.len) |i| {
        if (layer_tint) |tint| {
            self.fg_layers.items[i].setTint(tint);
        }
        try self.fg_layers.items[i].update(self, delta_time);
    }

    if (!debug.isPaused()) {
        for (0..self.mobs.items.len) |i| {
            try self.mobs.items[i].update(self, delta_time);
        }

        for (0..self.platforms.items.len) |i| {
            try self.platforms.items[i].update(self, delta_time);
        }

        for (0..self.mystery_boxes.items.len) |i| {
            try self.mystery_boxes.items[i].update(self, delta_time);
        }
    }

    for (0..self.collectables.items.len) |i| {
        try self.collectables.items[i].update(self, delta_time);
    }

    try self.player.update(self, delta_time);

    if (self.game_over_screen_elapsed >= game_over_screen_duration + game_over_screen_delay) {
        // Post game over handler
        self.game_over_screen_elapsed = -1;
        globals.game_over_counter += 1;
        self.reset();
    }
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

    if (self.game_over_screen_elapsed == -1) {
        for (0..self.mobs.items.len) |i| {
            self.mobs.items[i].draw(self);
        }

        for (0..self.collectables.items.len) |i| {
            self.collectables.items[i].draw(self);
        }

        for (0..self.platforms.items.len) |i| {
            self.platforms.items[i].draw(self);
        }

        for (0..self.mystery_boxes.items.len) |i| {
            self.mystery_boxes.items[i].draw(self);
        }
    }

    self.player.draw(self);

    for (self.fg_layers.items, 0..) |layer, i| {
        const layer_mask_index: i16 = @intCast(i + 1);
        if (self.layer_visibility_treshold != null and layer_mask_index > self.layer_visibility_treshold.?) {
            break;
        }
        layer.draw(self);
    }

    // Draw gameover text
    if (self.game_over_screen_elapsed >= game_over_screen_duration) {
        const text = globals.game_over_texts[globals.game_over_counter % globals.game_over_texts.len];
        const game_over_text_x = self.viewport.rectangle.x + (self.viewport.rectangle.width / 2) - 130;
        const game_over_text_y = self.viewport.rectangle.y + (self.viewport.rectangle.height / 2) - 30;
        rl.drawTextEx(globals.font, text, .{ .x = game_over_text_x, .y = game_over_text_y }, 12, 1, rl.Color.white);
    }
}

pub fn drawDebug(self: *const Scene) void {
    for (self.bg_layers.items) |layer| {
        layer.drawDebug(self);
    }

    self.main_layer.drawDebug(self);

    for (0..self.mobs.items.len) |i| {
        self.mobs.items[i].drawDebug(self);
    }

    self.player.drawDebug(self);

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

pub fn setViewportOffset(self: *Scene, viewport_offset: rl.Vector2) void {
    self.viewport_x_offset = viewport_offset.x;
    self.viewport_y_offset = viewport_offset.y;
    self.scroll_state.x = @min(@max(viewport_offset.x / self.max_x_scroll, 0), 1);
    self.scroll_state.y = @min(@max(viewport_offset.y / self.max_y_scroll, 0), 1);
}

pub fn centerViewportOnPos(self: *Scene, pos: anytype) void {
    self.setViewportOffset(.{
        .x = @min(@max(pos.x - (self.viewport.rectangle.width / 2), 0), self.max_x_scroll),
        .y = @min(@max(pos.y - (self.viewport.rectangle.height / 2), 0), self.max_y_scroll),
    });
}

pub const Collision = struct {
    flags: u8,
    solid: ?Solid = null,
};

pub fn collideAt(self: *Scene, rect: shapes.IRect, grid_rect: shapes.IRect) ?Collision {
    // Collide with world tiles
    const tile_flags = self.main_layer.collideAt(rect, grid_rect);
    if (tile_flags) |flags| {
        return .{ .flags = flags };
    }

    // Collide with solids
    var solid_it = self.getSolidIterator();
    while (solid_it.next()) |solid| {
        if (solid.collideAt(rect)) {
            return .{
                .flags = @intFromEnum(Tileset.TileFlag.Collidable),
                .solid = solid,
            };
        }
    }

    // Collide with scene boundary
    if (rect.x < 0 or rect.y < 0) {
        return .{ .flags = @intFromEnum(Tileset.TileFlag.Collidable) };
    }

    if (blk: {
        if (@as(f32, @floatFromInt(rect.x + rect.width)) > self.main_layer.getPixelSize().x) {
            break :blk true;
        }

        if (@as(f32, @floatFromInt(rect.y + rect.height)) > self.main_layer.getPixelSize().y) {
            break :blk true;
        }

        break :blk false;
    }) {
        return .{ .flags = @intFromEnum(Tileset.TileFlag.Collidable) };
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

const BYTE_NO_BG_LAYERS_HEADER = "\nNO_BG_LAYERS\n";
const BYTE_NO_FG_LAYERS_HEADER = "\nNO_FG_LAYERS\n";
const BYTE_NO_MOBS_HEADER = "\nNO_MOBS\n";
const BYTE_NO_COLLECTABLES_HEADER = "\nNO_COLLECTABLES\n";
const BYTE_MAIN_LAYER_HEADER = "\nMAIN_LAYER\n";
const BYTE_BG_LAYERS_HEADER = "\nBG_LAYERS\n";
const BYTE_FG_LAYERS_HEADER = "\nFG_LAYERS\n";
const BYTE_MOB_HEADER = "\nMOBS\n";
const BYTE_COLLECTABLE_HEADER = "\nCOLLECTABLES\n";

pub const data_format_version = 1;
pub const game_over_screen_duration = 1;
pub const game_over_screen_steps = 3;
pub const game_over_screen_delay = 1;

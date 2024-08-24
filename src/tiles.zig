const Entity = @import("entity.zig");
const Scene = @import("scene.zig");
const an = @import("animation.zig");
const co = @import("collisions.zig");
const debug = @import("debug.zig");
const helpers = @import("helpers.zig");
const rl = @import("raylib");
const shapes = @import("shapes.zig");
const std = @import("std");

pub const LayerFlag = enum(u8) {
    NoFlag = 0x00,
    Collidable = 0b00000001,
    InvertXScroll = 0b00000010,
    InvertYScroll = 0b00000100,

    pub fn mask(flags: []const LayerFlag) u8 {
        var result: u8 = 0;
        for (flags) |flag| {
            result |= @intFromEnum(flag);
        }
        return result;
    }
};

pub const Tileset = struct {
    ptr: *anyopaque,
    impl: *const Interface,

    pub const Interface = struct {
        isCollidable: *const fn (ctx: *anyopaque, tile_index: usize) bool,
        drawRect: *const fn (ctx: *anyopaque, tile_index: usize, dest: rl.Vector2, cull_x: f32, cull_y: f32, tint: rl.Color) void,
        getTileSize: *const fn (ctx: *anyopaque) rl.Vector2,
    };

    pub fn isCollidable(self: Tileset, tile_index: usize) bool {
        return self.impl.isCollidable(self.ptr, tile_index);
    }

    pub fn drawRect(self: Tileset, tile_index: usize, dest: rl.Vector2, cull_x: f32, cull_y: f32, tint: rl.Color) void {
        return self.impl.drawRect(self.ptr, tile_index, dest, cull_x, cull_y, tint);
    }

    pub fn getTileSize(self: Tileset) rl.Vector2 {
        return self.impl.getTileSize(self.ptr);
    }
};

pub const TileLayer = struct {
    ptr: *anyopaque,
    impl: *const Interface,

    pub const Interface = struct {
        entity: *const fn (ctx: *anyopaque) Entity,
        getPixelSize: *const fn (ctx: *anyopaque) rl.Vector2,
        getSize: *const fn (ctx: *anyopaque) rl.Vector2,
        getTileset: *const fn (ctx: *anyopaque) Tileset,
        collideAt: *const fn (ctx: *anyopaque, rect: shapes.IRect) bool,
    };

    pub fn entity(self: TileLayer) Entity {
        return self.impl.entity(self.ptr);
    }

    pub fn getPixelSize(self: TileLayer) rl.Vector2 {
        return self.impl.getPixelSize(self.ptr);
    }

    pub fn getSize(self: TileLayer) rl.Vector2 {
        return self.impl.getSize(self.ptr);
    }

    pub fn getTileset(self: TileLayer) Tileset {
        return self.impl.getTileset(self.ptr);
    }

    pub fn collideAt(self: TileLayer, rect: shapes.IRect) bool {
        return self.impl.collideAt(self.ptr, rect);
    }
};

pub fn FixedSizeTileset(size: usize) type {
    return struct {
        texture: rl.Texture2D,
        rect_map: RectMap,
        tile_size: rl.Vector2,
        collision_map: CollisionMap,

        pub const RectMap = [size]?rl.Rectangle;
        pub const CollisionMap = [size]bool;

        pub fn init(tilemap_texture_file: [*:0]const u8, tile_size: rl.Vector2, collision_map: CollisionMap) !@This() {
            const texture = rl.loadTexture(tilemap_texture_file);
            const rect_map = helpers.buildRectMap(size, texture.width, texture.height, tile_size.x, tile_size.y, 1, 1);
            std.log.debug("Tilemap texture loaded, includes {d} tiles", .{rect_map.len});
            return .{ .texture = texture, .tile_size = tile_size, .rect_map = rect_map, .collision_map = collision_map };
        }

        pub fn tileset(self: *@This()) Tileset {
            return Tileset{
                .ptr = self,
                .impl = &.{
                    .isCollidable = isCollidable,
                    .drawRect = drawRect,
                    .getTileSize = getTileSize,
                },
            };
        }

        fn getTileSize(ctx: *anyopaque) rl.Vector2 {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.tile_size;
        }

        fn isCollidable(ctx: *anyopaque, tile_index: usize) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.collision_map[tile_index];
        }

        fn drawRect(ctx: *anyopaque, tile_index: usize, dest: rl.Vector2, cull_x: f32, cull_y: f32, tint: rl.Color) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const src = self.rect_map[tile_index];

            if (src) |rect| {
                const drawn = helpers.culledRectDraw(self.texture, rect, dest, tint, cull_x, cull_y);

                if (debug.isDebugFlagSet(.ShowTilemapDebug)) {
                    const r = drawn[0];
                    const d = drawn[1];

                    var debug_label_buf: [8]u8 = undefined;
                    const debug_label = std.fmt.bufPrintZ(&debug_label_buf, "{d}", .{tile_index}) catch {
                        std.log.err("Error: failed to format debug label\n", .{});
                        return;
                    };
                    rl.drawRectangleLines(@intFromFloat(d.x), @intFromFloat(d.y), @intFromFloat(r.width), @intFromFloat(r.height), rl.Color.red);
                    rl.drawText(debug_label, @intFromFloat(d.x), @intFromFloat(d.y), @intFromFloat(@floor(r.width / 2)), rl.Color.red);
                }
            } else {
                std.log.warn("Warning: tile index {d} not found in tilemap\n", .{tile_index});
            }
        }
    };
}

pub fn FixedSizeTileLayer(comptime size: usize, comptime TilesetType: type) type {
    return struct {
        var id_seq: u8 = 0;

        id: u8,
        size: rl.Vector2,
        pixel_size: rl.Vector2,
        row_size: usize,
        tileset: TilesetType,
        tiles: [size]u8,
        flags: u8,

        // Runtime vars
        scroll_x_tiles: usize = 0,
        scroll_y_tiles: usize = 0,
        sub_tile_scroll_x: f32 = 0,
        sub_tile_scroll_y: f32 = 0,
        include_x_tiles: usize = 0,
        include_y_tiles: usize = 0,
        viewport_x_adjust: f32 = 0,
        viewport_y_adjust: f32 = 0,

        // Debug vars
        tested_tiles: [size]bool = .{false} ** size,
        collided_tiles: [size]bool = .{false} ** size,
        grid_rect: ?shapes.IRect = null,

        pub fn init(layer_size: rl.Vector2, row_size: usize, tileset: TilesetType, tiles: [size]u8, flags: u8) @This() {
            std.debug.assert(layer_size.x > 0);
            std.debug.assert(layer_size.y > 0);

            const id = id_seq;
            id_seq += 1;

            const tile_size = tileset.tile_size;
            const pixel_size = .{ .x = layer_size.x * tile_size.x, .y = layer_size.y * tile_size.y };

            return .{
                .id = id,
                .size = layer_size,
                .pixel_size = pixel_size,
                .row_size = row_size,
                .tileset = tileset,
                .tiles = tiles,
                .flags = flags,
            };
        }

        fn entityCast(ctx: *anyopaque) Entity {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.entity();
        }

        pub fn entity(self: *@This()) Entity {
            return .{
                .ptr = self,
                .impl = &.{
                    .update = update,
                    .draw = draw,
                    .drawDebug = drawDebug,
                },
            };
        }

        pub fn tileLayer(self: *@This()) TileLayer {
            return .{
                .ptr = self,
                .impl = &.{
                    .entity = entityCast,
                    .getPixelSize = getPixelSize,
                    .getSize = getSize,
                    .getTileset = getTileset,
                    .collideAt = collideAt,
                },
            };
        }

        fn getPixelSize(ctx: *anyopaque) rl.Vector2 {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            return self.pixel_size;
        }

        fn getSize(ctx: *anyopaque) rl.Vector2 {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            return self.size;
        }

        fn getTileset(ctx: *anyopaque) Tileset {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.tileset.tileset();
        }

        pub fn getTileFromRowAndCol(self: *const @This(), row_idx: usize, col_idx: usize) ?u8 {
            const tile_idx = row_idx * self.row_size + (col_idx % self.row_size);
            const tile = self.tiles[tile_idx % self.tiles.len];

            if (tile == 0) {
                return null;
            }

            return tile;
        }

        fn update(ctx: *anyopaque, scene: *Scene, delta_time: f32) an.AnimationBufferError!void {
            const self: *@This() = @ptrCast(@alignCast(ctx));

            _ = delta_time; // autofix
            const viewport = scene.viewport;
            const scroll_state = scene.scroll_state;

            const tile_size = self.tileset.tile_size;
            const viewport_rect = viewport.rectangle;

            const max_x_scroll: f32 = @max(self.pixel_size.x - viewport_rect.width, 0);
            const max_y_scroll: f32 = @max(self.pixel_size.y - viewport_rect.height, 0);

            const scroll_state_x = blk: {
                if ((self.flags & @intFromEnum(LayerFlag.InvertXScroll)) > 0) {
                    break :blk 1 - scroll_state.x;
                }
                break :blk scroll_state.x;
            };

            const scroll_state_y = blk: {
                if ((self.flags & @intFromEnum(LayerFlag.InvertYScroll)) > 0) {
                    break :blk 1 - scroll_state.y;
                }
                break :blk scroll_state.y;
            };

            const scroll_x_pixels: f32 = @round(scroll_state_x * max_x_scroll);
            const scroll_y_pixels: f32 = @round(scroll_state_y * max_y_scroll);

            self.scroll_x_tiles = @intFromFloat(@floor(scroll_x_pixels / tile_size.x));
            self.scroll_y_tiles = @intFromFloat(@floor(scroll_y_pixels / tile_size.y));

            self.sub_tile_scroll_x = @mod(scroll_x_pixels, tile_size.x);
            self.sub_tile_scroll_y = @mod(scroll_y_pixels, tile_size.y);

            const viewport_tile_size_x: usize = @intFromFloat(@floor(viewport_rect.width / tile_size.x));
            const viewport_tile_size_y: usize = @intFromFloat(@floor(viewport_rect.height / tile_size.y));

            self.include_x_tiles = self.scroll_x_tiles + viewport_tile_size_x;
            self.include_y_tiles = self.scroll_y_tiles + viewport_tile_size_y;

            self.viewport_x_adjust = viewport_rect.x;
            self.viewport_y_adjust = viewport_rect.y;

            // if (debug.isDebugFlagSet(.ShowTestedTiles)) {
            //     self.tested_tiles = .{false} ** size;
            // }
            //
            // if (debug.isDebugFlagSet(.ShowCollidedTiles)) {
            //     self.collided_tiles = .{false} ** size;
            // }
            //

            self.tested_tiles = .{false} ** size;
            self.collided_tiles = .{false} ** size;
        }

        fn draw(ctx: *anyopaque, _: *const Scene) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));

            const tile_size = self.tileset.tile_size;

            for (self.scroll_y_tiles..self.include_y_tiles + 1) |row_idx| {
                for (self.scroll_x_tiles..self.include_x_tiles + 1) |col_idx| {
                    const tile_idx = row_idx * self.row_size + (col_idx % self.row_size);

                    const tile = self.tiles[tile_idx % self.tiles.len];

                    if (tile == 0) {
                        continue;
                    }

                    const row_offset: f32 = @floatFromInt(row_idx - self.scroll_y_tiles);
                    const col_offset: f32 = @floatFromInt(col_idx - self.scroll_x_tiles);

                    var cull_x: f32 = 0;
                    var cull_y: f32 = 0;

                    if (col_idx == self.scroll_x_tiles) {
                        cull_x = self.sub_tile_scroll_x;
                    } else if (col_idx == self.include_x_tiles) {
                        cull_x = -(tile_size.x - self.sub_tile_scroll_x);
                    }

                    if (row_idx == self.scroll_y_tiles) {
                        cull_y = self.sub_tile_scroll_y;
                    } else if (row_idx == self.include_y_tiles) {
                        cull_y = -(tile_size.y - self.sub_tile_scroll_y);
                    }

                    const dest_x: f32 = self.viewport_x_adjust + col_offset * tile_size.x - self.sub_tile_scroll_x;
                    const dest_y: f32 = self.viewport_y_adjust + row_offset * tile_size.y - self.sub_tile_scroll_y;
                    const dest = rl.Vector2.init(dest_x, dest_y);

                    self.tileset.tileset().drawRect(tile, dest, cull_x, cull_y, rl.Color.white);
                }
            }
        }

        fn drawDebug(ctx: *anyopaque, scene: *const Scene) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));

            if (!debug.isDebugFlagSet(.ShowCollidedTiles) and !debug.isDebugFlagSet(.ShowTestedTiles)) {
                return;
            }

            if (self.grid_rect) |grid_rect| {
                const rect = helpers.getPixelRect(getTileset(ctx).getTileSize(), grid_rect.toRect());
                const grid_rect_adjusted = scene.getViewportAdjustedPos(rl.Rectangle, rect);
                std.debug.print("grid_rect={d} {d} {d} {d}\n", .{ grid_rect.x, grid_rect.y, grid_rect.width, grid_rect.height });
                std.debug.print("grid_rect_adjusted = {d} {d} {d} {d}\n", .{ grid_rect_adjusted.x, grid_rect_adjusted.y, grid_rect_adjusted.width, grid_rect_adjusted.height });
                rl.drawRectangleLinesEx(grid_rect_adjusted, 1, rl.Color.brown);
            }

            for (self.scroll_y_tiles..self.include_y_tiles + 1) |row_idx| {
                for (self.scroll_x_tiles..self.include_x_tiles + 1) |col_idx| {
                    const tile_idx = row_idx * self.row_size + (col_idx % self.row_size);

                    const tile_rect: rl.Rectangle = scene.getViewportAdjustedPos(
                        rl.Rectangle,
                        helpers.getPixelPos(self.tileset.tile_size, rl.Rectangle{
                            .x = @floatFromInt(col_idx),
                            .y = @floatFromInt(row_idx),
                            .width = self.tileset.tile_size.x,
                            .height = self.tileset.tile_size.y,
                        }),
                    );
                    if (debug.isDebugFlagSet(.ShowCollidedTiles) and self.collided_tiles[tile_idx] == true) {
                        rl.drawRectangleRec(tile_rect, rl.Color.green.alpha(0.5));
                    } else if (debug.isDebugFlagSet(.ShowTestedTiles) and self.tested_tiles[tile_idx] == true) {
                        rl.drawRectangleRec(tile_rect, rl.Color.red.alpha(0.5));
                    }
                }
            }
        }

        fn collideAt(ctx: *anyopaque, rect: shapes.IRect) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));

            const tile_size = shapes.IPos.fromVec2(self.tileset.tile_size);
            const grid_rect: shapes.IRect = helpers.getGridRect(tile_size, rect);

            self.grid_rect = grid_rect;

            for (@intCast(@max(0, grid_rect.y - 2))..@intCast(@max(0, grid_rect.y + 2))) |row_idx| {
                for (@intCast(@max(0, grid_rect.x - 2))..@intCast(@max(0, grid_rect.x + 2))) |col_idx| {
                    const tile = self.getTileFromRowAndCol(row_idx, col_idx) orelse continue;

                    if (!self.tileset.tileset().isCollidable(tile)) {
                        continue;
                    }

                    const tile_rect: shapes.IRect = helpers.getPixelPos(tile_size, shapes.IRect{
                        .x = @intCast(col_idx),
                        .y = @intCast(row_idx),
                        .width = tile_size.x,
                        .height = tile_size.y,
                    });

                    const is_colliding = rect.isColliding(tile_rect);

                    if (debug.isDebugFlagSet(.ShowTestedTiles) or debug.isDebugFlagSet(.ShowCollidedTiles)) {
                        const tile_idx = row_idx * self.row_size + (col_idx % self.row_size);

                        if (debug.isDebugFlagSet(.ShowTestedTiles)) {
                            self.tested_tiles[tile_idx] = true;
                        }

                        if (debug.isDebugFlagSet(.ShowCollidedTiles) and is_colliding) {
                            self.collided_tiles[tile_idx] = true;
                        }
                    }

                    if (is_colliding) {
                        return true;
                    }
                }
            }

            return false;
        }
    };
}

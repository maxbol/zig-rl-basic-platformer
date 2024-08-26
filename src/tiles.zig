const Entity = @import("entity.zig");
const Scene = @import("scene.zig");
const Scrollable = @import("scrollable.zig");
const an = @import("animation.zig");
const co = @import("collisions.zig");
const constants = @import("constants.zig");
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
        getRect: *const fn (ctx: *anyopaque, tile_index: usize) ?rl.Rectangle,
        getRectMap: *const fn (ctx: *anyopaque) []?rl.Rectangle,
        getTexture: *const fn (ctx: *anyopaque) rl.Texture2D,
        getTileSize: *const fn (ctx: *anyopaque) rl.Vector2,
        isCollidable: *const fn (ctx: *anyopaque, tile_index: usize) bool,
    };

    pub fn getRectMap(self: Tileset) []?rl.Rectangle {
        return self.impl.getRectMap(self.ptr);
    }

    pub fn getTexture(self: Tileset) rl.Texture2D {
        return self.impl.getTexture(self.ptr);
    }

    pub fn isCollidable(self: Tileset, tile_index: usize) bool {
        return self.impl.isCollidable(self.ptr, tile_index);
    }

    pub fn getTileSize(self: Tileset) rl.Vector2 {
        return self.impl.getTileSize(self.ptr);
    }

    pub fn drawEditor(self: Tileset) void {
        const EDITOR_COLS_PER_ROW = 7;
        const EDITOR_X = constants.GAME_SIZE_X - (constants.TILE_SIZE * 7) - constants.VIEWPORT_PADDING_X;
        const EDITOR_Y = constants.VIEWPORT_PADDING_Y;
        const EDITOR_WIDTH = constants.TILE_SIZE * EDITOR_COLS_PER_ROW;
        const EDITOR_HEIGHT = constants.TILE_SIZE * 10;

        const editor_rect = rl.Rectangle.init(EDITOR_X, EDITOR_Y, EDITOR_WIDTH, EDITOR_HEIGHT);

        rl.drawRectangleLinesEx(editor_rect, 2, rl.Color.white);

        for (self.getRectMap(), 0..) |tile_rect, idx| {
            if (tile_rect) |rect| {
                const x: f32 = @floatFromInt(EDITOR_X + (idx % EDITOR_COLS_PER_ROW) * constants.TILE_SIZE);
                const y: f32 = @floatFromInt(EDITOR_Y + @divFloor(idx, EDITOR_COLS_PER_ROW) * constants.TILE_SIZE);

                const dest = rl.Vector2.init(x, y);

                rl.drawTextureRec(self.getTexture(), rect, dest, rl.Color.white);
            }
        }
    }

    pub fn getRect(self: Tileset, tile_idx: usize) ?rl.Rectangle {
        return self.impl.getRect(self.ptr, tile_idx);
    }

    pub fn drawRect(self: Tileset, tile_index: usize, dest: rl.Vector2, cull_x: f32, cull_y: f32, tint: rl.Color) void {
        const rect = self.getRect(tile_index) orelse {
            std.log.warn("Warning: tile index {d} not found in tilemap\n", .{tile_index});
            return;
        };

        const drawn = helpers.culledRectDraw(self.getTexture(), rect, dest, tint, cull_x, cull_y);

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
    }
};

pub const TileLayer = struct {
    ptr: *anyopaque,
    impl: *const Interface,

    pub const Interface = struct {
        didCollideThisFrame: *const fn (ctx: *anyopaque, tile_idx: usize) bool,
        getFlags: *const fn (ctx: *anyopaque) u8,
        getPixelSize: *const fn (ctx: *anyopaque) rl.Vector2,
        getScrollState: *const fn (ctx: *anyopaque) *const Scrollable,
        getSize: *const fn (ctx: *anyopaque) rl.Vector2,
        getTileFromRowAndCol: *const fn (ctx: *anyopaque, row_idx: usize, col_idx: usize) ?u8,
        getTileIdxFromRowAndCol: *const fn (ctx: *anyopaque, row_idx: usize, col_idx: usize) usize,
        getTileset: *const fn (ctx: *anyopaque) Tileset,
        storeCollisionData: *const fn (ctx: *anyopaque, tile_idx: usize, did_collide: bool) void,
        update: *const fn (ctx: *anyopaque, scene: *Scene, delta_time: f32) Entity.EntityUpdateError!void,
        wasTestedThisFrame: *const fn (ctx: *anyopaque, tile_idx: usize) bool,
    };

    pub fn entity(self: TileLayer) Entity {
        // Copy pointer data to allow mutability
        var copy = self;

        return .{
            .ptr = &copy,
            .impl = &.{
                .update = update,
                .draw = draw,
                .drawDebug = drawDebug,
            },
        };
    }

    pub fn getFlags(self: TileLayer) u8 {
        return self.impl.getFlags(self.ptr);
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

    pub fn getTileIdxFromRowAndCol(self: TileLayer, row_idx: usize, col_idx: usize) usize {
        return self.impl.getTileIdxFromRowAndCol(self.ptr, row_idx, col_idx);
    }

    pub fn getTileFromRowAndCol(self: TileLayer, row_idx: usize, col_idx: usize) ?u8 {
        return self.impl.getTileFromRowAndCol(self.ptr, row_idx, col_idx);
    }

    pub fn getScrollState(self: TileLayer) *const Scrollable {
        return self.impl.getScrollState(self.ptr);
    }

    pub fn update(ctx: *anyopaque, scene: *Scene, delta_time: f32) Entity.EntityUpdateError!void {
        const self: *TileLayer = @ptrCast(@alignCast(ctx));
        return self.impl.update(self.ptr, scene, delta_time);
    }

    pub fn draw(ctx: *anyopaque, _: *const Scene) void {
        const self: *TileLayer = @ptrCast(@alignCast(ctx));
        return drawTileLayer(self);
    }

    pub fn drawDebug(ctx: *anyopaque, scene: *const Scene) void {
        const self: *TileLayer = @ptrCast(@alignCast(ctx));
        return drawDebugTileLayer(self, scene);
    }

    pub fn collideAt(self: TileLayer, rect: shapes.IRect, grid_rect: shapes.IRect) bool {
        return collideTileLayerAt(self, rect, grid_rect);
    }

    pub fn storeCollisionData(self: TileLayer, tile_idx: usize, did_collide: bool) void {
        return self.impl.storeCollisionData(self.ptr, tile_idx, did_collide);
    }

    pub fn didCollideThisFrame(self: TileLayer, tile_idx: usize) bool {
        return self.impl.didCollideThisFrame(self.ptr, tile_idx);
    }

    pub fn wasTestedThisFrame(self: TileLayer, tile_idx: usize) bool {
        return self.impl.wasTestedThisFrame(self.ptr, tile_idx);
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
                    .getTexture = getTexture,
                    .getRect = getRect,
                    .getRectMap = getRectMap,
                    .getTileSize = getTileSize,
                    .isCollidable = isCollidable,
                },
            };
        }

        fn getTexture(ctx: *anyopaque) rl.Texture2D {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.texture;
        }

        fn getRect(ctx: *anyopaque, tile_idx: usize) ?rl.Rectangle {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.rect_map[tile_idx];
        }

        fn getRectMap(ctx: *anyopaque) []?rl.Rectangle {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return &self.rect_map;
        }

        fn getTileSize(ctx: *anyopaque) rl.Vector2 {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.tile_size;
        }

        fn isCollidable(ctx: *anyopaque, tile_index: usize) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.collision_map[tile_index];
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
        scrollable: Scrollable,

        // Debug vars
        tested_tiles: [size]bool = .{false} ** size,
        collided_tiles: [size]bool = .{false} ** size,

        pub fn init(layer_size: rl.Vector2, row_size: usize, tileset: TilesetType, tiles: [size]u8, flags: u8) @This() {
            std.debug.assert(layer_size.x > 0);
            std.debug.assert(layer_size.y > 0);

            const id = id_seq;
            id_seq += 1;

            const tile_size = tileset.tile_size;
            const pixel_size = .{ .x = layer_size.x * tile_size.x, .y = layer_size.y * tile_size.y };

            return .{ .id = id, .size = layer_size, .pixel_size = pixel_size, .row_size = row_size, .tileset = tileset, .tiles = tiles, .flags = flags, .scrollable = Scrollable{} };
        }

        pub fn entity(self: *@This()) Entity {
            return self.tileLayer().entity();
        }

        pub fn tileLayer(self: *@This()) TileLayer {
            return .{
                .ptr = self,
                .impl = &.{
                    .didCollideThisFrame = didCollideThisFrame,
                    .getFlags = getFlags,
                    .getPixelSize = getPixelSize,
                    .getSize = getSize,
                    .getScrollState = getScrollState,
                    .getTileset = getTileset,
                    .getTileIdxFromRowAndCol = getTileIdxFromRowAndCol,
                    .getTileFromRowAndCol = getTileFromRowAndCol,
                    .storeCollisionData = storeCollisionData,
                    .update = update,
                    .wasTestedThisFrame = wasTestedThisFrame,
                },
            };
        }

        fn didCollideThisFrame(ctx: *anyopaque, tile_idx: usize) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.collided_tiles[tile_idx];
        }

        fn getFlags(ctx: *anyopaque) u8 {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            return self.flags;
        }

        fn getPixelSize(ctx: *anyopaque) rl.Vector2 {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            return self.pixel_size;
        }

        fn getSize(ctx: *anyopaque) rl.Vector2 {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            return self.size;
        }

        fn getScrollState(ctx: *anyopaque) *const Scrollable {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            return &self.scrollable;
        }

        fn getTileset(ctx: *anyopaque) Tileset {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.tileset.tileset();
        }

        fn getTileIdxFromRowAndCol(ctx: *anyopaque, row_idx: usize, col_idx: usize) usize {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return row_idx * self.row_size + (col_idx % self.row_size);
        }

        fn getTileFromRowAndCol(ctx: *anyopaque, row_idx: usize, col_idx: usize) ?u8 {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const tile_idx = getTileIdxFromRowAndCol(ctx, row_idx, col_idx);

            if (tile_idx >= self.tiles.len) {
                std.log.warn("Warning: tile index {d} out of bounds\n", .{tile_idx});
                return null;
            }

            const tile = self.tiles[tile_idx % self.tiles.len];

            if (tile == 0) {
                return null;
            }

            return tile;
        }

        fn storeCollisionData(ctx: *anyopaque, tile_idx: usize, did_collide: bool) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));

            if (debug.isDebugFlagSet(.ShowTestedTiles) or debug.isDebugFlagSet(.ShowCollidedTiles)) {
                if (debug.isDebugFlagSet(.ShowTestedTiles)) {
                    self.tested_tiles[tile_idx] = true;
                }

                if (debug.isDebugFlagSet(.ShowCollidedTiles) and did_collide) {
                    self.collided_tiles[tile_idx] = true;
                }
            }
        }

        fn update(ctx: *anyopaque, scene: *Scene, delta_time: f32) Entity.EntityUpdateError!void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            try self.scrollable.update(scene, self.tileLayer(), delta_time);
        }

        fn wasTestedThisFrame(ctx: *anyopaque, tile_idx: usize) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.tested_tiles[tile_idx];
        }
    };
}

fn drawTileLayer(layer: *TileLayer) void {
    const tileset = layer.getTileset();
    const tile_size = tileset.getTileSize();
    const scrollable = layer.getScrollState();

    for (scrollable.scroll_y_tiles..scrollable.include_y_tiles + 1) |row_idx| {
        for (scrollable.scroll_x_tiles..scrollable.include_x_tiles + 1) |col_idx| {
            const tile = layer.getTileFromRowAndCol(row_idx, col_idx) orelse continue;

            const row_offset: f32 = @floatFromInt(row_idx - scrollable.scroll_y_tiles);
            const col_offset: f32 = @floatFromInt(col_idx - scrollable.scroll_x_tiles);

            var cull_x: f32 = 0;
            var cull_y: f32 = 0;

            if (col_idx == scrollable.scroll_x_tiles) {
                cull_x = scrollable.sub_tile_scroll_x;
            } else if (col_idx == scrollable.include_x_tiles) {
                cull_x = -(tile_size.x - scrollable.sub_tile_scroll_x);
            }

            if (row_idx == scrollable.scroll_y_tiles) {
                cull_y = scrollable.sub_tile_scroll_y;
            } else if (row_idx == scrollable.include_y_tiles) {
                cull_y = -(tile_size.y - scrollable.sub_tile_scroll_y);
            }

            const dest_x: f32 = scrollable.viewport_x_adjust + col_offset * tile_size.x - scrollable.sub_tile_scroll_x;
            const dest_y: f32 = scrollable.viewport_y_adjust + row_offset * tile_size.y - scrollable.sub_tile_scroll_y;
            const dest = rl.Vector2.init(dest_x, dest_y);

            tileset.drawRect(tile, dest, cull_x, cull_y, rl.Color.white);
        }
    }
}

fn drawDebugTileLayer(layer: *TileLayer, scene: *const Scene) void {
    if (!debug.isDebugFlagSet(.ShowCollidedTiles) and !debug.isDebugFlagSet(.ShowTestedTiles)) {
        return;
    }

    const scrollable = layer.getScrollState();
    const tileset = layer.getTileset();

    for (scrollable.scroll_y_tiles..scrollable.include_y_tiles + 1) |row_idx| {
        for (scrollable.scroll_x_tiles..scrollable.include_x_tiles + 1) |col_idx| {
            const tile_idx = layer.getTileIdxFromRowAndCol(row_idx, col_idx);

            const tile_rect: rl.Rectangle = scene.getViewportAdjustedPos(
                rl.Rectangle,
                helpers.getPixelRect(tileset.getTileSize(), rl.Rectangle{
                    .x = @floatFromInt(col_idx),
                    .y = @floatFromInt(row_idx),
                    .width = 1,
                    .height = 1,
                }),
            );

            if (debug.isDebugFlagSet(.ShowCollidedTiles) and layer.didCollideThisFrame(tile_idx)) {
                rl.drawRectangleRec(tile_rect, rl.Color.green.alpha(0.5));
            } else if (debug.isDebugFlagSet(.ShowTestedTiles) and layer.wasTestedThisFrame(tile_idx)) {
                rl.drawRectangleRec(tile_rect, rl.Color.red.alpha(0.5));
            }
        }
    }
}

fn collideTileLayerAt(layer: TileLayer, rect: shapes.IRect, grid_rect: shapes.IRect) bool {
    const tileset = layer.getTileset();
    const tile_size = shapes.IPos.fromVec2(tileset.getTileSize());

    const min_row: usize = @intCast(@max(0, grid_rect.y - 1));
    const max_row: usize = @intCast(@max(0, grid_rect.y + grid_rect.height + 1));

    const min_col: usize = @intCast(@max(0, grid_rect.x - 1));
    const max_col: usize = @intCast(@max(0, grid_rect.x + grid_rect.width + 1));

    for (min_row..max_row) |row_idx| {
        for (min_col..max_col) |col_idx| {
            const tile_idx = layer.getTileIdxFromRowAndCol(row_idx, col_idx);
            const tile = layer.getTileFromRowAndCol(row_idx, col_idx) orelse continue;

            if (!tileset.isCollidable(tile)) {
                continue;
            }

            const tile_rect: shapes.IRect = helpers.getPixelPos(tile_size, shapes.IRect{
                .x = @intCast(col_idx),
                .y = @intCast(row_idx),
                .width = tile_size.x,
                .height = tile_size.y,
            });

            const is_colliding = rect.isColliding(tile_rect);

            layer.storeCollisionData(tile_idx, is_colliding);

            if (is_colliding) {
                return true;
            }
        }
    }

    return false;
}

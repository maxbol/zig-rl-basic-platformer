const Entity = @import("../entity.zig");
const Scene = @import("../scene.zig");
const Scrollable = @import("scrollable.zig");
const TileLayer = @import("tile_layer.zig");
const Tileset = @import("../tileset/tileset.zig");
const debug = @import("../debug.zig");
const rl = @import("raylib");
const std = @import("std");

pub fn FixedSizeTileLayer(comptime size: usize, comptime TilesetType: type) type {
    return struct {
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

            const tile_size = tileset.tile_size;
            const pixel_size = .{ .x = layer_size.x * tile_size.x, .y = layer_size.y * tile_size.y };

            return .{
                .size = layer_size,
                .pixel_size = pixel_size,
                .row_size = row_size,
                .tileset = tileset,
                .tiles = tiles,
                .flags = flags,
                .scrollable = Scrollable{},
            };
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
                    .writeTile = writeTile,
                },
            };
        }

        fn didCollideThisFrame(ctx: *anyopaque, tile_idx: usize) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (tile_idx >= self.collided_tiles.len) {
                // std.log.warn("Warning: tile index {d} out of bounds\n", .{tile_idx});
                return false;
            }
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
                // std.log.warn("Warning: tile index {d} out of bounds\n", .{tile_idx});
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

        fn update(ctx: *anyopaque, scene: *Scene, _: f32) Entity.UpdateError!void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            try self.scrollable.update(scene, self.tileLayer());
        }

        fn wasTestedThisFrame(ctx: *anyopaque, tile_idx: usize) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (tile_idx >= self.tested_tiles.len) {
                // std.log.warn("Warning: tile index {d} out of bounds\n", .{tile_idx});
                return false;
            }
            return self.tested_tiles[tile_idx];
        }

        fn writeTile(ctx: *anyopaque, tile_idx: usize, tile: u8) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (tile_idx > self.tiles.len) {
                std.log.warn("Tried out of bounds write of tile to position {d}. Failed.", .{tile_idx});
            }
            self.tiles[tile_idx] = tile;
        }
    };
}

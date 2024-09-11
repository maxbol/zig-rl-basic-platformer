const Scene = @import("../scene.zig");
const Scrollable = @import("scrollable.zig");
const TileLayer = @import("tile_layer.zig");
const Tileset = @import("../tileset/tileset.zig");
const debug = @import("../debug.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");
const std = @import("std");

pub fn FixedSizeTileLayer(comptime size: usize) type {
    return struct {
        allocator: std.mem.Allocator,
        size: rl.Vector2,
        pixel_size: rl.Vector2,
        row_size: usize,
        tileset: Tileset,
        tiles: [size]u8,
        flags: u8,
        scrollable: Scrollable,
        tileset_path_buf: [3 * 1024]u8 = undefined,
        tileset_path_len: u16,

        // Debug vars
        tested_tiles: [size]bool = .{false} ** size,
        collided_tiles: [size]bool = .{false} ** size,

        pub const data_format_version = 1;

        pub fn create(allocator: std.mem.Allocator, layer_size: rl.Vector2, row_size: usize, tileset_path: []const u8, tiles: []u8, flags: u8) !*@This() {
            std.debug.assert(layer_size.x > 0);
            std.debug.assert(layer_size.y > 0);

            if (tiles.len > size) {
                std.log.err("Tile data size {d} exceeds maximum size {d}\n", .{ tiles.len, size });
                return error.LayerTooBig;
            }

            const new = try allocator.create(@This());

            const tileset = try Tileset.loadTilesetFromFile(allocator, tileset_path);

            var tileset_path_buf: [3 * 1024]u8 = undefined;
            std.mem.copyForwards(u8, &tileset_path_buf, tileset_path);

            const tileset_path_len: u16 = @intCast(tileset_path.len);

            const tile_size = tileset.getTileSize();
            const pixel_size = .{ .x = layer_size.x * tile_size.x, .y = layer_size.y * tile_size.y };

            var tile_data: [size]u8 = undefined;
            std.mem.copyForwards(u8, &tile_data, tiles);

            new.* = .{
                .allocator = allocator,
                .size = layer_size,
                .pixel_size = pixel_size,
                .row_size = row_size,
                .tileset = tileset,
                .tiles = tile_data,
                .flags = flags,
                .scrollable = Scrollable{},
                .tileset_path_buf = tileset_path_buf,
                .tileset_path_len = tileset_path_len,
            };

            return new;
        }

        fn destroy(ctx: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.tileset.destroy();
            self.allocator.destroy(self);
        }

        pub fn writeBytes(ctx: *anyopaque, writer: std.io.AnyWriter) !void {
            const self: *@This() = @ptrCast(@alignCast(ctx));

            // Write version byte
            writer.writeByte(data_format_version) catch {
                return error.WriteError;
            };

            // Write flags
            writer.writeByte(self.flags) catch {
                return error.WriteError;
            };

            // Write tile data size
            writer.writeInt(usize, size, .big) catch {
                return error.WriteError;
            };

            // Write layer size
            const size_bytes: [8]u8 = std.mem.toBytes(self.size);
            _ = writer.write(&size_bytes) catch {
                return error.WriteError;
            };

            // Write row size
            const row_size: u16 = @intCast(self.row_size);
            const row_size_bytes: [2]u8 = std.mem.toBytes(row_size);
            _ = writer.write(&row_size_bytes) catch {
                return error.WriteError;
            };

            // Write tileset file path length
            const len_bytes: [2]u8 = std.mem.toBytes(self.tileset_path_len);
            _ = writer.write(&len_bytes) catch {
                return error.WriteError;
            };

            // Write tileset file path
            const tileset_path = self.tileset_path_buf[0..self.tileset_path_len];
            _ = writer.write(tileset_path) catch {
                return error.WriteError;
            };

            // Write tiles
            _ = writer.write(&self.tiles) catch {
                return error.WriteError;
            };
        }

        pub fn tileLayer(self: *@This()) TileLayer {
            return .{
                .ptr = self,
                .impl = &.{
                    .destroy = destroy,
                    .didCollideThisFrame = didCollideThisFrame,
                    .getFlags = getFlags,
                    .getPixelSize = getPixelSize,
                    .getLayerPosition = getLayerPosition,
                    .getRowSize = getRowSize,
                    .getSize = getSize,
                    .getScrollState = getScrollState,
                    .getTileset = getTileset,
                    .getTileIdxFromRowAndCol = getTileIdxFromRowAndCol,
                    .getTileFromRowAndCol = getTileFromRowAndCol,
                    .resizeLayer = resizeLayer,
                    .storeCollisionData = storeCollisionData,
                    .update = update,
                    .wasTestedThisFrame = wasTestedThisFrame,
                    .writeBytes = writeBytes,
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

        fn getLayerPosition(ctx: *anyopaque, pos: rl.Vector2) rl.Vector2 {
            const self: *const @This() = @ptrCast(@alignCast(ctx));

            var layer_pos = pos;
            layer_pos.x += self.scrollable.scroll_x_pixels;
            layer_pos.x -= self.scrollable.viewport_x_adjust;
            layer_pos.y += self.scrollable.scroll_y_pixels;
            layer_pos.y -= self.scrollable.viewport_y_adjust;

            return layer_pos;
        }

        fn getSize(ctx: *anyopaque) rl.Vector2 {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            return self.size;
        }

        fn getRowSize(ctx: *anyopaque) usize {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            return self.row_size;
        }

        fn getScrollState(ctx: *anyopaque) *const Scrollable {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            return &self.scrollable;
        }

        fn getTileset(ctx: *anyopaque) Tileset {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.tileset;
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

        fn resizeLayer(ctx: *anyopaque, new_size: rl.Vector2, row_size: usize) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const tile_size = self.tileset.getTileSize();

            if (@as(usize, @intFromFloat(new_size.y)) * row_size > size) {
                std.log.err("New layer size {d} exceeds maximum size {d}\n", .{ @as(usize, @intFromFloat(new_size.y)) * row_size, size });
                return;
            }

            self.row_size = row_size;
            self.size = new_size;
            self.pixel_size = .{
                .x = new_size.x * tile_size.x,
                .y = new_size.y * tile_size.y,
            };
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

        fn update(ctx: *anyopaque, scene: *Scene, _: f32) !void {
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

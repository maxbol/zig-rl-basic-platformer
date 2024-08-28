const Entity = @import("../entity.zig");
const Scene = @import("../scene.zig");
const Scrollable = @import("scrollable.zig");
const TileLayer = @import("tile_layer.zig");
const Tileset = @import("../tileset/tileset.zig");
const debug = @import("../debug.zig");
const helpers = @import("../helpers.zig");
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
        tileset_path_buf: [3 * 1024]u8 = undefined,
        tileset_path_len: u16,

        // Debug vars
        tested_tiles: [size]bool = .{false} ** size,
        collided_tiles: [size]bool = .{false} ** size,

        pub const data_format_version = 1;

        pub fn init(layer_size: rl.Vector2, row_size: usize, tileset_path: []const u8, tiles: [size]u8, flags: u8) !@This() {
            std.debug.assert(layer_size.x > 0);
            std.debug.assert(layer_size.y > 0);

            const tileset_file = helpers.openFile(tileset_path, .{ .mode = .read_only }) catch |err| {
                std.log.err("Error opening tileset file: {!}\n", .{err});
                std.process.exit(1);
            };
            defer tileset_file.close();

            const tileset = TilesetType.readFromFile(tileset_file) catch |err| {
                std.log.err("Error reading tileset file: {!}\n", .{err});
                return error.TilesetLoadFailed;
            };

            var tileset_path_buf: [3 * 1024]u8 = undefined;
            std.mem.copyForwards(u8, &tileset_path_buf, tileset_path);
            std.debug.print("inited tileset_path_buf as {s}\n", .{tileset_path_buf});

            const tileset_path_len: u16 = @intCast(tileset_path.len);

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
                .tileset_path_buf = tileset_path_buf,
                .tileset_path_len = tileset_path_len,
            };
        }

        pub fn readBytes(reader: anytype) !@This() {
            // Version
            const version = try reader.readByte();
            if (version != data_format_version) {
                std.log.err("Invalid data format version: {d}\n", .{version});
                return error.InvalidDataFormatVersion;
            }

            // Flags
            const flags = try reader.readByte();

            // Layer size
            const size_bytes = try reader.readBytesNoEof(8);
            const layer_size = std.mem.bytesToValue(rl.Vector2, &size_bytes);

            // Row size
            const row_size_bytes = try reader.readBytesNoEof(2);
            const row_size = std.mem.bytesToValue(u16, &row_size_bytes);

            // Tileset file path length
            const len_bytes = try reader.readBytesNoEof(2);
            const tileset_path_len: usize = @intCast(std.mem.bytesToValue(u16, &len_bytes));

            // Tileset file path
            var tileset_path_buf: [3 * 1024]u8 = undefined;
            for (0..tileset_path_len) |i| {
                const byte = try reader.readByte();
                tileset_path_buf[i] = byte;
            }
            const tileset_path = tileset_path_buf[0..tileset_path_len];

            // Tiles
            var tiles: [size]u8 = undefined;
            const tiles_read_len = try reader.readAll(&tiles);
            if (size != tiles_read_len) {
                std.log.err("Failed to read tiles from file\n", .{});
                return error.FailedToReadTiles;
            }

            return @This().init(layer_size, row_size, tileset_path, tiles, flags);
        }

        pub fn writeBytes(self: *@This(), writer: anytype) !void {
            // Write version byte
            try writer.writeByte(data_format_version);

            // Write flags
            try writer.writeByte(self.flags);

            // Write layer size
            const size_bytes: [8]u8 = std.mem.toBytes(self.size);
            _ = try writer.write(&size_bytes);

            // Write row size
            const row_size: u16 = @intCast(self.row_size);
            const row_size_bytes: [2]u8 = std.mem.toBytes(row_size);
            _ = try writer.write(&row_size_bytes);

            // Write tileset file path length
            const len_bytes: [2]u8 = std.mem.toBytes(self.tileset_path_len);
            _ = try writer.write(&len_bytes);

            // Write tileset file path
            const tileset_path = self.tileset_path_buf[0..self.tileset_path_len];
            _ = try writer.write(tileset_path);

            // Write tiles
            _ = try writer.write(&self.tiles);
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

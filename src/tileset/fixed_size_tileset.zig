const Tileset = @import("tileset.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");
const std = @import("std");

pub fn FixedSizeTileset(size: usize) type {
    return struct {
        texture: rl.Texture2D,
        image: rl.Image,
        rect_map: RectMap,
        tile_size: rl.Vector2,
        collision_map: CollisionMap,

        pub const RectMap = [size]?rl.Rectangle;
        pub const CollisionMap = [size]bool;

        pub const bitpacked_size = size / 8;
        pub const data_format_version = 1;
        pub const serialized_size = 1 + 8 + (size / 8) + (1024 * 30);

        pub fn init(image: rl.Image, tile_size: rl.Vector2, collision_map: CollisionMap) !@This() {
            const texture = rl.loadTextureFromImage(image);
            const rect_map = helpers.buildRectMap(size, texture.width, texture.height, tile_size.x, tile_size.y, 1, 1);
            return .{ .image = image, .texture = texture, .tile_size = tile_size, .rect_map = rect_map, .collision_map = collision_map };
        }

        pub fn deinit(self: *@This()) void {
            rl.unloadTexture(self.texture);
        }

        pub fn readFromFile(file: std.fs.File) !@This() {
            return readBytes(file.reader());
        }

        pub fn writeToFile(self: *@This(), file: std.fs.File) !@This() {
            return self.writeBytes(file.writer());
        }

        pub fn readBytes(reader: anytype) !@This() {
            // Version byte
            const version = try reader.readByte();
            if (version != data_format_version) {
                @panic("Invalid data format version");
            }

            // Tile size
            const tile_size_x_bytes = try reader.readBytesNoEof(4);
            const tile_size_y_bytes = try reader.readBytesNoEof(4);
            const tile_size_x: f32 = std.mem.bytesToValue(
                f32,
                &tile_size_x_bytes,
            );
            const tile_size_y: f32 = std.mem.bytesToValue(
                f32,
                &tile_size_y_bytes,
            );
            const tile_size = rl.Vector2.init(tile_size_x, tile_size_y);

            // Collision map
            var collision_map: CollisionMap = undefined;
            const col_map_bitpacked = try reader.readBytesNoEof(bitpacked_size);
            for (col_map_bitpacked, 0..) |byte, byte_idx| {
                for (0..8) |bit_idx| {
                    if (byte & (@as(u8, 1) << (7 - @as(u3, @intCast(bit_idx)))) != 0) {
                        collision_map[(byte_idx * 8) + bit_idx] = true;
                    }
                }
            }

            // Image data
            var image_data_buf: [1024 * 30]u8 = undefined;
            const image_data_len = try reader.readAll(&image_data_buf);
            const image_data = image_data_buf[0..image_data_len];
            const image = rl.loadImageFromMemory(".png", image_data);

            return @This().init(image, tile_size, collision_map);
        }

        pub fn writeBytes(self: *@This(), writer: anytype) !void {
            // Set version byte (1 byte)
            try writer.writeByte(data_format_version);

            // Serialize tile size (8 bytes)
            for (std.mem.toBytes(self.tile_size.x)) |byte| {
                try writer.writeByte(byte);
            }
            for (std.mem.toBytes(self.tile_size.y)) |byte| {
                try writer.writeByte(byte);
            }

            // Serialize collision map (size / 8 bytes)
            var col_map_bitpacked: [bitpacked_size]u8 = std.mem.zeroes([bitpacked_size]u8);
            for (self.collision_map, 0..) |is_collidable, bit_idx| {
                const byte_idx = @divFloor(bit_idx, 8);
                const bit_offset: u3 = @intCast(bit_idx % 8);
                col_map_bitpacked[byte_idx] |= @as(u8, if (is_collidable) 1 else 0) << (7 - bit_offset);
            }
            _ = try writer.write(&col_map_bitpacked);

            // Serialize texture (max 30 KiB)
            var file_size: c_int = undefined;
            const image_data = rl.exportImageToMemory(self.image, ".png", &file_size);
            if (file_size == 0) {
                return error.ImageExportFailed;
            }
            for (0..@intCast(file_size)) |i| {
                try writer.writeByte(image_data[i]);
            }
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

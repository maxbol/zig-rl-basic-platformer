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

        pub const data_format_version = 1;
        pub const serialized_size = 1 + 8 + (size / 8) + (1024 * 30);

        pub fn init(image: rl.Image, tile_size: rl.Vector2, collision_map: CollisionMap) !@This() {
            const texture = rl.loadTextureFromImage(image);
            const rect_map = helpers.buildRectMap(size, texture.width, texture.height, tile_size.x, tile_size.y, 1, 1);
            std.log.debug("Tilemap texture loaded, includes {d} tiles", .{rect_map.len});
            return .{ .image = image, .texture = texture, .tile_size = tile_size, .rect_map = rect_map, .collision_map = collision_map };
        }

        pub fn deinit(self: *@This()) void {
            rl.unloadTexture(self.texture);
        }

        pub fn fromBytes(bytes: []u8) @This() {
            var cursor: usize = 0;

            // Version byte
            const version = bytes[cursor];
            if (version != data_format_version) {
                @panic("Invalid data format version");
            }
            cursor += 1;

            // Tile size
            const tile_size_x: f32 = std.mem.fromBytes(bytes[cursor .. cursor + 4]);
            cursor += 4;
            const tile_size_y: f32 = std.mem.fromBytes(bytes[cursor .. cursor + 4]);
            cursor += 4;
            const tile_size = rl.Vector2.init(tile_size_x, tile_size_y);

            // Collision map
            var collision_map: CollisionMap = undefined;
            const collision_map_size = std.math.divCeil(size, 8) catch {
                @panic("Invalid collision map size");
            };
            for (cursor..cursor + collision_map_size) |byte_idx| {
                const byte = bytes[byte_idx];
                for (0..8) |bit_idx| {
                    collision_map[(byte_idx * 8) + bit_idx] = (byte >> (7 - bit_idx)) & 1;
                }
            }
            cursor += collision_map_size;

            // Image data
            const image_data = bytes[cursor..];
            const image = rl.loadImageFromMemory("png", image_data);

            return @This().init(image, tile_size, collision_map);
        }

        pub fn toBytes(self: *@This(), byte_len: *usize) ![serialized_size]u8 {
            // TODO: refactor using the writer pattern

            var data = std.mem.zeroes([serialized_size]u8);
            var cursor: usize = 0;

            // Set version byte (1 byte)
            data[cursor] = data_format_version;
            cursor = 1;

            // Serialize tile size (8 bytes)
            for (std.mem.toBytes(self.tile_size.x)) |byte| {
                data[cursor] = byte;
                cursor += 1;
            }
            for (std.mem.toBytes(self.tile_size.y)) |byte| {
                data[cursor] = byte;
                cursor += 1;
            }

            // Serialize collision map (size / 8 bytes)
            for (self.collision_map, 0..) |is_collidable, bit_idx| {
                const byte_idx = @divFloor(bit_idx, 8);
                const bit_offset: u3 = @intCast(bit_idx % 8);
                if (is_collidable) {
                    data[cursor + byte_idx] |= @as(u8, 1) << (7 - bit_offset);
                }
            }
            cursor += try std.math.divCeil(usize, size, 8);

            // Serialize texture (30 KiB)
            var file_size: c_int = undefined;
            const image_data = rl.exportImageToMemory(self.image, ".png", &file_size);
            if (file_size == 0) {
                return error.ImageExportFailed;
            }
            for (0..@intCast(file_size)) |i| {
                data[cursor + i] = image_data[i];
            }
            cursor += @intCast(file_size);

            byte_len.* = cursor;

            return data;
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

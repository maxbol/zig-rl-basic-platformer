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
        flag_map: FlagMap,
        allocator: std.mem.Allocator,

        pub const RectMap = [size]?rl.Rectangle;
        pub const FlagMap = [size]u8;

        pub const map_size = size;
        pub const bitpacked_size = size / 8;
        pub const data_format_version = 1;
        pub const serialized_size = 1 + 8 + (size / 8) + (1024 * 30);

        pub fn create(
            image_data: []const u8,
            tile_size: rl.Vector2,
            flag_map: []const u8,
            allocator: std.mem.Allocator,
        ) !*@This() {
            const new = try allocator.create(@This());
            const image = rl.loadImageFromMemory(".png", image_data);
            const texture = rl.loadTextureFromImage(image);
            const rect_map = helpers.buildRectMap(
                size,
                @floatFromInt(texture.width),
                @floatFromInt(texture.height),
                tile_size.x,
                tile_size.y,
                1,
                1,
                0,
                0,
            );

            var flag_map_owned: FlagMap = std.mem.zeroes([size]u8);
            std.mem.copyForwards(u8, &flag_map_owned, flag_map);

            new.* = .{
                .image = image,
                .texture = texture,
                .tile_size = tile_size,
                .rect_map = rect_map,
                .flag_map = flag_map_owned,
                .allocator = allocator,
            };
            return new;
        }

        pub fn destroy(ctx: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            rl.unloadTexture(self.texture);
            rl.unloadImage(self.image);
            self.allocator.destroy(self);
        }

        pub fn writeToFile(self: *@This(), file: std.fs.File) !void {
            return self.writeBytes(file.writer());
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

            // Set map size (2 bytes)
            try writer.writeInt(u16, map_size, .big);

            // Serialize collision map (size)
            // var col_map_bitpacked: [size]u8 = std.mem.zeroes([size]u8);
            const flag_map_bytes = std.mem.toBytes(self.flag_map);
            _ = try writer.write(&flag_map_bytes);
            // for (self.flag_map, 0..) |is_collidable, bit_idx| {
            //     const byte_idx = @divFloor(bit_idx, 8);
            //     const bit_offset: u3 = @intCast(bit_idx % 8);
            //     col_map_bitpacked[byte_idx] |= @as(u8, if (is_collidable) 1 else 0) << (7 - bit_offset);
            // }
            // _ = try writer.write(&col_map_bitpacked);

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
                    .destroy = destroy,
                    .getTexture = getTexture,
                    .getRect = getRect,
                    .getRectMap = getRectMap,
                    .getTileFlags = getTileFlags,
                    .getTileSize = getTileSize,
                    .isCollidable = isCollidable,
                    .tileHasFlag = tileHasFlag,
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

        fn getTileFlags(ctx: *anyopaque, tile_index: usize) u8 {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.flag_map[tile_index];
        }

        fn isCollidable(ctx: *anyopaque, tile_index: usize) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.flag_map[tile_index] & @intFromEnum(Tileset.TileFlag.Collidable) != 0;
        }

        fn tileHasFlag(ctx: *anyopaque, tile_index: usize, flag: Tileset.TileFlag) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            return self.flag_map[tile_index] & @intFromEnum(flag) != 0;
        }
    };
}

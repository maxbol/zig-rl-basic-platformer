const Tileset = @import("tileset.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");
const std = @import("std");

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

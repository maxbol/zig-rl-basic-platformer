const std = @import("std");
const rl = @import("raylib");
const co = @import("collisions.zig");
const helpers = @import("helpers.zig");
const debug = @import("debug.zig");
const Scene = @import("scene.zig");

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

pub fn Tileset(size: usize) type {
    return struct {
        allocator: std.mem.Allocator,
        texture: rl.Texture2D,
        rect_map: RectMap,
        tile_size: rl.Vector2,
        collision_map: CollisionMap,

        pub const RectMap = [size]?rl.Rectangle;
        pub const CollisionMap = [size]bool;

        pub fn init(tilemap_texture_file: [*:0]const u8, tile_size: rl.Vector2, collision_map: CollisionMap, allocator: std.mem.Allocator) !@This() {
            const texture = rl.loadTexture(tilemap_texture_file);
            const rect_map = helpers.buildRectMap(size, texture.width, texture.height, tile_size.x, tile_size.y, 1, 1);
            std.log.debug("Tilemap texture loaded, includes {d} tiles", .{rect_map.len});
            return .{ .texture = texture, .tile_size = tile_size, .rect_map = rect_map, .collision_map = collision_map, .allocator = allocator };
        }

        pub fn getRect(self: *const @This(), tile_index: usize) ?rl.Rectangle {
            return self.rect_map[tile_index];
        }

        pub fn isCollidable(self: *const @This(), tile_index: usize) bool {
            return self.collision_map[tile_index];
        }

        pub fn drawRect(self: *const @This(), tile_index: usize, dest: rl.Vector2, cull_x: f32, cull_y: f32, tint: rl.Color) void {
            const src = self.getRect(tile_index);

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

pub const TileLayer = struct {
    var id_seq: u8 = 0;

    id: u8,
    size: rl.Vector2, // Size in tiles
    pixel_size: rl.Vector2 = undefined,
    row_size: usize,
    tileset: LayerTileset,
    tiles: []u8,
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

    pub const LayerTileset = Tileset(512);

    pub fn init(size: rl.Vector2, row_size: usize, tileset: LayerTileset, tiles: []u8, flags: u8) TileLayer {
        std.debug.assert(tiles.len > 0);
        std.debug.assert(size.x > 0);
        std.debug.assert(size.y > 0);

        const id = id_seq;
        id_seq += 1;

        var layer = TileLayer{
            .id = id,
            .size = size,
            .row_size = row_size,
            .tileset = tileset,
            .tiles = tiles,
            .flags = flags,
        };

        layer.updatePixelSize();

        return layer;
    }

    pub fn getTileFromRowAndCol(self: *const TileLayer, row_idx: usize, col_idx: usize) ?u8 {
        const tile_idx = row_idx * self.row_size + (col_idx % self.row_size);
        const tile = self.tiles[tile_idx % self.tiles.len];

        if (tile == 0) {
            return null;
        }

        return tile;
    }

    fn updatePixelSize(self: *TileLayer) void {
        const tile_size = self.tileset.tile_size;
        self.pixel_size = .{ .x = self.size.x * tile_size.x, .y = self.size.y * tile_size.y };
    }

    pub fn update(self: *TileLayer, scene: *const Scene, delta_time: f32) void {
        self.updatePixelSize();
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

        std.debug.print("Layer {d} scroll state: {d},{d}\n", .{ self.id, viewport_rect.width, viewport_rect.width });

        // Check sprite collisions
        if (self.flags & @intFromEnum(LayerFlag.Collidable) > 0) {
            for (self.scroll_y_tiles..self.include_y_tiles + 1) |row_idx| {
                for (self.scroll_x_tiles..self.include_x_tiles + 1) |col_idx| {
                    const tile = self.getTileFromRowAndCol(row_idx, col_idx) orelse continue;

                    const tile_scene_pos_x: f32 = @as(f32, @floatFromInt(col_idx)) * tile_size.x;
                    const tile_scene_pos_y: f32 = @as(f32, @floatFromInt(row_idx)) * tile_size.y;

                    const tile_scene_rect = rl.Rectangle.init(tile_scene_pos_x, tile_scene_pos_y, tile_size.x, tile_size.y);

                    for (scene.sprites, 0..) |sprite, sprite_idx| {
                        if (!sprite.hitbox_scene.checkCollision(tile_scene_rect)) {
                            continue;
                        }

                        const collision = sprite.hitbox_scene.getCollision(tile_scene_rect);

                        std.debug.print("Collision detected between {s} ({d},{d}) and tile {d} ({d},{d}): {d} {d} {d} {d}\n", .{
                            sprite.texture_filename,
                            sprite.scene_pos.y,
                            sprite.scene_pos.x,
                            tile,
                            tile_scene_rect.x,
                            tile_scene_rect.y,
                            collision.x,
                            collision.y,
                            collision.width,
                            collision.height,
                        });

                        var new_sprite_pos = sprite.scene_pos;

                        const top_side_m = collision.y == tile_scene_rect.y;
                        const bottom_side_m = collision.y + collision.height == tile_scene_rect.y + tile_scene_rect.height;
                        const left_side_m = collision.x == tile_scene_rect.x;
                        const right_side_m = collision.x + collision.width == tile_scene_rect.x + tile_scene_rect.width;

                        if (top_side_m) {
                            std.debug.print("Top side collision: {d},{d},{d},{d}\n", .{
                                collision.x,
                                collision.y,
                                collision.width,
                                collision.height,
                            });
                            scene.sprites[sprite_idx].world_collision_mask |= @intFromEnum(co.CollisionDirection.Down);
                            new_sprite_pos.y -= collision.height;
                        } else if (bottom_side_m) {
                            std.debug.print("Bottom side collision: {d},{d},{d},{d}\n", .{
                                collision.x,
                                collision.y,
                                collision.width,
                                collision.height,
                            });
                            scene.sprites[sprite_idx].world_collision_mask |= @intFromEnum(co.CollisionDirection.Up);
                            new_sprite_pos.y += collision.height;
                        }

                        if (left_side_m) {
                            std.debug.print("Left side collision: {d},{d},{d},{d}\n", .{
                                collision.x,
                                collision.y,
                                collision.width,
                                collision.height,
                            });
                            scene.sprites[sprite_idx].world_collision_mask |= @intFromEnum(co.CollisionDirection.Right);
                            new_sprite_pos.x -= collision.width;
                        } else if (right_side_m) {
                            std.debug.print("Right side collision: {d},{d},{d},{d}\n", .{
                                collision.x,
                                collision.y,
                                collision.width,
                                collision.height,
                            });
                            scene.sprites[sprite_idx].world_collision_mask |= @intFromEnum(co.CollisionDirection.Left);
                            new_sprite_pos.x += collision.width;
                        }

                        // std.debug.print("setting new scene pos {d},{d}\n", .{ new_sprite_pos.x, new_sprite_pos.y });
                        // scene.sprites[sprite_idx].setScenePosition(scene, new_sprite_pos);

                        // if (true) {
                        //     @panic("Get me out of here");
                        // }
                    }
                }
            }
        }
    }

    pub fn draw(self: *const TileLayer) void {
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

                self.tileset.drawRect(tile, dest, cull_x, cull_y, rl.Color.white);
            }
        }
    }
};

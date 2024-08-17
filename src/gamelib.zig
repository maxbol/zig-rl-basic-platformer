const rl = @import("raylib");
const std = @import("std");

var movement_vectors: [16]rl.Vector2 = undefined;

pub const MovementKeyBitmask = enum(u4) {
    None = 0,
    Up = 1,
    Left = 2,
    Down = 4,
    Right = 8,
};

pub const PixelVec2 = struct {
    x: i32,
    y: i32,
    pub fn getVec2(self: PixelVec2) rl.Vector2 {
        return rl.Vector2.init(self.x, self.y);
    }
};

pub const PixelRect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,

    pub fn getRect(self: PixelRect) rl.Rectangle {
        return rl.Rectangle.init(0, 0, self.x, self.y);
    }
};

pub fn Tilemap(size: usize) type {
    return struct {
        allocator: std.mem.Allocator,
        texture: rl.Texture2D,
        rect_map: RectMap,
        tile_size: PixelVec2,

        const RectMap = [size]?rl.Rectangle;

        pub fn init(tilemap_texture_file: [*:0]const u8, tile_size: PixelVec2, allocator: std.mem.Allocator) !@This() {
            const texture = rl.loadTexture(tilemap_texture_file);
            const rect_map = try buildRectMap(texture, tile_size);
            std.log.debug("Tilemap texture loaded, includes {d} tiles", .{rect_map.len});
            return .{ .texture = texture, .tile_size = tile_size, .rect_map = rect_map, .allocator = allocator };
        }

        pub fn getRect(self: *const @This(), tile_index: usize) ?rl.Rectangle {
            return self.rect_map[tile_index];
        }

        pub fn getTileSize(self: *const @This()) PixelVec2 {
            return self.tile_size;
        }

        pub fn drawRect(self: *const @This(), tile_index: usize, dest: rl.Vector2, cull_x: i32, cull_y: i32, tint: rl.Color, debug_mode: bool) void {
            const src = self.getRect(tile_index);

            if (src) |rect| {
                const cull_x_float: f32 = @floatFromInt(cull_x);
                const cull_y_float: f32 = @floatFromInt(cull_y);

                var r = rect;
                var d = dest;

                if (cull_x > 0) {
                    r.x += cull_x_float;
                    r.width -= cull_x_float;
                    d.x += cull_x_float;
                } else if (cull_x < 0) {
                    r.width += cull_x_float;
                }

                if (cull_y > 0) {
                    r.y += cull_y_float;
                    r.height -= cull_y_float;
                    d.y += cull_y_float;
                } else if (cull_y < 0) {
                    r.height += cull_y_float;
                }

                self.texture.drawRec(r, d, tint);

                if (debug_mode) {
                    var debug_label_buf: [8]u8 = undefined;
                    const debug_label = std.fmt.bufPrintZ(&debug_label_buf, "{d}", .{tile_index}) catch {
                        std.log.err("Error: failed to format debug label\n", .{});
                        return;
                    };
                    rl.drawText(debug_label, @intFromFloat(d.x), @intFromFloat(d.y), @intFromFloat(@floor(r.width / 2)), rl.Color.red);
                }
            } else {
                std.log.warn("Warning: tile index {d} not found in tilemap\n", .{tile_index});
            }
        }

        fn buildRectMap(texture: rl.Texture2D, tile_size: PixelVec2) !RectMap {
            const x_inc: f32 = @floatFromInt(tile_size.x);
            const y_inc: f32 = @floatFromInt(tile_size.y);

            const texture_read_max_x: f32 = @floatFromInt(@divFloor(texture.width, tile_size.x));
            const texture_read_max_y: f32 = @floatFromInt(@divFloor(texture.height, tile_size.y));

            const texture_width: f32 = @floatFromInt(texture.width);
            const texture_height: f32 = @floatFromInt(texture.height);

            if (texture_read_max_x * x_inc != texture_width) {
                std.log.warn("Warning: texture width is not a multiple of tile width\n", .{});
            }

            if (texture_read_max_y * y_inc != texture_height) {
                std.log.warn("Warning: texture height is not a multiple of tile height\n", .{});
            }

            var x_cursor: f32 = 0;
            var y_cursor: f32 = 0;
            var tile_index: usize = 1;

            var map: RectMap = .{null} ** size;

            while (y_cursor <= texture_read_max_y - 1) : (y_cursor += 1) {
                x_cursor = 0;
                while (x_cursor <= texture_read_max_x - 1) : ({
                    x_cursor += 1;
                    tile_index += 1;
                }) {
                    map[tile_index] = rl.Rectangle.init(x_cursor * x_inc, y_cursor * y_inc, x_inc, y_inc);
                }
            }

            return map;
        }
    };
}

pub const Viewport = struct {
    rectangle: rl.Rectangle,
    pos_normal: rl.Vector2 = undefined,
    pixel_pos: PixelVec2 = undefined,
    pixel_rect: PixelRect = undefined,

    pub fn init(rectangle: rl.Rectangle) Viewport {
        return .{ .rectangle = rectangle };
    }

    pub fn update(self: *Viewport, delta_time: f32) void {
        _ = delta_time; // autofix
        //
        const rec_x: i32 = @intFromFloat(@round(self.rectangle.x));
        const rec_y: i32 = @intFromFloat(@round(self.rectangle.y));
        const rec_width: i32 = @intFromFloat(@round(self.rectangle.width));
        const rec_height: i32 = @intFromFloat(@round(self.rectangle.height));
        self.pos_normal = rl.Vector2.init(self.rectangle.x, self.rectangle.y).normalize();
        self.pixel_pos = .{ .x = rec_x, .y = rec_y };
        self.pixel_rect = .{ .x = rec_x, .y = rec_y, .width = rec_width, .height = rec_height };
    }

    pub fn draw(self: *const Viewport) void {
        rl.drawRectangleLines(@intFromFloat(self.rectangle.x - 1), @intFromFloat(self.rectangle.y - 1), @intFromFloat(self.rectangle.width + 2), @intFromFloat(self.rectangle.height + 2), rl.Color.white);
    }
};

pub const TileLayer = struct {
    size: PixelVec2, // Size in tiles
    tilemap: Level.LevelTilemap,
    repeat_behavior: RepeatBehavior,
    tiles: [][]u8,

    const RepeatBehavior = enum {
        DoNotRepeat,
        RepeatSequence,
        RepeatFirstTile,
        RepeatLastTile,
    };

    pub fn init(size: PixelVec2, tilemap: Level.LevelTilemap, tiles: [][]u8, repeat_behavior: RepeatBehavior) TileLayer {
        return .{
            .size = size,
            .tilemap = tilemap,
            .tiles = tiles,
            .repeat_behavior = repeat_behavior,
        };
    }

    pub fn drawLayer(self: *const TileLayer, level: *const Level) void {
        const viewport = level.viewport;
        const scroll_state = level.scroll_state;

        const tile_size = self.tilemap.getTileSize();
        const viewport_pixel_rect = viewport.pixel_rect;

        // const pixel_size_x = self.size.x * tile_size.x;
        // _ = pixel_size_x; // autofix
        // const pixel_size_y = self.size.y * tile_size.y;
        // _ = pixel_size_y; // autofix

        const max_x_scroll: f32 = @floatFromInt(self.size.x - viewport_pixel_rect.width);
        const max_y_scroll: f32 = @floatFromInt(self.size.y - viewport_pixel_rect.height);

        const scroll_x_pixels: i32 = @intFromFloat(scroll_state.x * max_x_scroll);
        const scroll_y_pixels: i32 = @intFromFloat(scroll_state.y * max_y_scroll);

        const scroll_x_tiles = @divFloor(scroll_x_pixels, tile_size.x);
        const scroll_y_tiles = @divFloor(scroll_y_pixels, tile_size.y);
        //
        const sub_tile_scroll_x: i32 = @mod(scroll_x_pixels, tile_size.x);
        const sub_tile_scroll_y: i32 = @mod(scroll_y_pixels, tile_size.y);
        //
        const include_x_tiles = @divFloor(viewport_pixel_rect.width, tile_size.x);
        const include_y_tiles = @divFloor(viewport_pixel_rect.height, tile_size.y);

        const viewport_x_adjust: i32 = @intFromFloat(@round(viewport.rectangle.x));
        const viewport_y_adjust: i32 = @intFromFloat(@round(viewport.rectangle.y));

        // Draw level tiles
        for (self.tiles, 0..) |row, row_idx| {
            if (row_idx < scroll_y_tiles or row_idx > scroll_y_tiles + include_y_tiles) {
                continue;
            }
            const row_idx_int: i32 = @intCast(row_idx);
            const row_offset = row_idx_int - scroll_y_tiles;

            for (row, 0..) |tile, col_idx| {
                if (col_idx < scroll_x_tiles or col_idx > scroll_x_tiles + include_x_tiles) {
                    continue;
                }

                const col_idx_int: i32 = @intCast(col_idx);
                const col_offset = col_idx_int - scroll_x_tiles;

                var cull_x: i32 = 0;
                var cull_y: i32 = 0;

                if (col_idx == scroll_x_tiles) {
                    cull_x = sub_tile_scroll_x;
                } else if (col_idx + 1 > scroll_x_tiles + include_x_tiles) {
                    cull_x = -(tile_size.x - sub_tile_scroll_x);
                }

                if (row_idx == scroll_y_tiles) {
                    cull_y = sub_tile_scroll_y;
                } else if (row_idx + 1 > scroll_y_tiles + include_y_tiles) {
                    cull_y = -(tile_size.y - sub_tile_scroll_y);
                }

                const dest_x: f32 = @floatFromInt(viewport_x_adjust + col_offset * tile_size.x - sub_tile_scroll_x);
                const dest_y: f32 = @floatFromInt(viewport_y_adjust + row_offset * tile_size.y - sub_tile_scroll_y);
                const dest = rl.Vector2.init(dest_x, dest_y);

                self.tilemap.drawRect(tile, dest, cull_x, cull_y, rl.Color.white, true);
            }
        }
    }
};

pub const Level = struct {
    // Initial state
    scroll_state: rl.Vector2,
    viewport: *Viewport,
    layers: []TileLayer,
    allocator: std.mem.Allocator,

    const LevelTilemap = Tilemap(512);

    pub fn create(layers: []TileLayer, viewport: *Viewport, allocator: std.mem.Allocator) !*Level {
        // This does not belong here, temporary solution
        movement_vectors = getMovementVectors();

        const level = try allocator.create(Level);

        level.* = .{
            .layers = layers,
            .scroll_state = rl.Vector2.init(0, 0),
            .viewport = viewport,
            .allocator = allocator,
        };

        return level;
    }

    pub fn destroy(self: *Level) void {
        self.allocator.destroy(self);
    }

    pub fn update(self: *Level, delta_time: f32) void {
        var dir_mask: u4 = @intFromEnum(MovementKeyBitmask.None);

        if (rl.isKeyDown(rl.KeyboardKey.key_w)) {
            dir_mask |= @intFromEnum(MovementKeyBitmask.Up);
        } else if (rl.isKeyDown(rl.KeyboardKey.key_s)) {
            dir_mask |= @intFromEnum(MovementKeyBitmask.Down);
        }

        if (rl.isKeyDown(rl.KeyboardKey.key_a)) {
            dir_mask |= @intFromEnum(MovementKeyBitmask.Left);
        } else if (rl.isKeyDown(rl.KeyboardKey.key_d)) {
            dir_mask |= @intFromEnum(MovementKeyBitmask.Right);
        }

        const dir_vec = movement_vectors[dir_mask];
        const scroll_speed = 0.06;

        if (dir_vec.length() > 0) {
            self.scroll_state = self.scroll_state.add(dir_vec.scale(scroll_speed * delta_time)).clamp(rl.Vector2.init(0, 0), rl.Vector2.init(1, 1));
        }
    }

    pub fn draw(self: *const Level) void {
        for (self.layers, 0..) |layer, i| {
            _ = i; // autofix
            layer.drawLayer(self);
        }
    }
};

pub fn getMovementVectors() [16]rl.Vector2 {
    // This constant can't be run in comptime because it uses extern calls to raylib.
    // I'm not sure if there is a better way of solving this.
    return .{
        // 0 - None
        rl.Vector2.init(0, 0),
        // 1 - Up
        rl.Vector2.init(0, -1),
        // 2 - Left
        rl.Vector2.init(-1, 0),
        // 3 - Up + Left
        rl.Vector2.init(-1, -1).scale(std.math.sqrt2).normalize(),
        // 4 - Down
        rl.Vector2.init(0, 1),
        // 5 - Up + Down (invalid)
        rl.Vector2.init(0, 0),
        // 6 - Left + Down
        rl.Vector2.init(-1, 1).scale(std.math.sqrt2).normalize(),
        // 7 - Up + Left + Down (invalid)
        rl.Vector2.init(0, 0),
        // 8 - Right
        rl.Vector2.init(1, 0),
        // 9 - Up + Right
        rl.Vector2.init(1, -1).scale(std.math.sqrt2).normalize(),
        // 10 - Left + Right (invalid)
        rl.Vector2.init(0, 0),
        // 11 - Up + Left + Right (invalid)
        rl.Vector2.init(0, 0),
        // 12 - Down + Right
        rl.Vector2.init(1, 1).scale(std.math.sqrt2).normalize(),
        // 13 - Up + Down + Right (invalid)
        rl.Vector2.init(0, 0),
        // 14 - Left + Down + Right (invalid)
        rl.Vector2.init(0, 0),
        // 15 - Up + Left + Down + Right (invalid)
        rl.Vector2.init(0, 0),
    };
}

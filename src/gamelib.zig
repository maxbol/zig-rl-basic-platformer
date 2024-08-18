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

pub fn Tileset(size: usize) type {
    return struct {
        allocator: std.mem.Allocator,
        texture: rl.Texture2D,
        rect_map: RectMap,
        tile_size: PixelVec2,

        const RectMap = [size]?rl.Rectangle;

        pub fn init(tilemap_texture_file: [*:0]const u8, tile_size: PixelVec2, allocator: std.mem.Allocator) !@This() {
            const texture = rl.loadTexture(tilemap_texture_file);
            const rect_map = buildRectMap(size, texture.width, texture.height, tile_size.x, tile_size.y);
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
                const drawn = culledRectDraw(self.texture, rect, dest, tint, cull_x, cull_y);
                const r = drawn[0];
                const d = drawn[1];

                if (debug_mode) {
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

pub const LayerFlag = enum(u8) {
    NoFlag = 0x00,
    Collidable = 0b00000001,
    InvertXScroll = 0b00000010,
    InvertYScroll = 0b00000100,

    pub fn compose(flags: []const LayerFlag) u8 {
        var result: u8 = 0;
        for (flags) |flag| {
            result |= @intFromEnum(flag);
        }
        return result;
    }
};

pub const TileLayer = struct {
    size: PixelVec2, // Size in tiles
    pixel_size: PixelVec2 = undefined, // Size in pixels
    row_size: usize,
    tileset: LayerTileset,
    tiles: []u8,
    flags: u8,
    collision_map: ?[]bool = null,

    pub const LayerTileset = Tileset(512);

    pub fn init(size: PixelVec2, row_size: usize, tileset: LayerTileset, tiles: []u8, collision_map: ?[]bool, flags: u8) TileLayer {
        std.debug.assert(tiles.len > 0);
        std.debug.assert(size.x > 0);
        std.debug.assert(size.y > 0);

        var layer = TileLayer{
            .size = size,
            .row_size = row_size,
            .tileset = tileset,
            .tiles = tiles,
            .flags = flags,
            .collision_map = collision_map,
        };

        layer.updateLayerPixelSize();

        return layer;
    }

    inline fn updateLayerPixelSize(self: *TileLayer) void {
        self.pixel_size = .{ .x = self.size.x * self.tileset.tile_size.x, .y = self.size.y * self.tileset.tile_size.y };
    }

    pub fn drawLayer(self: *const TileLayer, scene: *const Scene) void {
        const viewport = scene.viewport;
        const scroll_state = scene.scroll_state;

        const tile_size = self.tileset.getTileSize();
        const viewport_pixel_rect = viewport.pixel_rect;

        const pixel_size_x = self.pixel_size.x;
        const pixel_size_y = self.pixel_size.y;

        const max_x_scroll: f32 = @floatFromInt(@max(pixel_size_x - viewport_pixel_rect.width, 0));
        const max_y_scroll: f32 = @floatFromInt(@max(pixel_size_y - viewport_pixel_rect.height, 0));

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

        const scroll_x_pixels: i32 = @intFromFloat(@round(scroll_state_x * max_x_scroll));
        const scroll_y_pixels: i32 = @intFromFloat(@round(scroll_state_y * max_y_scroll));

        const scroll_x_tiles: usize = @intCast(@divFloor(scroll_x_pixels, tile_size.x));
        const scroll_y_tiles: usize = @intCast(@divFloor(scroll_y_pixels, tile_size.y));

        const sub_tile_scroll_x: i32 = @mod(scroll_x_pixels, tile_size.x);
        const sub_tile_scroll_y: i32 = @mod(scroll_y_pixels, tile_size.y);

        const viewport_tile_size_x: usize = @intCast(@divFloor(viewport_pixel_rect.width, tile_size.x));
        const viewport_tile_size_y: usize = @intCast(@divFloor(viewport_pixel_rect.height, tile_size.y));

        const include_x_tiles: usize = scroll_x_tiles + viewport_tile_size_x;
        const include_y_tiles: usize = scroll_y_tiles + viewport_tile_size_y;

        const viewport_x_adjust: i32 = viewport_pixel_rect.x;
        const viewport_y_adjust: i32 = viewport_pixel_rect.y;

        for (scroll_y_tiles..include_y_tiles + 1) |row_idx| {
            for (scroll_x_tiles..include_x_tiles + 1) |col_idx| {
                const tile_idx = row_idx * self.row_size + (col_idx % self.row_size);

                const tile = self.tiles[tile_idx % self.tiles.len];

                if (tile == 0) {
                    continue;
                }

                const row_offset: i32 = @intCast(row_idx - scroll_y_tiles);
                const col_offset: i32 = @intCast(col_idx - scroll_x_tiles);

                var cull_x: i32 = 0;
                var cull_y: i32 = 0;

                if (col_idx == scroll_x_tiles) {
                    cull_x = sub_tile_scroll_x;
                } else if (col_idx == include_x_tiles) {
                    cull_x = -(tile_size.x - sub_tile_scroll_x);
                }

                if (row_idx == scroll_y_tiles) {
                    cull_y = sub_tile_scroll_y;
                } else if (row_idx == include_y_tiles) {
                    cull_y = -(tile_size.y - sub_tile_scroll_y);
                }

                const dest_x: f32 = @floatFromInt(viewport_x_adjust + col_offset * tile_size.x - sub_tile_scroll_x);
                const dest_y: f32 = @floatFromInt(viewport_y_adjust + row_offset * tile_size.y - sub_tile_scroll_y);
                const dest = rl.Vector2.init(dest_x, dest_y);

                self.tileset.drawRect(tile, dest, cull_x, cull_y, rl.Color.white, false);
            }
        }
    }
};

pub const Scene = struct {
    // Initial state
    scroll_state: rl.Vector2,
    viewport: *Viewport,
    layers: []TileLayer,
    allocator: std.mem.Allocator,
    size: PixelVec2 = undefined,
    sprites: []Sprite = undefined,

    pub fn create(layers: []TileLayer, viewport: *Viewport, sprites: []Sprite, allocator: std.mem.Allocator) !*Scene {
        // This does not belong here, temporary solution
        movement_vectors = getMovementVectors();

        const level = try allocator.create(Scene);

        level.* = .{
            .layers = layers,
            .scroll_state = rl.Vector2.init(0, 0),
            .viewport = viewport,
            .allocator = allocator,
            .sprites = sprites,
        };

        level.updateSceneSize();

        return level;
    }

    inline fn updateSceneSize(self: *Scene) void {
        var scene_size: PixelVec2 = .{ .x = 0, .y = 0 };
        for (self.layers) |layer| {
            if (layer.pixel_size.x > scene_size.x) {
                scene_size.x = layer.pixel_size.x;
            }
            if (layer.pixel_size.y > scene_size.y) {
                scene_size.y = layer.pixel_size.y;
            }
        }
        self.size = scene_size;
    }

    pub fn destroy(self: *Scene) void {
        self.allocator.destroy(self);
    }

    pub fn update(self: *Scene, delta_time: f32) !void {
        // Do we need to run this every frame? Only if the layers
        // ever get updated, which they don't atm.
        // self.updateSceneSize();

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
        const scroll_speed = 0.46;

        if (dir_vec.length() > 0) {
            self.scroll_state = self.scroll_state.add(dir_vec.scale(scroll_speed * delta_time)).clamp(rl.Vector2.init(0, 0), rl.Vector2.init(1, 1));
        }

        for (0..self.sprites.len) |i| {
            try self.sprites[i].update(delta_time);
        }
    }

    pub fn draw(self: *const Scene) void {
        for (self.layers, 0..) |layer, i| {
            _ = i; // autofix
            layer.drawLayer(self);
        }

        for (self.sprites) |sprite| {
            sprite.draw(self);
        }
    }
};

pub const AnimationBufferReader = struct {
    ptr: *anyopaque,
    impl: *const Interface,

    pub const Interface = struct {
        readAnimation: *const fn (ctx: *anyopaque, animation_type: AnimationType) AnimationBufferError!AnimationData,
    };

    pub fn readAnimation(self: AnimationBufferReader, animation_type: AnimationType) AnimationBufferError!AnimationData {
        return self.impl.readAnimation(self.ptr, animation_type);
    }
};

pub const AnimationBufferError = error{
    InvalidAnimation,
};

pub fn AnimationBuffer(animation_index: []const AnimationType, max_no_of_frames: usize) type {
    const max_no_of_animations = animation_index.len;

    const BufferData = [max_no_of_animations * (max_no_of_frames + 2)]u8;

    return struct {
        data: BufferData = std.mem.zeroes(BufferData),

        pub fn reader(self: *@This()) AnimationBufferReader {
            return .{
                .ptr = self,
                .impl = &.{
                    .readAnimation = readAnimation,
                },
            };
        }

        pub fn writeAnimation(
            self: *@This(),
            comptime animation_type: AnimationType,
            duration: f16,
            frames: []const u8,
        ) void {
            const animation_idx = comptime blk: {
                for (animation_index, 0..) |anim, i| {
                    if (anim == animation_type) {
                        break :blk i;
                    }
                }
                @compileError("Invalid animation type referenced in encodeAnimationData(), make sure the animation type is allowed by the buffer");
            };
            const start_idx: usize = animation_idx * (max_no_of_frames + 2);
            const end_idx: usize = start_idx + (max_no_of_frames + 2);

            const duration_bytes: [2]u8 = std.mem.toBytes(duration);

            self.data[start_idx] = duration_bytes[0];
            self.data[start_idx + 1] = duration_bytes[1];

            for (frames, 0..) |frame, i| {
                const idx = start_idx + 2 + i;

                if (frame == 0 or idx > end_idx) {
                    break;
                }
                self.data[idx] = frame;
            }
        }

        pub fn readAnimation(
            ctx: *anyopaque,
            animation_type: AnimationType,
        ) !AnimationData {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const animation_idx = blk: {
                for (animation_index, 0..) |anim, i| {
                    if (anim == animation_type) {
                        break :blk i;
                    }
                }
                return AnimationBufferError.InvalidAnimation;
            };
            const start_idx: usize = animation_idx * (max_no_of_frames + 2);
            const end_idx: usize = start_idx + (max_no_of_frames + 2);

            const anim_end_idx = blk: {
                for (start_idx + 2..end_idx) |i| {
                    if (self.data[i] == 0) {
                        break :blk i;
                    }
                }
                break :blk end_idx;
            };

            const frames = self.data[start_idx + 2 .. anim_end_idx];
            const duration_bytes = self.data[start_idx .. start_idx + 1];

            const duration: f16 = std.mem.bytesToValue(f16, duration_bytes);

            return .{ .duration = duration, .frames = frames };
        }
    };
}

pub const AnimationData = struct {
    duration: f16,
    frames: []u8,
};

pub const AnimationType = enum(usize) {
    Idle,
    Walk,
    Roll,
    Hit,
    Death,
    Attack,
};

pub const Sprite = struct {
    texture: rl.Texture2D,
    hitbox: rl.Rectangle,
    size: PixelVec2,
    pos: rl.Vector2,
    sprite_direction: Direction = .Right,
    current_animation: AnimationType = .Idle,
    queued_animation: ?AnimationType = null,
    freeze_animation_on_last_frame: bool = false,
    sprite_texture_map: SpriteTextureMap,
    animation_buffer: AnimationBufferReader,
    animation_clock: f32 = 0,
    current_display_frame: u8 = 0,
    texture_filename: [*:0]const u8 = "",

    pub const SpriteTextureMap = [128]?rl.Rectangle;

    pub const Direction = enum(u1) {
        Left,
        Right,
    };

    pub fn init(sprite_texture_file: [*:0]const u8, size: PixelVec2, hitbox: rl.Rectangle, pos: rl.Vector2, animation_buffer: AnimationBufferReader) Sprite {
        const texture = rl.loadTexture(sprite_texture_file);
        const sprite_texture_map = buildRectMap(128, texture.width, texture.height, size.x, size.y);

        return .{
            .texture_filename = sprite_texture_file,
            .animation_buffer = animation_buffer,
            .hitbox = hitbox,
            .size = size,
            .pos = pos,
            .sprite_texture_map = sprite_texture_map,
            .texture = texture,
        };
    }

    pub fn setAnimation(self: *Sprite, animation: AnimationType, queued: ?AnimationType, freeze_animation_on_last_frame: bool) void {
        self.current_animation = animation;
        self.queued_animation = queued;
        self.freeze_animation_on_last_frame = freeze_animation_on_last_frame;
        self.animation_clock = 0;
    }

    pub fn update(self: *Sprite, delta_time: f32) !void {
        const current_animation = try self.animation_buffer.readAnimation(self.current_animation);
        const current_animation_duration: f32 = @floatCast(current_animation.duration);
        const anim_length: f32 = @floatFromInt(current_animation.frames.len);

        const frame_duration: f32 = current_animation_duration / anim_length;
        const frame_idx: usize = @min(
            @as(usize, @intFromFloat(@floor(self.animation_clock / frame_duration))),
            current_animation.frames.len - 1,
        );

        self.animation_clock += delta_time;

        if (self.animation_clock > current_animation.duration) {
            if (self.queued_animation) |queued_animation| {
                self.setAnimation(queued_animation, null, false);
            } else if (self.freeze_animation_on_last_frame) {
                self.animation_clock = current_animation.duration;
            } else {
                self.animation_clock = @mod(self.animation_clock, current_animation.duration);
            }
        }

        self.current_display_frame = current_animation.frames[frame_idx];
    }

    pub fn draw(self: *const Sprite, scene: *const Scene) void {
        if (self.current_display_frame == 0) {
            return;
        }

        const frame_rect = self.sprite_texture_map[self.current_display_frame];

        if (frame_rect) |rect| blk: {
            const viewport = scene.viewport;
            const scroll_state = scene.scroll_state;
            const viewport_pixel_rect = viewport.pixel_rect;
            const scene_size = scene.size;

            const max_x_scroll: f32 = @floatFromInt(@max(scene_size.x - viewport_pixel_rect.width, 0));
            const max_y_scroll: f32 = @floatFromInt(@max(scene_size.y - viewport_pixel_rect.height, 0));

            const viewport_x_offset: i32 = @intFromFloat(@round(scroll_state.x * max_x_scroll));
            const viewport_y_offset: i32 = @intFromFloat(@round(scroll_state.y * max_y_scroll));

            const viewport_x_limit: i32 = viewport_x_offset + viewport_pixel_rect.width;
            const viewport_y_limit: i32 = viewport_y_offset + viewport_pixel_rect.height;

            const sprite_scene_pos_x: i32 = @intFromFloat(@floor(self.pos.x * @as(f32, @floatFromInt(scene_size.x))));
            const sprite_scene_pos_y: i32 = @intFromFloat(@floor(self.pos.y * @as(f32, @floatFromInt(scene_size.y))));

            if (sprite_scene_pos_x + self.size.x < viewport_x_offset or sprite_scene_pos_x > viewport_x_limit) {
                break :blk;
            }

            if (sprite_scene_pos_y + self.size.y < viewport_y_offset or sprite_scene_pos_y > viewport_y_limit) {
                break :blk;
            }

            const cull_x: i32 = cull: {
                if (sprite_scene_pos_x < viewport_x_offset) {
                    break :cull viewport_x_offset - sprite_scene_pos_x;
                } else if (sprite_scene_pos_x + self.size.x > viewport_x_limit) {
                    break :cull viewport_x_limit - (sprite_scene_pos_x + self.size.x);
                }
                break :cull 0;
            };
            const cull_y = cull: {
                if (sprite_scene_pos_y < viewport_y_offset) {
                    break :cull viewport_y_offset - sprite_scene_pos_y;
                } else if (sprite_scene_pos_y + self.size.y > viewport_y_limit) {
                    break :cull viewport_y_limit - (sprite_scene_pos_y + self.size.y);
                }
                break :cull 0;
            };

            const dest = rl.Vector2.init(
                viewport.rectangle.x + @as(f32, @floatFromInt(sprite_scene_pos_x)) - @as(f32, @floatFromInt(viewport_x_offset)),
                viewport.rectangle.y + @as(f32, @floatFromInt(sprite_scene_pos_y)) - @as(f32, @floatFromInt(viewport_y_offset)),
            );

            _ = culledRectDraw(self.texture, rect, dest, rl.Color.white, cull_x, cull_y);
        }
    }
};

pub const Player = struct {
    sprite: Sprite,
    movement_speed: f32,
    movement_vector: rl.Vector2 = rl.Vector2.init(0, 0),
};

pub fn getMovementVectors() [16]rl.Vector2 {
    // This constant can't be constructed in comptime because it uses extern calls to raylib.
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

pub fn buildRectMap(comptime size: usize, source_width: i32, source_height: i32, rec_width: i32, rec_height: i32) [size]?rl.Rectangle {
    const x_inc: f32 = @floatFromInt(rec_width);
    const y_inc: f32 = @floatFromInt(rec_height);

    const source_read_max_x: f32 = @floatFromInt(@divFloor(source_width, rec_width));
    const source_read_max_y: f32 = @floatFromInt(@divFloor(source_height, rec_height));

    const source_width_f: f32 = @floatFromInt(source_width);
    const source_height_f: f32 = @floatFromInt(source_height);

    if (source_read_max_x * x_inc != source_width_f) {
        std.log.warn("Warning: source width is not a multiple of rec width\n", .{});
    }

    if (source_read_max_y * y_inc != source_height_f) {
        std.log.warn("Warning: source height is not a multiple of rec height\n", .{});
    }

    var x_cursor: f32 = 0;
    var y_cursor: f32 = 0;
    var tile_index: usize = 1;

    var map: [size]?rl.Rectangle = .{null} ** size;

    while (y_cursor <= source_read_max_y - 1) : (y_cursor += 1) {
        x_cursor = 0;
        while (x_cursor <= source_read_max_x - 1) : ({
            x_cursor += 1;
            tile_index += 1;
        }) {
            map[tile_index] = rl.Rectangle.init(x_cursor * x_inc, y_cursor * y_inc, x_inc, y_inc);
        }
    }

    return map;
}

pub fn culledRectDraw(texture: rl.Texture2D, rect: rl.Rectangle, dest: rl.Vector2, tint: rl.Color, cull_x: i32, cull_y: i32) struct { rl.Rectangle, rl.Vector2 } {
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

    texture.drawRec(r, d, tint);

    return .{ r, d };
}

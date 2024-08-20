const rl = @import("raylib");
const std = @import("std");

var movement_vectors: [16]rl.Vector2 = undefined;
var debug_mode: u8 = 0;

pub const DebugFlags = enum(u8) {
    None = 0b00000000,
    ShowHitboxes = 0b00000001,
    ShowTilemapDebug = 0b00000010,
    ShowScrollState = 0b00000100,
};

pub fn setDebugFlags(flags: []const DebugFlags) void {
    for (flags) |flag| {
        debug_mode |= @intFromEnum(flag);
    }
}

pub const MovementKeyBitmask = enum(u4) {
    None = 0,
    Up = 1,
    Left = 2,
    Down = 4,
    Right = 8,
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
            const rect_map = buildRectMap(size, texture.width, texture.height, tile_size.x, tile_size.y, 1, 1);
            std.log.debug("Tilemap texture loaded, includes {d} tiles", .{rect_map.len});
            return .{ .texture = texture, .tile_size = tile_size, .rect_map = rect_map, .collision_map = collision_map, .allocator = allocator };
        }

        pub fn getRect(self: *const @This(), tile_index: usize) ?rl.Rectangle {
            return self.rect_map[tile_index];
        }

        pub fn isCollidable(self: *const @This(), tile_index: usize) bool {
            return self.collision_map[tile_index];
        }

        pub fn getTileSize(self: *const @This()) rl.Vector2 {
            return self.tile_size;
        }

        pub fn drawRect(self: *const @This(), tile_index: usize, dest: rl.Vector2, cull_x: f32, cull_y: f32, tint: rl.Color) void {
            const src = self.getRect(tile_index);

            if (src) |rect| {
                const drawn = culledRectDraw(self.texture, rect, dest, tint, cull_x, cull_y);

                if (debug_mode & @intFromEnum(DebugFlags.ShowTilemapDebug) > 0) {
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

pub const Viewport = struct {
    rectangle: rl.Rectangle,
    pos_normal: rl.Vector2 = undefined,

    pub fn init(rectangle: rl.Rectangle) Viewport {
        return .{ .rectangle = rectangle };
    }

    pub fn update(self: *Viewport, delta_time: f32) void {
        _ = delta_time; // autofix
        self.pos_normal = rl.Vector2.init(self.rectangle.x, self.rectangle.y).normalize();
    }

    pub fn draw(self: *const Viewport) void {
        rl.drawRectangleLines(@intFromFloat(self.rectangle.x - 1), @intFromFloat(self.rectangle.y - 1), @intFromFloat(self.rectangle.width + 2), @intFromFloat(self.rectangle.height + 2), rl.Color.white);
    }

    pub fn getViewportAdjustedPos(self: *Viewport, comptime T: type, scene: *Scene, pos: T) T {
        pos.x += self.rectangle.x;
        pos.x -= scene.viewport_x_offset;

        pos.y += self.rectangle.y;
        pos.y -= scene.viewport_y_offset;

        return pos;
    }
};

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

    fn updatePixelSize(self: *TileLayer) void {
        const tile_size = self.tileset.getTileSize();
        self.pixel_size = .{ .x = self.size.x * tile_size.x, .y = self.size.y * tile_size.y };
    }

    pub fn update(self: *TileLayer, scene: *const Scene, delta_time: f32) void {
        self.updatePixelSize();
        _ = delta_time; // autofix
        const viewport = scene.viewport;
        const scroll_state = scene.scroll_state;

        const tile_size = self.tileset.getTileSize();
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
                    const tile_idx = row_idx * self.row_size + (col_idx % self.row_size);

                    const tile = self.tiles[tile_idx % self.tiles.len];

                    if (tile == 0 or !self.tileset.isCollidable(tile)) {
                        continue;
                    }

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
                            scene.sprites[sprite_idx].world_collision_mask |= @intFromEnum(CollisionDirection.Down);
                            new_sprite_pos.y -= collision.height;
                        } else if (bottom_side_m) {
                            std.debug.print("Bottom side collision: {d},{d},{d},{d}\n", .{
                                collision.x,
                                collision.y,
                                collision.width,
                                collision.height,
                            });
                            scene.sprites[sprite_idx].world_collision_mask |= @intFromEnum(CollisionDirection.Up);
                            new_sprite_pos.y += collision.height;
                        }

                        if (left_side_m) {
                            std.debug.print("Left side collision: {d},{d},{d},{d}\n", .{
                                collision.x,
                                collision.y,
                                collision.width,
                                collision.height,
                            });
                            scene.sprites[sprite_idx].world_collision_mask |= @intFromEnum(CollisionDirection.Right);
                            new_sprite_pos.x -= collision.width;
                        } else if (right_side_m) {
                            std.debug.print("Right side collision: {d},{d},{d},{d}\n", .{
                                collision.x,
                                collision.y,
                                collision.width,
                                collision.height,
                            });
                            scene.sprites[sprite_idx].world_collision_mask |= @intFromEnum(CollisionDirection.Left);
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
        const tile_size = self.tileset.getTileSize();

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

pub const Scene = struct {
    // Initial state
    scroll_state: rl.Vector2,
    viewport: *Viewport,
    layers: []TileLayer,
    allocator: std.mem.Allocator,
    size: rl.Vector2 = undefined,
    sprites: []Sprite = undefined,
    gravity_vector: rl.Vector2 = rl.Vector2.init(0, 1),
    gravity_force: f32 = 0.1,

    viewport_x_offset: f32 = 0,
    viewport_y_offset: f32 = 0,
    viewport_x_limit: f32 = 0,
    viewport_y_limit: f32 = 0,

    pub fn create(layers: []TileLayer, viewport: *Viewport, sprites: []Sprite, allocator: std.mem.Allocator) !*Scene {
        // This does not belong here, temporary solution
        movement_vectors = getMovementVectors();

        const scene = try allocator.create(Scene);

        scene.* = .{
            .layers = layers,
            .scroll_state = rl.Vector2.init(0, 0),
            .viewport = viewport,
            .allocator = allocator,
            .sprites = sprites,
        };

        scene.updateSceneSize();

        for (0..scene.sprites.len) |i| {
            scene.sprites[i].updatePixelPos(scene);
        }

        return scene;
    }

    inline fn updateSceneSize(self: *Scene) void {
        var scene_size: rl.Vector2 = .{ .x = 0, .y = 0 };
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

        const max_x_scroll: f32 = @max(self.size.x - self.viewport.rectangle.width, 0);
        const max_y_scroll: f32 = @max(self.size.y - self.viewport.rectangle.height, 0);

        self.viewport_x_offset = @round(self.scroll_state.x * max_x_scroll);
        self.viewport_y_offset = @round(self.scroll_state.y * max_y_scroll);

        self.viewport_x_limit = self.viewport_x_offset + self.viewport.rectangle.width;
        self.viewport_y_limit = self.viewport_y_offset + self.viewport.rectangle.height;

        for (0..self.sprites.len) |i| {
            self.sprites[i].clearWorldCollisions();
        }

        for (0..self.layers.len) |i| {
            self.layers[i].update(self, delta_time);
        }

        for (0..self.sprites.len) |i| {
            try self.sprites[i].update(self, delta_time);
        }
    }

    pub fn draw(self: *const Scene) void {
        for (self.layers) |layer| {
            layer.draw();
        }

        for (self.sprites) |sprite| {
            sprite.draw(self);
        }

        if (debug_mode & @intFromEnum(DebugFlags.ShowScrollState) > 0) {
            var debug_label_buf: [32]u8 = undefined;
            const debug_label = std.fmt.bufPrintZ(&debug_label_buf, "scroll state: {d},{d}", .{ self.scroll_state.x, self.scroll_state.y }) catch {
                std.log.err("Error: failed to format debug label\n", .{});
                return;
            };
            rl.drawText(
                debug_label,
                @intFromFloat(self.viewport.rectangle.x + self.viewport.rectangle.width - 200),
                @intFromFloat(self.viewport.rectangle.y + self.viewport.rectangle.height - 100),
                16,
                rl.Color.red,
            );
        }
    }

    pub fn getSceneAdjustedPos(self: *const Scene, comptime T: type, pos: T) T {
        var new_pos = pos;

        new_pos.x *= self.size.x;
        new_pos.y *= self.size.y;

        return new_pos;
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

pub const CollisionDirection = enum(u4) {
    None = 0,
    Up = 1,
    Down = 2,
    Left = 4,
    Right = 8,

    pub fn mask(flags: []const CollisionDirection) u4 {
        var result: u4 = 0;
        for (flags) |flag| {
            result |= @intFromEnum(flag);
        }
        return result;
    }
};

pub const Sprite = struct {
    texture: rl.Texture2D,
    hitbox: rl.Rectangle,
    hitbox_scene: rl.Rectangle = undefined,
    size: rl.Vector2,
    pos: rl.Vector2,
    scene_pos: rl.Vector2 = undefined,
    sprite_direction: Direction = .Right,
    current_animation: AnimationType = .Idle,
    queued_animation: ?AnimationType = null,
    freeze_animation_on_last_frame: bool = false,
    sprite_texture_map_r: SpriteTextureMap,
    sprite_texture_map_l: SpriteTextureMap,
    animation_buffer: AnimationBufferReader,
    animation_clock: f32 = 0,
    current_display_frame: u8 = 0,
    texture_filename: [*:0]const u8 = "",
    world_collision_mask: u4 = 0,
    hitbox_in_viewport: bool = false,
    hitbox_anchor_nodes: [HITBOX_ANCHOR_NODES]rl.Rectangle = std.mem.zeroes([HITBOX_ANCHOR_NODES]rl.Rectangle),
    hitbox_anchor_collision_mask: u16 = 0,

    pub const HITBOX_ANCHOR_ROWS = 3;
    pub const HITBOX_ANCHOR_COLS = 3;
    pub const HITBOX_ANCHOR_NODES = HITBOX_ANCHOR_ROWS * HITBOX_ANCHOR_COLS;
    pub const HITBOX_SIZE = 2;

    pub const SpriteTextureMap = [128]?rl.Rectangle;

    pub const Direction = enum(u1) {
        Left,
        Right,
    };

    pub fn init(sprite_texture_file: [*:0]const u8, size: rl.Vector2, hitbox: rl.Rectangle, pos: rl.Vector2, animation_buffer: AnimationBufferReader) Sprite {
        const texture = rl.loadTexture(sprite_texture_file);
        const sprite_texture_map_r = buildRectMap(128, texture.width, texture.height, size.x, size.y, 1, 1);
        const sprite_texture_map_l = buildRectMap(128, texture.width, texture.height, size.x, size.y, -1, 1);

        return .{
            .texture_filename = sprite_texture_file,
            .animation_buffer = animation_buffer,
            .hitbox = hitbox,
            .size = size,
            .pos = pos,
            .sprite_texture_map_r = sprite_texture_map_r,
            .sprite_texture_map_l = sprite_texture_map_l,
            .texture = texture,
        };
    }

    pub fn clearWorldCollisions(self: *Sprite) void {
        if (self.hitbox_in_viewport) {
            self.world_collision_mask = 0;
        }
    }

    pub fn setAnimation(self: *Sprite, animation: AnimationType, queued: ?AnimationType, freeze_animation_on_last_frame: bool) void {
        self.current_animation = animation;
        self.queued_animation = queued;
        self.freeze_animation_on_last_frame = freeze_animation_on_last_frame;
        self.animation_clock = 0;
    }

    pub fn setDirection(self: *Sprite, direction: Direction) void {
        self.sprite_direction = direction;
    }

    pub fn setScenePosition(self: *Sprite, scene: *const Scene, pos: rl.Vector2) void {
        self.pos = rl.Vector2.init(@as(f32, @floatFromInt(pos.x)) / @as(f32, @floatFromInt(scene.size.x)), @as(f32, @floatFromInt(pos.y)) / @as(f32, @floatFromInt(scene.size.y)));
    }

    pub fn updatePixelPos(self: *Sprite, scene: *const Scene) void {
        // self.scene_pos = scene.getSceneAdjustedPos(rl.Vector2, self.pos);
        self.scene_pos = rl.Vector2.init(
            self.pos.x * scene.size.x,
            self.pos.y * scene.size.y,
        );

        self.hitbox_scene = rl.Rectangle.init(
            self.scene_pos.x + self.hitbox.x,
            self.scene_pos.y + self.hitbox.y,
            self.hitbox.width,
            self.hitbox.height,
        );

        for (0..HITBOX_ANCHOR_NODES) |node_idx| {
            const row_idx = @divFloor(node_idx, HITBOX_ANCHOR_COLS);
            const col_idx = @mod(node_idx, HITBOX_ANCHOR_COLS);

            const anchor_x: f32 = self.hitbox_scene.x + (@round(self.hitbox_scene.width / HITBOX_ANCHOR_COLS) * @as(f32, @floatFromInt(col_idx)));
            const anchor_y: f32 = self.hitbox_scene.y + (@round(self.hitbox_scene.height / HITBOX_ANCHOR_ROWS) * @as(f32, @floatFromInt(row_idx)));

            self.hitbox_anchor_nodes[node_idx] = rl.Rectangle.init(
                anchor_x,
                anchor_y,
                HITBOX_SIZE,
                HITBOX_SIZE,
            );
            //

        }
    }

    pub fn update(self: *Sprite, scene: *Scene, delta_time: f32) !void {
        // Don't perform calculations on sprite if its hitbox is out of bounds of the viewport
        if (self.hitbox_scene.x + self.hitbox_scene.width < scene.viewport_x_offset or self.hitbox_scene.x > scene.viewport_x_limit) {
            self.hitbox_in_viewport = false;
            return;
        }

        if (self.hitbox_scene.y + self.hitbox_scene.height < scene.viewport_y_offset or self.hitbox_scene.y > scene.viewport_y_limit) {
            self.hitbox_in_viewport = false;
            return;
        }

        self.hitbox_in_viewport = true;

        // Animation
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

        // Apply gravity (if not colliding with world below)
        if (self.world_collision_mask & @intFromEnum(CollisionDirection.Down) == 0) {
            self.pos = self.pos.add(scene.gravity_vector.scale(scene.gravity_force * delta_time));
        }

        // Relative positioning
        self.updatePixelPos(scene);
    }

    pub fn draw(self: *const Sprite, scene: *const Scene) void {
        if (self.current_display_frame == 0) {
            return;
        }

        const frame_rect = blk: {
            if (self.sprite_direction == .Right) {
                break :blk self.sprite_texture_map_r[self.current_display_frame];
            } else {
                break :blk self.sprite_texture_map_l[self.current_display_frame];
            }
        };

        if (frame_rect) |rect| blk: {
            const viewport = scene.viewport;

            if (self.scene_pos.x + self.size.x < scene.viewport_x_offset or self.scene_pos.x > scene.viewport_x_limit) {
                break :blk;
            }

            if (self.scene_pos.y + self.size.y < scene.viewport_y_offset or self.scene_pos.y > scene.viewport_y_limit) {
                break :blk;
            }

            const cull_x: f32 = cull: {
                if (self.scene_pos.x < scene.viewport_x_offset) {
                    break :cull scene.viewport_x_offset - self.scene_pos.x;
                } else if (self.scene_pos.x + self.size.x > scene.viewport_x_limit) {
                    break :cull scene.viewport_x_limit - (self.scene_pos.x + self.size.x);
                }
                break :cull 0;
            };
            const cull_y = cull: {
                if (self.scene_pos.y < scene.viewport_y_offset) {
                    break :cull scene.viewport_y_offset - self.scene_pos.y;
                } else if (self.scene_pos.y + self.size.y > scene.viewport_y_limit) {
                    break :cull scene.viewport_y_limit - (self.scene_pos.y + self.size.y);
                }
                break :cull 0;
            };

            const dest = rl.Vector2.init(
                viewport.rectangle.x + self.scene_pos.x - scene.viewport_x_offset,
                viewport.rectangle.y + self.scene_pos.y - scene.viewport_y_offset,
            );

            _ = culledRectDraw(self.texture, rect, dest, rl.Color.white, cull_x, cull_y);

            if (debug_mode & @intFromEnum(DebugFlags.ShowHitboxes) > 0) {
                const hitbox_scene = rl.Rectangle.init(
                    viewport.rectangle.x + self.scene_pos.x + self.hitbox.x - scene.viewport_x_offset,
                    viewport.rectangle.y + self.scene_pos.y + self.hitbox.y - scene.viewport_y_offset,
                    self.hitbox.width,
                    self.hitbox.height,
                );

                rl.drawRectangleLines(@intFromFloat(dest.x), @intFromFloat(dest.y), @intFromFloat(@abs(rect.width)), @intFromFloat(@abs(rect.height)), rl.Color.green);
                rl.drawRectangleLines(@intFromFloat(hitbox_scene.x), @intFromFloat(hitbox_scene.y), @intFromFloat(hitbox_scene.width), @intFromFloat(hitbox_scene.height), rl.Color.red);

                for (self.hitbox_anchor_nodes) |anchor| {
                    rl.drawRectangle(@intFromFloat(anchor.x), @intFromFloat(anchor.y), @intFromFloat(anchor.width), @intFromFloat(anchor.height), rl.Color.red);
                }

                if (self.world_collision_mask & @intFromEnum(CollisionDirection.Down) > 0) {
                    rl.drawLine(@intFromFloat(hitbox_scene.x), @intFromFloat(hitbox_scene.y + hitbox_scene.height), @intFromFloat(hitbox_scene.x + hitbox_scene.width), @intFromFloat(hitbox_scene.y + hitbox_scene.height), rl.Color.yellow);
                }
                if (self.world_collision_mask & @intFromEnum(CollisionDirection.Up) > 0) {
                    rl.drawLine(@intFromFloat(hitbox_scene.x), @intFromFloat(hitbox_scene.y), @intFromFloat(hitbox_scene.x + hitbox_scene.width), @intFromFloat(hitbox_scene.y), rl.Color.yellow);
                }
                if (self.world_collision_mask & @intFromEnum(CollisionDirection.Left) > 0) {
                    rl.drawLine(@intFromFloat(hitbox_scene.x), @intFromFloat(hitbox_scene.y), @intFromFloat(hitbox_scene.x), @intFromFloat(hitbox_scene.y + hitbox_scene.height), rl.Color.yellow);
                }
                if (self.world_collision_mask & @intFromEnum(CollisionDirection.Right) > 0) {
                    rl.drawLine(@intFromFloat(hitbox_scene.x + hitbox_scene.width), @intFromFloat(hitbox_scene.y), @intFromFloat(hitbox_scene.x + hitbox_scene.width), @intFromFloat(hitbox_scene.y + hitbox_scene.height), rl.Color.yellow);
                }
            }
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

pub fn buildRectMap(comptime size: usize, source_width: i32, source_height: i32, rec_width: f32, rec_height: f32, x_dir: i2, y_dir: i2) [size]?rl.Rectangle {
    const source_read_max_x: f32 = @floor(@as(f32, @floatFromInt(source_width)) / rec_width);
    const source_read_max_y: f32 = @floor(@as(f32, @floatFromInt(source_height)) / rec_height);

    const source_width_f: f32 = @floatFromInt(source_width);
    const source_height_f: f32 = @floatFromInt(source_height);

    if (source_read_max_x * rec_width != source_width_f) {
        std.log.warn("Warning: source width is not a multiple of rec width\n", .{});
    }

    if (source_read_max_y * rec_height != source_height_f) {
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
            map[tile_index] = rl.Rectangle.init(x_cursor * rec_width, y_cursor * rec_height, rec_width * @as(f32, @floatFromInt(x_dir)), rec_height * @as(f32, @floatFromInt(y_dir)));
        }
    }

    return map;
}

pub fn culledRectDraw(texture: rl.Texture2D, rect: rl.Rectangle, dest: rl.Vector2, tint: rl.Color, cull_x: f32, cull_y: f32) struct { rl.Rectangle, rl.Vector2 } {
    var r = rect;
    var d = dest;

    const width_dir = std.math.sign(r.width);
    const height_dir = std.math.sign(r.height);

    std.debug.assert(rect.width != 0);

    // Some of this logic is somewhat convoluted and hard to understand.
    // Basically we swap some parts of the logic around based on whether the source
    // rect has a negative width or height, which indicates that is should be drawn
    // flipped. A flipped sprite needs to be culled somewhat differently.

    if (width_dir * cull_x > 0) {
        r.x += width_dir * cull_x;
        r.width -= cull_x;
        if (r.width >= 0) {
            d.x += cull_x;
        }
    } else if (width_dir * cull_x < 0) {
        r.width += cull_x;
        if (r.width < 0) {
            d.x += cull_x;
        }
    }

    if (height_dir * cull_y > 0) {
        r.y += height_dir * cull_y;
        r.height -= cull_y;
        if (r.height >= 0) {
            d.y += cull_y;
        }
    } else if (height_dir * cull_y < 0) {
        r.height += cull_y;
        if (r.height < 0) {
            d.y += cull_y;
        }
    }

    texture.drawRec(r, d, tint);

    return .{ r, d };
}

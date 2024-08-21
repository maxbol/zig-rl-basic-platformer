const rl = @import("raylib");
const constants = @import("constants.zig");
const an = @import("animation.zig");
const std = @import("std");
const Sprite = @This();
const helpers = @import("helpers.zig");
const Scene = @import("scene.zig");
const co = @import("collisions.zig");
const debug = @import("debug.zig");
const tl = @import("tiles.zig");

texture: rl.Texture2D,
hitbox: rl.Rectangle,
hitbox_scene: rl.Rectangle = undefined,
hitbox_scene_next: rl.Rectangle = undefined,
hitbox_in_viewport: bool = false,
hitbox_anchor_nodes: [HITBOX_ANCHOR_NODES]rl.Rectangle = std.mem.zeroes([HITBOX_ANCHOR_NODES]rl.Rectangle),
hitbox_anchor_collisions: [HITBOX_ANCHOR_NODES]?rl.Rectangle = .{null} ** HITBOX_ANCHOR_NODES,
hitbox_node_vectors: [HITBOX_ANCHOR_NODES]rl.Vector2 = .{rl.Vector2.init(0, 0)} ** HITBOX_ANCHOR_NODES,
size: rl.Vector2,
pos: rl.Vector2,
movement_vec: rl.Vector2 = rl.Vector2.init(0, 0),
sprite_direction: Direction = .Right,
current_animation: an.AnimationType = .Idle,
queued_animation: ?an.AnimationType = null,
freeze_animation_on_last_frame: bool = false,
sprite_texture_map_r: SpriteTextureMap,
sprite_texture_map_l: SpriteTextureMap,
animation_buffer: an.AnimationBufferReader,
animation_clock: f32 = 0,
current_display_frame: u8 = 0,
texture_filename: [*:0]const u8 = "",
world_collision_mask: u4 = 0,
total_collision_rect: ?rl.Rectangle = null,
collision_vec: rl.Vector2 = rl.Vector2.init(0, 0),

pub const HITBOX_ANCHOR_ROWS = 3;
pub const HITBOX_ANCHOR_COLS = 3;
pub const HITBOX_ANCHOR_NODES = HITBOX_ANCHOR_ROWS * HITBOX_ANCHOR_COLS;
pub const HITBOX_SIZE = 3;

pub const SpriteTextureMap = [128]?rl.Rectangle;

pub const Direction = enum(u1) {
    Left,
    Right,
};

pub fn init(sprite_texture_file: [*:0]const u8, size: rl.Vector2, hitbox: rl.Rectangle, pos: rl.Vector2, animation_buffer: an.AnimationBufferReader) Sprite {
    const texture = rl.loadTexture(sprite_texture_file);
    const sprite_texture_map_r = helpers.buildRectMap(128, texture.width, texture.height, size.x, size.y, 1, 1);
    const sprite_texture_map_l = helpers.buildRectMap(128, texture.width, texture.height, size.x, size.y, -1, 1);

    var sprite = Sprite{
        .texture_filename = sprite_texture_file,
        .animation_buffer = animation_buffer,
        .hitbox = hitbox,
        .size = size,
        .pos = pos,
        .sprite_texture_map_r = sprite_texture_map_r,
        .sprite_texture_map_l = sprite_texture_map_l,
        .texture = texture,
    };

    const max_anchor_x = sprite.hitbox.width - HITBOX_SIZE;
    const max_anchor_y = sprite.hitbox.height - HITBOX_SIZE;
    const anchor_spacing_x: f32 = @round(max_anchor_x / (HITBOX_ANCHOR_COLS - 1));
    const anchor_spacing_y: f32 = @round(max_anchor_y / (HITBOX_ANCHOR_ROWS - 1));

    for (0..HITBOX_ANCHOR_NODES) |node_idx| {
        const row_idx = @divFloor(node_idx, HITBOX_ANCHOR_COLS);
        const col_idx = @mod(node_idx, HITBOX_ANCHOR_COLS);

        const anchor_x: f32 = anchor_spacing_x * @as(f32, @floatFromInt(col_idx));
        const anchor_y: f32 = anchor_spacing_y * @as(f32, @floatFromInt(row_idx));

        sprite.hitbox_anchor_nodes[node_idx] = rl.Rectangle.init(
            anchor_x,
            anchor_y,
            HITBOX_SIZE,
            HITBOX_SIZE,
        );

        sprite.hitbox_node_vectors[node_idx] = rl.Vector2
            .init(sprite.hitbox.x + (sprite.hitbox.width / 2), sprite.hitbox.y + (sprite.hitbox.height / 2))
            .subtract(rl.Vector2.init(anchor_x + HITBOX_SIZE / 2, anchor_y + HITBOX_SIZE / 2))
            .normalize();
    }

    return sprite;
}

pub fn setAnimation(self: *Sprite, animation: an.AnimationType, queued: ?an.AnimationType, freeze_animation_on_last_frame: bool) void {
    self.current_animation = animation;
    self.queued_animation = queued;
    self.freeze_animation_on_last_frame = freeze_animation_on_last_frame;
    self.animation_clock = 0;
}

pub fn setDirection(self: *Sprite, direction: Direction) void {
    self.sprite_direction = direction;
}

pub fn getHitboxAbsolutePos(self: *Sprite, origin: rl.Vector2) rl.Rectangle {
    return helpers.getAbsolutePos(origin, self.hitbox);
}

pub fn checkTileCollision(self: *Sprite, nodes: [HITBOX_ANCHOR_NODES]rl.Rectangle, layer: tl.TileLayer, row_idx: usize, col_idx: usize) void {
    const tile = layer.getTileFromRowAndCol(row_idx, col_idx) orelse return;

    if (!layer.tileset.isCollidable(tile)) {
        return;
    }

    const tile_scene_pos_x: f32 = @as(f32, @floatFromInt(col_idx)) * layer.tileset.tile_size.x;
    const tile_scene_pos_y: f32 = @as(f32, @floatFromInt(row_idx)) * layer.tileset.tile_size.y;

    const tile_scene_rect = rl.Rectangle.init(tile_scene_pos_x, tile_scene_pos_y, layer.tileset.tile_size.x, layer.tileset.tile_size.y);

    for (nodes, 0..) |anchor, anchor_idx| {
        if (!anchor.checkCollision(tile_scene_rect)) {
            continue;
        }

        const prev_collision = self.hitbox_anchor_collisions[anchor_idx];
        var next_collision = anchor.getCollision(tile_scene_rect);

        if (prev_collision) |prev| {
            next_collision = helpers.combineRects(prev, next_collision);
        }

        self.hitbox_anchor_collisions[anchor_idx] = next_collision;
    }
}

pub fn checkCollisions(self: *Sprite, nodes: [HITBOX_ANCHOR_NODES]rl.Rectangle, layer: tl.TileLayer) void {
    if (layer.flags & @intFromEnum(tl.LayerFlag.Collidable) == 0) {
        return;
    }
    for (layer.scroll_y_tiles..layer.include_y_tiles + 1) |row_idx| {
        for (layer.scroll_x_tiles..layer.include_x_tiles + 1) |col_idx| {
            self.checkTileCollision(nodes, layer, row_idx, col_idx);
        }
    }
}

pub fn update(self: *Sprite, scene: *Scene, delta_time: f32) !void {
    // Update hitbox position
    self.hitbox_scene = self.getHitboxAbsolutePos(self.pos);

    // Don't perform calculations on sprite if its hitbox is out of bounds of the viewport
    if (!scene.isRectInViewport(self.hitbox_scene)) {
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
    if (self.world_collision_mask & @intFromEnum(co.CollisionDirection.Down) == 0) {
        self.movement_vec = self.movement_vec.add(scene.gravity_vector.scale(scene.gravity_force * delta_time));
    }

    // Get next hypothetical position of sprite
    var next_pos = self.pos.add(self.movement_vec);

    // Calculate next hitbox position
    self.hitbox_scene_next = self.getHitboxAbsolutePos(next_pos);

    // Collision detection
    self.hitbox_anchor_collisions = .{null} ** HITBOX_ANCHOR_NODES;
    self.total_collision_rect = null;
    self.collision_vec = rl.Vector2.init(0, 0);
    self.world_collision_mask = 0;

    // Scene positions of hitbox anchor nodes
    var hitbox_anchor_scene_nodes: [HITBOX_ANCHOR_NODES]rl.Rectangle = undefined;
    for (self.hitbox_anchor_nodes, 0..) |anchor, anchor_idx| {
        const anchor_scene_pos = helpers.getAbsolutePos(next_pos, anchor);
        hitbox_anchor_scene_nodes[anchor_idx] = anchor_scene_pos;
    }

    for (scene.layers) |layer| {
        self.checkCollisions(hitbox_anchor_scene_nodes, layer);
    }

    for (hitbox_anchor_scene_nodes, 0..) |anchor, anchor_idx| {
        if (!scene.isRectInViewport(anchor)) {
            continue;
        }

        const collision_rect = self.hitbox_anchor_collisions[anchor_idx];

        if (collision_rect) |rect| {
            self.total_collision_rect = if (self.total_collision_rect) |prev| helpers.combineRects(prev, rect) else rect;
            self.collision_vec = self.collision_vec.add(self.hitbox_node_vectors[anchor_idx]);
        }
    }

    if (self.collision_vec.x > 0) {
        self.world_collision_mask |= @intFromEnum(co.CollisionDirection.Left);
    } else if (self.collision_vec.x < 0) {
        self.world_collision_mask |= @intFromEnum(co.CollisionDirection.Right);
    }

    if (self.collision_vec.y > 0) {
        self.world_collision_mask |= @intFromEnum(co.CollisionDirection.Up);
    } else if (self.collision_vec.y < 0) {
        self.world_collision_mask |= @intFromEnum(co.CollisionDirection.Down);
    }

    self.collision_vec = self.collision_vec.normalize();

    if (self.total_collision_rect) |col_rect| {
        self.collision_vec.x *= col_rect.width;
        self.collision_vec.y *= col_rect.height;
        next_pos = next_pos.add(self.collision_vec);
        const collision_vec_angle = rl.Vector2.init(1, 0).angle(self.collision_vec) * constants.RAD2DEG;
        std.debug.print("collision_vec: {d},{d}, collision_vec_angle={d}, col_rect={d},{d},{d},{d}\n", .{ self.collision_vec.x, self.collision_vec.y, collision_vec_angle, col_rect.x, col_rect.y, col_rect.width, col_rect.height });
    }

    //
    // if (self.total_collision_rect) |col_rect| {
    //     self.collision_vec.x *= col_rect.width;
    //     self.collision_vec.y *= col_rect.height;
    //
    //     // const escape_vec = rl.Vector2.init(if (self.collision_vec.x >= 1) self.collision_vec.x else 0, if (self.collision_vec.y >= 1) self.collision_vec.y else 0);
    //     // self.pos = self.pos.add(escape_vec);
    //
    //     if ((collision_vec_angle >= -45 and collision_vec_angle < 45) or (collision_vec_angle >= 135 or collision_vec_angle < -135)) {
    //         std.debug.print("adjusting horizontal position by {d}\n", .{self.collision_vec.x});
    //         self.pos = self.pos.add(rl.Vector2.init(self.collision_vec.x, 0));
    //     }
    //     if ((collision_vec_angle >= 45 and collision_vec_angle < 135) or (collision_vec_angle >= -135 and collision_vec_angle < -45)) {
    //         std.debug.print("adjusting vertical position by {d}\n", .{self.collision_vec.y});
    //         self.pos = self.pos.add(rl.Vector2.init(0, self.collision_vec.y));
    //     }
    // }

    // Adjust position by accumulated movement vector
    self.pos = next_pos;

    // Clear movement vector
    self.movement_vec = rl.Vector2.init(0, 0);
}

pub fn draw(self: *const Sprite, scene: *const Scene) void {
    if (self.current_display_frame == 0) {
        return;
    }

    const rect = blk: {
        if (self.sprite_direction == .Right) {
            break :blk self.sprite_texture_map_r[self.current_display_frame];
        } else {
            break :blk self.sprite_texture_map_l[self.current_display_frame];
        }
    } orelse {
        return;
    };

    if (self.pos.x + self.size.x < scene.viewport_x_offset or self.pos.x > scene.viewport_x_limit) {
        return;
    }

    if (self.pos.y + self.size.y < scene.viewport_y_offset or self.pos.y > scene.viewport_y_limit) {
        return;
    }

    const cull_x: f32 = cull: {
        if (self.pos.x < scene.viewport_x_offset) {
            break :cull scene.viewport_x_offset - self.pos.x;
        } else if (self.pos.x + self.size.x > scene.viewport_x_limit) {
            break :cull scene.viewport_x_limit - (self.pos.x + self.size.x);
        }
        break :cull 0;
    };

    const cull_y = cull: {
        if (self.pos.y < scene.viewport_y_offset) {
            break :cull scene.viewport_y_offset - self.pos.y;
        } else if (self.pos.y + self.size.y > scene.viewport_y_limit) {
            break :cull scene.viewport_y_limit - (self.pos.y + self.size.y);
        }
        break :cull 0;
    };

    const dest = scene.getViewportAdjustedPos(rl.Vector2, self.pos);

    _ = helpers.culledRectDraw(self.texture, rect, dest, rl.Color.white, cull_x, cull_y);
}

pub fn drawDebug(self: *const Sprite, scene: *const Scene) void {
    const viewport = scene.viewport;

    const rect = blk: {
        if (self.sprite_direction == .Right) {
            break :blk self.sprite_texture_map_r[self.current_display_frame];
        } else {
            break :blk self.sprite_texture_map_l[self.current_display_frame];
        }
    } orelse {
        return;
    };

    if (!debug.isDebugFlagSet(.ShowHitboxes)) {
        return;
    }

    const hitbox_viewport = scene.getViewportAdjustedPos(rl.Rectangle, self.hitbox_scene_next);

    const dest = rl.Vector2.init(
        viewport.rectangle.x + self.pos.x - scene.viewport_x_offset,
        viewport.rectangle.y + self.pos.y - scene.viewport_y_offset,
    );

    rl.drawRectangleLines(@intFromFloat(dest.x), @intFromFloat(dest.y), @intFromFloat(@abs(rect.width)), @intFromFloat(@abs(rect.height)), rl.Color.green);
    rl.drawRectangleLines(@intFromFloat(hitbox_viewport.x), @intFromFloat(hitbox_viewport.y), @intFromFloat(hitbox_viewport.width), @intFromFloat(hitbox_viewport.height), rl.Color.red);

    if (self.total_collision_rect) |t| {
        const t_viewport = scene.getViewportAdjustedPos(rl.Rectangle, t);
        rl.drawRectangle(@intFromFloat(t_viewport.x), @intFromFloat(t_viewport.y), @intFromFloat(t_viewport.width), @intFromFloat(t_viewport.height), rl.Color.red.alpha(0.5));
    }

    if (self.collision_vec.x != 0 and self.collision_vec.y != 0) {
        const origo = scene.getViewportAdjustedPos(rl.Vector2, rl.Vector2.init(self.hitbox_scene_next.x, self.hitbox_scene_next.y));
        std.debug.print("drawing collision vec: {d}, {d}\n", .{ self.collision_vec.x, self.collision_vec.y });
        helpers.drawVec2AsArrow(origo, self.collision_vec, rl.Color.white);
    }

    for (self.hitbox_anchor_nodes, 0..) |anchor, anchor_idx| {
        const anchor_scene = helpers.getAbsolutePos(self.hitbox_scene_next, anchor);
        const anchor_viewport = scene.getViewportAdjustedPos(rl.Rectangle, anchor_scene);
        const anchor_color = if (self.hitbox_anchor_collisions[anchor_idx] != null) rl.Color.yellow else rl.Color.red;
        rl.drawRectangle(@intFromFloat(anchor_viewport.x), @intFromFloat(anchor_viewport.y), @intFromFloat(anchor_viewport.width), @intFromFloat(anchor_viewport.height), anchor_color);
    }

    if (self.world_collision_mask & @intFromEnum(co.CollisionDirection.Down) > 0) {
        rl.drawLine(@intFromFloat(hitbox_viewport.x), @intFromFloat(hitbox_viewport.y + hitbox_viewport.height), @intFromFloat(hitbox_viewport.x + hitbox_viewport.width), @intFromFloat(hitbox_viewport.y + hitbox_viewport.height), rl.Color.yellow);
    }
    if (self.world_collision_mask & @intFromEnum(co.CollisionDirection.Up) > 0) {
        rl.drawLine(@intFromFloat(hitbox_viewport.x), @intFromFloat(hitbox_viewport.y), @intFromFloat(hitbox_viewport.x + hitbox_viewport.width), @intFromFloat(hitbox_viewport.y), rl.Color.yellow);
    }
    if (self.world_collision_mask & @intFromEnum(co.CollisionDirection.Left) > 0) {
        rl.drawLine(@intFromFloat(hitbox_viewport.x), @intFromFloat(hitbox_viewport.y), @intFromFloat(hitbox_viewport.x), @intFromFloat(hitbox_viewport.y + hitbox_viewport.height), rl.Color.yellow);
    }
    if (self.world_collision_mask & @intFromEnum(co.CollisionDirection.Right) > 0) {
        rl.drawLine(@intFromFloat(hitbox_viewport.x + hitbox_viewport.width), @intFromFloat(hitbox_viewport.y), @intFromFloat(hitbox_viewport.x + hitbox_viewport.width), @intFromFloat(hitbox_viewport.y + hitbox_viewport.height), rl.Color.yellow);
    }
}

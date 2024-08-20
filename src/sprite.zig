const rl = @import("raylib");
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
size: rl.Vector2,
pos: rl.Vector2,
scene_pos: rl.Vector2 = undefined,
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
hitbox_in_viewport: bool = false,
hitbox_anchor_nodes: [HITBOX_ANCHOR_NODES]rl.Rectangle = std.mem.zeroes([HITBOX_ANCHOR_NODES]rl.Rectangle),
hitbox_anchor_collision_mask: u16 = 0,

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
        self.hitbox_anchor_collision_mask = 0;
    }
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

pub fn setScenePosition(self: *Sprite, scene: *const Scene, pos: rl.Vector2) void {
    self.pos = rl.Vector2.init(@as(f32, @floatFromInt(pos.x)) / @as(f32, @floatFromInt(scene.size.x)), @as(f32, @floatFromInt(pos.y)) / @as(f32, @floatFromInt(scene.size.y)));
}

pub fn updatePixelPos(self: *Sprite, scene: *const Scene) void {
    self.scene_pos = scene.getSceneAdjustedPos(rl.Vector2, self.pos);

    self.hitbox_scene = rl.Rectangle.init(
        self.scene_pos.x + self.hitbox.x,
        self.scene_pos.y + self.hitbox.y,
        self.hitbox.width,
        self.hitbox.height,
    );

    const max_anchor_x = self.hitbox_scene.width - HITBOX_SIZE;
    const max_anchor_y = self.hitbox_scene.height - HITBOX_SIZE;
    const anchor_spacing_x: f32 = @round(max_anchor_x / (HITBOX_ANCHOR_COLS - 1));
    const anchor_spacing_y: f32 = @round(max_anchor_y / (HITBOX_ANCHOR_ROWS - 1));

    for (0..HITBOX_ANCHOR_NODES) |node_idx| {
        const row_idx = @divFloor(node_idx, HITBOX_ANCHOR_COLS);
        const col_idx = @mod(node_idx, HITBOX_ANCHOR_COLS);

        const anchor_x: f32 = self.hitbox_scene.x + (anchor_spacing_x * @as(f32, @floatFromInt(col_idx)));
        const anchor_y: f32 = self.hitbox_scene.y + (anchor_spacing_y * @as(f32, @floatFromInt(row_idx)));

        self.hitbox_anchor_nodes[node_idx] = rl.Rectangle.init(
            anchor_x,
            anchor_y,
            HITBOX_SIZE,
            HITBOX_SIZE,
        );
    }
}

pub fn checkTileCollision(self: *Sprite, layer: tl.TileLayer, row_idx: usize, col_idx: usize) void {
    const tile = layer.getTileFromRowAndCol(row_idx, col_idx) orelse return;

    if (!layer.tileset.isCollidable(tile)) {
        return;
    }

    const tile_scene_pos_x: f32 = @as(f32, @floatFromInt(col_idx)) * layer.tileset.tile_size.x;
    const tile_scene_pos_y: f32 = @as(f32, @floatFromInt(row_idx)) * layer.tileset.tile_size.y;

    const tile_scene_rect = rl.Rectangle.init(tile_scene_pos_x, tile_scene_pos_y, layer.tileset.tile_size.x, layer.tileset.tile_size.y);

    for (self.hitbox_anchor_nodes, 0..) |anchor, anchor_idx| {
        if (anchor.checkCollision(tile_scene_rect)) {
            self.hitbox_anchor_collision_mask |= @as(u16, 1) << @as(u4, @intCast(anchor_idx));
        }
    }

    // if (!self.hitbox_scene.checkCollision(tile_scene_rect)) {
    //     return;
    // }
    //
    // const collision = self.hitbox_scene.getCollision(tile_scene_rect);
    //
    // std.debug.print("Collision detected between {s} ({d},{d}) and tile {d} ({d},{d}): {d} {d} {d} {d}\n", .{
    //     self.texture_filename,
    //     self.scene_pos.y,
    //     self.scene_pos.x,
    //     tile,
    //     tile_scene_rect.x,
    //     tile_scene_rect.y,
    //     collision.x,
    //     collision.y,
    //     collision.width,
    //     collision.height,
    // });
    //
    // var new_sprite_pos = self.scene_pos;
    //
    // const top_side_m = collision.y == tile_scene_rect.y;
    // const bottom_side_m = collision.y + collision.height == tile_scene_rect.y + tile_scene_rect.height;
    // const left_side_m = collision.x == tile_scene_rect.x;
    // const right_side_m = collision.x + collision.width == tile_scene_rect.x + tile_scene_rect.width;
    //
    // if (top_side_m) {
    //     std.debug.print("Top side collision: {d},{d},{d},{d}\n", .{
    //         collision.x,
    //         collision.y,
    //         collision.width,
    //         collision.height,
    //     });
    //     self.world_collision_mask |= @intFromEnum(co.CollisionDirection.Down);
    //     new_sprite_pos.y -= collision.height;
    // } else if (bottom_side_m) {
    //     std.debug.print("Bottom side collision: {d},{d},{d},{d}\n", .{
    //         collision.x,
    //         collision.y,
    //         collision.width,
    //         collision.height,
    //     });
    //     self.world_collision_mask |= @intFromEnum(co.CollisionDirection.Up);
    //     new_sprite_pos.y += collision.height;
    // }
    //
    // if (left_side_m) {
    //     std.debug.print("Left side collision: {d},{d},{d},{d}\n", .{
    //         collision.x,
    //         collision.y,
    //         collision.width,
    //         collision.height,
    //     });
    //     self.world_collision_mask |= @intFromEnum(co.CollisionDirection.Right);
    //     new_sprite_pos.x -= collision.width;
    // } else if (right_side_m) {
    //     std.debug.print("Right side collision: {d},{d},{d},{d}\n", .{
    //         collision.x,
    //         collision.y,
    //         collision.width,
    //         collision.height,
    //     });
    //     self.world_collision_mask |= @intFromEnum(co.CollisionDirection.Left);
    //     new_sprite_pos.x += collision.width;
    // }
}

pub fn checkCollisions(self: *Sprite, layer: tl.TileLayer) void {
    if (layer.flags & @intFromEnum(tl.LayerFlag.Collidable) == 0) {
        return;
    }
    for (layer.scroll_y_tiles..layer.include_y_tiles + 1) |row_idx| {
        for (layer.scroll_x_tiles..layer.include_x_tiles + 1) |col_idx| {
            self.checkTileCollision(layer, row_idx, col_idx);
        }
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

    var world_collision_mask: u4 = 0b1111;

    for (self.hitbox_anchor_nodes, 0..) |_, anchor_idx| {
        const collided = self.hitbox_anchor_collision_mask & (@as(u16, 1) << @as(u4, @intCast(anchor_idx))) != 0;
        if (collided) {
            continue;
        }
        const anchor_row_idx = @divFloor(anchor_idx, HITBOX_ANCHOR_COLS);
        const anchor_col_idx = @mod(anchor_idx, HITBOX_ANCHOR_COLS);

        if (anchor_row_idx == 0) {
            world_collision_mask &= (0b1111 ^ @intFromEnum(co.CollisionDirection.Up));
        }

        if (anchor_row_idx == HITBOX_ANCHOR_ROWS - 1) {
            world_collision_mask &= (0b1111 ^ @intFromEnum(co.CollisionDirection.Down));
        }

        if (anchor_col_idx == 0) {
            world_collision_mask &= (0b1111 ^ @intFromEnum(co.CollisionDirection.Left));
        }

        if (anchor_col_idx == HITBOX_ANCHOR_COLS - 1) {
            world_collision_mask &= (0b1111 ^ @intFromEnum(co.CollisionDirection.Right));
        }
    }

    self.world_collision_mask = world_collision_mask;

    // Apply gravity (if not colliding with world below)
    if (self.world_collision_mask & @intFromEnum(co.CollisionDirection.Down) == 0) {
        self.pos = self.pos.add(scene.gravity_vector.scale(scene.gravity_force * delta_time));
    }

    // Relative positioning
    self.updatePixelPos(scene);
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

    if (self.scene_pos.x + self.size.x < scene.viewport_x_offset or self.scene_pos.x > scene.viewport_x_limit) {
        return;
    }

    if (self.scene_pos.y + self.size.y < scene.viewport_y_offset or self.scene_pos.y > scene.viewport_y_limit) {
        return;
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

    const dest = scene.getViewportAdjustedPos(rl.Vector2, self.scene_pos);

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

    const hitbox_viewport = scene.getViewportAdjustedPos(rl.Rectangle, self.hitbox_scene);

    const dest = rl.Vector2.init(
        viewport.rectangle.x + self.scene_pos.x - scene.viewport_x_offset,
        viewport.rectangle.y + self.scene_pos.y - scene.viewport_y_offset,
    );

    rl.drawRectangleLines(@intFromFloat(dest.x), @intFromFloat(dest.y), @intFromFloat(@abs(rect.width)), @intFromFloat(@abs(rect.height)), rl.Color.green);
    rl.drawRectangleLines(@intFromFloat(hitbox_viewport.x), @intFromFloat(hitbox_viewport.y), @intFromFloat(hitbox_viewport.width), @intFromFloat(hitbox_viewport.height), rl.Color.red);

    std.debug.print("Collision mask: {b}\n", .{self.hitbox_anchor_collision_mask});

    for (self.hitbox_anchor_nodes, 0..) |anchor, anchor_idx| {
        const anchor_viewport = scene.getViewportAdjustedPos(rl.Rectangle, anchor);
        const anchor_color = if (self.hitbox_anchor_collision_mask & (@as(u16, 1) << @as(u4, @intCast(anchor_idx))) != 0) rl.Color.yellow else rl.Color.red;
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

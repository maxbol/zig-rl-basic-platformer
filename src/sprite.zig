const Scene = @import("scene.zig");
const Sprite = @This();
const an = @import("animation.zig");
const constants = @import("constants.zig");
const debug = @import("debug.zig");
const helpers = @import("helpers.zig");
const rl = @import("raylib");
const std = @import("std");

size: rl.Vector2,
flip_mask: u2 = 0,
texture: rl.Texture2D,
sprite_texture_map_r: SpriteTextureMap,
sprite_texture_map_l: SpriteTextureMap,
animation_buffer: an.AnimationBufferReader,
current_animation: an.AnimationType = .Idle,
queued_animation: ?an.AnimationType = null,
freeze_animation_on_last_frame: bool = false,
animation_speed: f32 = 1,
animation_clock: f32 = 0,
current_display_frame: u8 = 0,

pub const SpriteTextureMap = [128]?rl.Rectangle;

pub const FlipState = enum(u2) {
    XFlip = 0b01,
    YFlip = 0b10,
};

pub fn Prefab(
    size_x: f32,
    size_y: f32,
    loadTexture: fn () rl.Texture2D,
    animation_buffer: anytype,
    initial_animation: an.AnimationType,
) type {
    return struct {
        pub const SIZE_X = size_x;
        pub const SIZE_Y = size_y;

        pub fn init() Sprite {
            const size = rl.Vector2.init(size_x, size_y);
            const texture = loadTexture();
            return Sprite.init(texture, size, animation_buffer.reader(), initial_animation);
        }
    };
}

pub fn init(
    texture: rl.Texture2D,
    size: rl.Vector2,
    animation_buffer: an.AnimationBufferReader,
    initial_animation: an.AnimationType,
) Sprite {
    const sprite_texture_map_r = helpers.buildRectMap(128, texture.width, texture.height, size.x, size.y, 1, 1);
    const sprite_texture_map_l = helpers.buildRectMap(128, texture.width, texture.height, size.x, size.y, -1, 1);

    return .{
        .animation_buffer = animation_buffer,
        .size = size,
        .sprite_texture_map_r = sprite_texture_map_r,
        .sprite_texture_map_l = sprite_texture_map_l,
        .texture = texture,
        .current_animation = initial_animation,
    };
}

pub fn setAnimation(self: *Sprite, animation: an.AnimationType, queued: ?an.AnimationType, freeze_animation_on_last_frame: bool) void {
    if (self.current_animation != animation) {
        self.current_animation = animation;
        self.animation_clock = 0;
    }
    self.queued_animation = queued;
    self.freeze_animation_on_last_frame = freeze_animation_on_last_frame;
}

pub fn setAnimationSpeed(self: *Sprite, speed: f32) void {
    self.animation_speed = speed;
}

pub fn setFlip(self: *Sprite, flip: FlipState, state: bool) void {
    self.flip_mask = if (state) @intFromEnum(flip) | self.flip_mask else ~@intFromEnum(flip) & self.flip_mask;
}

pub fn getSourceRect(self: *const Sprite) ?rl.Rectangle {
    if (self.flip_mask & @intFromEnum(FlipState.XFlip) == 0) {
        return self.sprite_texture_map_r[self.current_display_frame];
    } else {
        return self.sprite_texture_map_l[self.current_display_frame];
    }
}

pub fn update(self: *Sprite, _: *Scene, delta_time: f32) !void {
    // Animation
    const current_animation = try self.animation_buffer.readAnimation(self.current_animation);
    const current_animation_duration: f32 = @floatCast(current_animation.duration);
    const anim_length: f32 = @floatFromInt(current_animation.frames.len);

    const frame_duration: f32 = current_animation_duration / anim_length;
    const frame_idx: usize = @min(
        @as(usize, @intFromFloat(@floor(self.animation_clock / frame_duration))),
        current_animation.frames.len - 1,
    );

    self.animation_clock += delta_time * self.animation_speed;

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

pub fn draw(self: *const Sprite, scene: *const Scene, pos: rl.Vector2, color: rl.Color) void {
    // Don't render if no animation frame
    if (self.current_display_frame == 0) {
        return;
    }

    // Don't render if out of viewport bounds
    if (pos.x + self.size.x < scene.viewport_x_offset or pos.x > scene.viewport_x_limit) {
        return;
    }
    if (pos.y + self.size.y < scene.viewport_y_offset or pos.y > scene.viewport_y_limit) {
        return;
    }

    // Get source rect from texture map
    const rect = self.getSourceRect() orelse {
        return;
    };

    // Add viewport culling
    const cull_x: f32 = cull: {
        if (pos.x < scene.viewport_x_offset) {
            break :cull scene.viewport_x_offset - pos.x;
        } else if (pos.x + self.size.x > scene.viewport_x_limit) {
            break :cull scene.viewport_x_limit - (pos.x + self.size.x);
        }
        break :cull 0;
    };
    const cull_y = cull: {
        if (pos.y < scene.viewport_y_offset) {
            break :cull scene.viewport_y_offset - pos.y;
        } else if (pos.y + self.size.y > scene.viewport_y_limit) {
            break :cull scene.viewport_y_limit - (pos.y + self.size.y);
        }
        break :cull 0;
    };

    // Get viewport adjusted destination position
    const dest = scene.getViewportAdjustedPos(rl.Vector2, pos);

    // Do a culled rectangle draw
    _ = helpers.culledRectDraw(self.texture, rect, dest, color, cull_x, cull_y);
}

pub fn drawDebug(self: *const Sprite, scene: *const Scene, pos: rl.Vector2) void {
    if (!debug.isDebugFlagSet(.ShowSpriteOutlines)) {
        return;
    }

    const rect = blk: {
        if (self.flip_mask & @intFromEnum(FlipState.XFlip) == 0) {
            break :blk self.sprite_texture_map_r[self.current_display_frame];
        } else {
            break :blk self.sprite_texture_map_l[self.current_display_frame];
        }
    } orelse {
        return;
    };

    const dest = scene.getViewportAdjustedPos(rl.Vector2, pos);

    rl.drawRectangleLines(@intFromFloat(dest.x), @intFromFloat(dest.y), @intFromFloat(@abs(rect.width)), @intFromFloat(@abs(rect.height)), rl.Color.green);
}

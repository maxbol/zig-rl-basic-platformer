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
initial_animation: u8,
current_animation: an.AnyAnimation,
queued_animation: ?u8 = null,
freeze_animation_on_last_frame: bool = false,
on_animation_finished: ?Callback = null,
animation_speed: f32 = 1,
animation_clock: f32 = 0,
current_display_frame: an.PackedFrame = an.PackedFrame.zero(),

pub const SpriteTextureMap = [128]?rl.Rectangle;

pub const Callback = struct {
    context: *anyopaque,
    call_ptr: *const fn (*anyopaque, *Sprite, *Scene) void,

    pub fn call(self: Callback, sprite: *Sprite, scene: *Scene) void {
        self.call_ptr(self.context, sprite, scene);
    }
};

pub const SetAnimationParam = struct {
    animation_speed: f32 = 1,
    on_animation_finished: ?an.AnyAnimation.Callback = null,
    freeze_animation_on_last_frame: bool = false,
};

pub const FlipState = enum(u2) {
    XFlip = 0b01,
    YFlip = 0b10,
};

pub fn Prefab(
    size_x: f32,
    size_y: f32,
    loadTexture: fn () rl.Texture2D,
    animation_buffer: anytype,
    initial_animation: anytype,
    sprite_map_offset: rl.Vector2,
) type {
    return struct {
        pub const SIZE_X = size_x;
        pub const SIZE_Y = size_y;

        pub fn init() Sprite {
            const size = rl.Vector2.init(size_x, size_y);
            const texture = loadTexture();
            return Sprite.init(
                texture,
                size,
                animation_buffer.reader(),
                @intFromEnum(initial_animation),
                sprite_map_offset,
            ) catch |err| {
                std.log.err("Error initializing sprite: {!}\n", .{err});
                std.process.exit(1);
            };
        }
    };
}

pub fn init(
    texture: rl.Texture2D,
    size: rl.Vector2,
    animation_buffer: an.AnimationBufferReader,
    initial_animation: u8,
    sprite_map_offset: rl.Vector2,
) !Sprite {
    const sprite_texture_map_r = helpers.buildRectMap(
        128,
        @floatFromInt(texture.width),
        @floatFromInt(texture.height),
        size.x,
        size.y,
        1,
        1,
        sprite_map_offset.x,
        sprite_map_offset.y,
    );
    const sprite_texture_map_l = helpers.buildRectMap(
        128,
        @floatFromInt(texture.width),
        @floatFromInt(texture.height),
        size.x,
        size.y,
        -1,
        1,
        sprite_map_offset.x,
        sprite_map_offset.y,
    );

    return .{
        .animation_buffer = animation_buffer,
        .size = size,
        .sprite_texture_map_r = sprite_texture_map_r,
        .sprite_texture_map_l = sprite_texture_map_l,
        .texture = texture,
        .initial_animation = initial_animation,
        .current_animation = try animation_buffer.readAnimation(initial_animation),
    };
}

pub fn reset(self: *Sprite) void {
    const current_animation = self.animation_buffer.readAnimation(self.initial_animation) catch |err| {
        std.log.err("Error resetting sprite: {!}\n", .{err});
        std.process.exit(1);
    };
    self.* = .{
        .animation_buffer = self.animation_buffer,
        .size = self.size,
        .sprite_texture_map_r = self.sprite_texture_map_r,
        .sprite_texture_map_l = self.sprite_texture_map_l,
        .texture = self.texture,
        .current_animation = current_animation,
        .initial_animation = self.initial_animation,
    };
}

pub fn setAnimation(self: *Sprite, animation: anytype, param: SetAnimationParam) void {
    const anim_int: u8 = @intFromEnum(animation);
    if (self.current_animation.data.type != anim_int) {
        self.current_animation = self.animation_buffer.readAnimation(anim_int) catch |err| {
            std.log.err("Error setting animation: {!}\n", .{err});
            std.process.exit(1);
        };
        self.current_animation.clock = 0;
        self.current_animation.freeze_on_last_frame = param.freeze_animation_on_last_frame;
        self.current_animation.speed = param.animation_speed;
        if (param.on_animation_finished) |cb| {
            self.current_animation.on_finished = cb;
        }
    }
}

pub fn setFlip(self: *Sprite, flip: FlipState, state: bool) void {
    self.flip_mask = if (state) @intFromEnum(flip) | self.flip_mask else ~@intFromEnum(flip) & self.flip_mask;
}

pub fn getSourceRect(self: *const Sprite) ?rl.Rectangle {
    const display_frame = self.current_animation.getFrame();
    if (self.flip_mask & @intFromEnum(FlipState.XFlip) == 0) {
        return self.sprite_texture_map_r[display_frame.frame_idx];
    } else {
        return self.sprite_texture_map_l[display_frame.frame_idx];
    }
}

pub fn update(self: *Sprite, scene: *Scene, delta_time: f32) !void {
    _ = scene; // autofix
    self.current_animation.update(delta_time);
    // // Animation
    // if (self.current_animation.frames.len == 0) {
    //     self.current_display_frame = an.PackedFrame.zero();
    //     return;
    // }
    //
    // const current_animation_duration: f32 = @floatCast(self.current_animation.duration);
    // const anim_length: f32 = @floatFromInt(self.current_animation.frames.len);
    //
    // const frame_duration: f32 = current_animation_duration / anim_length;
    // const frame_idx: usize = @min(
    //     @as(usize, @intFromFloat(@floor(self.animation_clock / frame_duration))),
    //     self.current_animation.frames.len - 1,
    // );
    //
    // self.animation_clock += delta_time * self.animation_speed;
    // self.current_display_frame = self.current_animation.frames[frame_idx];
    //
    // if (self.animation_clock > self.current_animation.duration) {
    //     if (self.on_animation_finished) |callback| {
    //         callback.call(self, scene);
    //     } else if (self.freeze_animation_on_last_frame) {
    //         self.animation_clock = self.current_animation.duration;
    //     } else {
    //         self.animation_clock = @mod(self.animation_clock, self.current_animation.duration);
    //     }
    // }
}

pub fn draw(self: *const Sprite, scene: *const Scene, pos: rl.Vector2, color: rl.Color) void {
    // Don't render if no animation frame
    // if (self.current_display_frame.frame_idx == 0) {
    //     return;
    // }
    const dst = helpers.v2r(pos, self.size);

    // Don't render if out of viewport bounds
    if (dst.x + dst.width < scene.viewport_x_offset or dst.x > scene.viewport_x_limit) {
        return;
    }
    if (dst.y + dst.height < scene.viewport_y_offset or dst.y > scene.viewport_y_limit) {
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
    const dst_adjusted = scene.getViewportAdjustedPos(rl.Rectangle, dst);

    // Do a culled rectangle draw
    _ = helpers.culledRectDraw(self.texture, rect, dst_adjusted, color, cull_x, cull_y);
}

pub fn drawDirect(self: *Sprite, pos: rl.Vector2, color: rl.Color) void {
    if (self.getSourceRect()) |rect| {
        self.texture.drawRec(rect, pos, color);
    }
}

pub fn drawDebug(self: *const Sprite, scene: *const Scene, pos: rl.Vector2) void {
    if (!debug.isDebugFlagSet(.ShowSpriteOutlines)) {
        return;
    }

    const rect = blk: {
        if (self.flip_mask & @intFromEnum(FlipState.XFlip) == 0) {
            break :blk self.sprite_texture_map_r[self.current_display_frame.frame_idx];
        } else {
            break :blk self.sprite_texture_map_l[self.current_display_frame.frame_idx];
        }
    } orelse {
        return;
    };

    const dest = scene.getViewportAdjustedPos(rl.Vector2, pos);

    rl.drawRectangleLines(@intFromFloat(dest.x), @intFromFloat(dest.y), @intFromFloat(@abs(rect.width)), @intFromFloat(@abs(rect.height)), rl.Color.green);
}

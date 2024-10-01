const Scene = @import("scene.zig");
const debug = @import("debug.zig");
const helpers = @import("helpers.zig");
const rl = @import("raylib");
const shapes = @import("shapes.zig");
const std = @import("std");

pub const SetAnimationParameters = struct {
    animation_speed: f32 = 1,
    on_animation_finished: ?Animation.Callback = null,
    freeze_animation_on_last_frame: bool = false,
};

pub const AnimationIterator = struct {
    reader: *const AnySpriteBuffer,
    current_animation_idx: usize = 0,

    pub fn next(self: *AnimationIterator) !?Animation {
        const animation = self.reader.readAnimationByIdx(self.current_animation_idx) catch |err| {
            switch (err) {
                SpriteBufferError.AnimationIdxOutOfBounds => {
                    return null;
                },
                else => {
                    return err;
                },
            }
        };
        self.current_animation_idx += 1;
        return animation;
    }
};

pub const AnySpriteBuffer = struct {
    ptr: *const anyopaque,
    impl: *const Interface,

    pub const Interface = struct {
        getInitialAnimationType: *const fn () u8,
        // listAnimations: *const fn (ctx: *const anyopaque) []usize,
        readAnimation: *const fn (ctx: *const anyopaque, animation_type: u8) SpriteBufferError!Animation,
        readAnimationByIdx: *const fn (ctx: *const anyopaque, animation_idx: usize) SpriteBufferError!Animation,
        // transformFrame: *const fn (frame_data: PackedFrame, prev: RenderableFrame) RenderableFrame,
    };

    pub fn readInitialAnimation(self: *const AnySpriteBuffer) SpriteBufferError!Animation {
        const initial_animation_type = self.getInitialAnimationType();
        return self.impl.readAnimation(self.ptr, initial_animation_type);
    }

    pub fn readAnimation(self: *const AnySpriteBuffer, animation_type: anytype) SpriteBufferError!Animation {
        return self.impl.readAnimation(self.ptr, @intFromEnum(animation_type));
    }

    pub fn readAnimationByIdx(self: *const AnySpriteBuffer, animation_idx: usize) SpriteBufferError!Animation {
        return self.impl.readAnimationByIdx(self.ptr, animation_idx);
    }

    pub fn getInitialAnimationType(self: *const AnySpriteBuffer) u8 {
        return self.impl.getInitialAnimationType();
    }

    pub fn iterate(self: *const AnySpriteBuffer) AnimationIterator {
        return .{ .reader = self };
    }

    pub fn sprite(self: AnySpriteBuffer) !Sprite {
        const initial_animation_type = self.impl.getInitialAnimationType();
        return .{
            .reader = self,
            .animation = try self.impl.readAnimation(self.ptr, initial_animation_type),
        };
    }
    // pub fn transformFrame(self: AnySpriteBuffer, frame_data: PackedFrame, prev: RenderableFrame) RenderableFrame {
    //     return self.impl.transformFrame(frame_data, prev);
    // }
};

pub const SpriteBufferError = error{
    InvalidAnimation,
    AnimationIdxOutOfBounds,
};

pub fn SpriteBuffer(
    comptime AnimationType: type,
    animation_types: []const AnimationType,
    transforms: anytype,
    load_texture_fn: *const fn () rl.Texture2D,
    sprite_size: shapes.IPos,
    max_no_of_frames: usize,
) type {
    if (transforms.len > 20) {
        @compileError("Too many transforms in AnimationBuffer, max is 20");
    }

    return struct {
        pub const size = sprite_size;
        pub const max_no_of_animations = animation_types.len;

        const ComptimeAnimationData = struct {
            duration: f32,
            frames: [max_no_of_frames]PackedFrame,
            len: usize,
        };

        data: [max_no_of_animations]ComptimeAnimationData = std.mem.zeroes([max_no_of_animations]ComptimeAnimationData),
        baked: bool = false,
        rendered_frames: [max_no_of_animations][max_no_of_frames]?rl.RenderTexture = undefined,
        sprite_sheet: ?rl.Texture2D = null,
        texture_map: ?SpriteTextureMap = null,
        texture_map_offset: rl.Vector2 = .{ .x = 0, .y = 0 },

        pub fn bakeSpriteSheet(self: *@This()) *rl.Texture2D {
            if (self.sprite_sheet) |*texture| {
                return texture;
            }
            self.sprite_sheet = load_texture_fn();
            return &self.sprite_sheet.?;
        }

        pub fn bakeTextureMap(self: *@This()) *SpriteTextureMap {
            if (self.texture_map) |*map| {
                return map;
            }
            const sprite_sheet = self.bakeSpriteSheet();

            self.texture_map = helpers.buildRectMap(
                128,
                @floatFromInt(sprite_sheet.width),
                @floatFromInt(sprite_sheet.height),
                sprite_size.x,
                sprite_size.y,
                1,
                1,
                self.texture_map_offset.x,
                self.texture_map_offset.y,
            );

            return &self.texture_map.?;
        }

        pub fn prebakeBuffer(self: *@This()) void {
            if (self.baked) {
                return;
            }
            _ = self.bakeTextureMap();
            for (0..max_no_of_animations) |anim_idx| {
                const animation = self.data[anim_idx];
                if (animation.frames[0].frame_pointer == 0) {
                    continue;
                }
                for (0..max_no_of_frames) |frame_idx| {
                    if (animation.frames[frame_idx].frame_pointer == 0) {
                        break;
                    }
                    self.rendered_frames[anim_idx][frame_idx] = self.prerenderFrame(animation.frames[frame_idx].frame_pointer);
                }
            }
            self.baked = true;
        }

        pub fn prerenderFrame(self: *const @This(), frame_idx: usize) ?rl.RenderTexture {
            const texture_map = self.texture_map.?;
            const src = texture_map[frame_idx] orelse {
                return null;
            };

            const y_flipped_src = rl.Rectangle{
                .x = src.x,
                .y = src.y,
                .width = src.width,
                .height = -src.height,
            };

            const dest = .{
                .x = @abs(src.width) / 2,
                .y = @abs(src.height) / 2,
                .width = @abs(src.width),
                .height = @abs(src.height),
            };

            const render_texture = rl.loadRenderTexture(@intFromFloat(dest.width), @intFromFloat(dest.height));

            render_texture.begin();

            self.sprite_sheet.?.drawPro(
                y_flipped_src,
                dest,
                .{ .x = dest.x, .y = dest.y },
                0,
                rl.Color.white,
            );

            render_texture.end();

            return render_texture;
        }

        pub fn getInitialAnimationType() u8 {
            return @intFromEnum(animation_types[0]);
        }

        pub fn reader(self: *const @This()) AnySpriteBuffer {
            return .{
                .ptr = self,
                .impl = &.{
                    .readAnimation = readAnimation,
                    .readAnimationByIdx = readAnimationByIdx,
                    .getInitialAnimationType = getInitialAnimationType,
                },
            };
        }

        // pub fn transformFrame(
        //     frame_data: PackedFrame,
        //     prev: RenderableFrame,
        // ) RenderableFrame {
        //     var next = prev;
        //     for (0..transforms.len) |transform_idx| {
        //         if (frame_data.transform_mask & (@as(u20, 1) << @as(u5, @intCast(transform_idx))) != 0) {
        //             const transform = inline for (transforms, 0..) |transform, idx| {
        //                 if (idx == transform_idx) {
        //                     break transform;
        //                 }
        //             } else unreachable;
        //
        //             next = transform(frame_data, next);
        //         }
        //     }
        //     return next;
        // }
        //
        pub fn listAnimations() []u8 {
            var list: [max_no_of_animations]u8 = undefined;
            for (animation_types) |idx| {
                list[idx] = @intFromEnum(idx);
            }
            return list;
        }

        pub fn writeAnimation(
            self: *@This(),
            comptime animation_type: AnimationType,
            duration: f32,
            frames: []const Frame,
        ) void {
            const animation_idx = comptime blk: {
                for (animation_types, 0..) |anim, i| {
                    if (anim == animation_type) {
                        break :blk i;
                    }
                }
                @compileError("Invalid animation type referenced in writeAnimation(), make sure the animation type is allowed by the buffer");
            };

            const t_lim = @as(u20, 0xfffff) << @as(u5, transforms.len);
            var frame_buffer: [max_no_of_frames]PackedFrame = .{PackedFrame.zero()} ** max_no_of_frames;
            for (frames, 0..) |frame, i| {
                frame_buffer[i] = frameFromU16(frame);
                // @compileLog("setting frame {d}: {d}\n", i, .{frame_buffer[i]});
                if (frame_buffer[i].transform_mask & t_lim != 0) {
                    @compileError(
                        "Trying to write a frame with a transform idx higher than the number of defined transforms in the buffer",
                    );
                }
            }

            // @compileLog("Writing animation:\n", .{@tagName(animation_type)}, frames, frames.len, frame_buffer[0..frames.len]);

            self.data[animation_idx] = .{
                .frames = frame_buffer,
                .duration = duration,
                .len = frames.len,
            };

            // @compileLog("Animation written:\n", .{self.data[animation_idx]});
        }

        pub fn readAnimationByIdx(
            ctx: *const anyopaque,
            animation_idx: usize,
        ) !Animation {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            _ = self; // autofix
            if (animation_idx >= max_no_of_animations) {
                return SpriteBufferError.AnimationIdxOutOfBounds;
            }
            const animation_type = animation_types[animation_idx];
            return readAnimation(ctx, @intFromEnum(animation_type));
        }

        pub fn readAnimation(
            ctx: *const anyopaque,
            animation_type: u8,
        ) !Animation {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            const atype: AnimationType = @enumFromInt(animation_type);
            const animation_idx = blk: {
                for (animation_types, 0..) |anim, i| {
                    if (anim == atype) {
                        break :blk i;
                    }
                }
                return SpriteBufferError.InvalidAnimation;
            };
            const animation = self.data[animation_idx];
            return .{
                .anim_data = .{
                    .duration = animation.duration,
                    .frames = self.rendered_frames[animation_idx][0..animation.len],
                    .type = animation_type,
                },
            };
        }
    };
}

pub const AnimationData = struct {
    duration: f32,
    frames: []const ?rl.RenderTexture,
    type: u8,
};

pub const Animation = struct {
    anim_data: AnimationData,
    anim_speed: f32 = 1,
    anim_clock: f32 = 0,
    anim_frame_idx: usize = 0,
    anim_on_finished: ?Callback = null,
    anim_freeze_on_last_frame: bool = false,

    pub const Callback = struct {
        context: *anyopaque,
        call_ptr: *const fn (*anyopaque, *Animation) void,

        pub fn call(self: Callback, sprite: *Animation) void {
            self.call_ptr(self.context, sprite);
        }
    };

    pub fn update(self: *Animation, delta_time: f32) void {
        if (self.anim_data.frames.len == 0) {
            return;
        }

        self.anim_clock += delta_time * self.anim_speed;

        if (self.anim_clock > self.anim_data.duration) {
            if (self.anim_on_finished) |callback| {
                callback.call(self);
            } else if (self.anim_freeze_on_last_frame) {
                self.anim_clock = self.anim_data.duration;
            } else {
                self.anim_clock = @mod(self.anim_clock, self.anim_data.duration);
            }
        }
    }

    pub fn getFrame(self: *const Animation) ?rl.Texture2D {
        const anim_length: f32 = @floatFromInt(self.anim_data.frames.len);
        const frame_duration: f32 = self.anim_data.duration / anim_length;
        const frame_idx: usize = @min(
            @as(usize, @intFromFloat(@floor(self.anim_clock / frame_duration))),
            self.anim_data.frames.len - 1,
        );
        const frame = self.anim_data.frames[frame_idx] orelse {
            return null;
        };
        return frame.texture;
    }

    pub fn drawDirect(self: *const Animation, pos: rl.Vector2, color: rl.Color) void {
        const frame = self.getFrame() orelse return;
        rl.drawTexture(frame, @intFromFloat(pos.x), @intFromFloat(pos.y), color);
    }

    pub fn draw(self: *const Animation, scene: *const Scene, pos: DrawPosition, tint: rl.Color, flip_mask: Sprite.FlipState) void {
        const frame = self.getFrame() orelse {
            return;
        };
        const fwidth = @as(f32, @floatFromInt(frame.width));
        const fheight = @as(f32, @floatFromInt(frame.height));
        const dst_scene = pos.toRect(.{
            .x = fwidth,
            .y = fheight,
        });

        if (dst_scene.x + dst_scene.width < scene.viewport_x_offset or dst_scene.x > scene.viewport_x_limit) {
            return;
        }
        if (dst_scene.y + dst_scene.height < scene.viewport_y_offset or dst_scene.y > scene.viewport_y_limit) {
            return;
        }

        const cull_x: f32 = cull: {
            if (dst_scene.x < scene.viewport_x_offset) {
                break :cull scene.viewport_x_offset - dst_scene.x;
            } else if (dst_scene.x + fwidth > scene.viewport_x_limit) {
                break :cull scene.viewport_x_limit - (dst_scene.x + fwidth);
            }
            break :cull 0;
        };

        const cull_y = cull: {
            if (dst_scene.y < scene.viewport_y_offset) {
                break :cull scene.viewport_y_offset - dst_scene.y;
            } else if (dst_scene.y + fheight > scene.viewport_y_limit) {
                break :cull scene.viewport_y_limit - (dst_scene.y + fheight);
            }
            break :cull 0;
        };

        // TODO(29/09/2024): More elegant solution here
        var src = rl.Rectangle{ .x = 0, .y = 0, .width = fwidth, .height = fheight };

        if (flip_mask.x) {
            src.x = fwidth;
            src.width = -fwidth;
        }

        if (flip_mask.y) {
            src.y = fheight;
            src.height = -fheight;
        }

        const dst = scene.getViewportAdjustedPos(rl.Rectangle, dst_scene);

        _ = helpers.culledRectDraw(frame, src, dst, tint, cull_x, cull_y);
    }

    pub fn drawDebug(self: *const Animation, scene: *const Scene, pos: DrawPosition) void {
        if (!debug.isDebugFlagSet(.ShowSpriteOutlines)) {
            return;
        }

        const frame = self.getFrame() orelse return;
        const fwidth = @as(f32, @floatFromInt(frame.width));
        const fheight = @as(f32, @floatFromInt(frame.height));

        const dest = scene.getViewportAdjustedPos(rl.Rectangle, pos.toRect(.{
            .x = fwidth,
            .y = fheight,
        }));

        rl.drawRectangleLinesEx(dest, 1, rl.Color.green);
    }
};

pub const Sprite = struct {
    reader: AnySpriteBuffer,
    animation: Animation,
    flip_mask: FlipState = .{},

    pub const FlipState = packed struct(u2) {
        y: bool = false,
        x: bool = false,
    };

    pub fn reset(self: *Sprite) !void {
        self.animation = try self.reader.readInitialAnimation();
        self.flip_mask = .{};
    }

    pub fn setAnimation(self: *Sprite, animation_type: anytype, param: SetAnimationParameters) void {
        std.debug.print("Setting animation: {s}\n", .{@tagName(animation_type)});
        const anim_int: u8 = @intFromEnum(animation_type);
        if (self.animation.anim_data.type != anim_int) {
            self.animation = self.reader.readAnimation(animation_type) catch |err| {
                std.log.err("Error setting animation: {!}\n", .{err});
                std.process.exit(1);
            };
            self.animation.anim_clock = 0;
            if (param.on_animation_finished) |cb| {
                self.animation.anim_on_finished = cb;
            }
        }
        self.animation.anim_freeze_on_last_frame = param.freeze_animation_on_last_frame;
        self.animation.anim_speed = param.animation_speed;
        std.debug.print("Animation set: {s}\n", .{@tagName(animation_type)});
    }

    pub fn update(self: *Sprite, delta_time: f32) void {
        self.animation.update(delta_time);
    }

    pub fn draw(self: *const Sprite, scene: *const Scene, pos: DrawPosition, tint: rl.Color) void {
        self.animation.draw(scene, pos, tint, self.flip_mask);
    }

    pub fn drawDebug(self: *const Sprite, scene: *const Scene, pos: DrawPosition) void {
        self.animation.drawDebug(scene, pos);
    }

    pub fn drawDirect(self: *const Sprite, pos: rl.Vector2, color: rl.Color) void {
        self.animation.drawDirect(pos, color);
    }
};

pub const Frame = u32;
pub const PackedFrame = packed struct(u32) {
    frame_pointer: u12,
    transform_mask: u20,

    pub fn zero() PackedFrame {
        return .{ .transform_mask = 0, .frame_pointer = 0 };
    }
};

pub const Anchor = enum(u8) {
    TopLeft,
    TopCenter,
    TopRight,
    CenterLeft,
    Center,
    CenterRight,
    BottomLeft,
    BottomCenter,
    BottomRight,
};

pub const SpriteTextureMap = [128]?rl.Rectangle;

pub const DrawPosition = struct {
    anchor: Anchor,
    offset: rl.Vector2,
    pos: rl.Vector2,

    pub fn init(pos: anytype, anchor: Anchor, offset: rl.Vector2) DrawPosition {
        return .{
            .pos = .{ .x = pos.x, .y = pos.y },
            .anchor = anchor,
            .offset = offset,
        };
    }

    pub fn toRect(self: DrawPosition, size: rl.Vector2) rl.Rectangle {
        var p = .{
            .x = self.pos.x,
            .y = self.pos.y,
            .width = size.x,
            .height = size.y,
        };
        switch (self.anchor) {
            Anchor.TopLeft => {},
            Anchor.TopCenter => {
                p.x -= size.x / 2;
            },
            Anchor.TopRight => {
                p.x -= size.x;
            },
            Anchor.CenterLeft => {
                p.y -= size.y / 2;
            },
            Anchor.Center => {
                p.x -= size.x / 2;
                p.y -= size.y / 2;
            },
            Anchor.CenterRight => {
                p.x -= size.x;
                p.y -= size.y / 2;
            },
            Anchor.BottomLeft => {
                p.y -= size.y;
            },
            Anchor.BottomCenter => {
                p.x -= size.x / 2;
                p.y -= size.y;
            },
            Anchor.BottomRight => {
                p.x -= size.x;
                p.y -= size.y;
            },
        }
        p.x += self.offset.x;
        p.y += self.offset.y;
        return p;
    }
};

// pub const NoAnimationsBuffer = AnimationBuffer(NoAnimationsType, &.{.Idle}, .{}, 1);
// pub fn getNoAnimationsBuffer() NoAnimationsBuffer {
//     // @compileLog("Building no-animations buffer...");
//     var buffer = NoAnimationsBuffer{};
//     buffer.writeAnimation(.Idle, 0.5, &.{1});
//     return buffer;
// }

pub fn frameFromU16(frame_int: Frame) PackedFrame {
    return @bitCast(frame_int);
}

pub fn f(frame: PackedFrame) Frame {
    return @bitCast(frame);
}

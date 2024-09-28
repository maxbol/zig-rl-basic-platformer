const Scene = @import("scene.zig");
const Sprite = @import("sprite.zig");
const rl = @import("raylib");
const std = @import("std");

pub const AnimationBufferReader = struct {
    ptr: *const anyopaque,
    impl: *const Interface,

    pub const Interface = struct {
        readAnimation: *const fn (ctx: *const anyopaque, animation_type: u8) AnimationBufferError!AnyAnimation,
        transformFrame: *const fn (frame_data: PackedFrame, prev: RenderableFrame) RenderableFrame,
    };

    pub fn readAnimation(self: AnimationBufferReader, animation_type: u8) AnimationBufferError!AnyAnimation {
        return self.impl.readAnimation(self.ptr, animation_type);
    }

    pub fn transformFrame(self: AnimationBufferReader, frame_data: PackedFrame, prev: RenderableFrame) RenderableFrame {
        return self.impl.transformFrame(frame_data, prev);
    }
};

pub const AnimationBufferError = error{
    InvalidAnimation,
};

pub fn AnimationBuffer(comptime AnimationType: type, animation_index: []const AnimationType, transforms: anytype, max_no_of_frames: usize) type {
    const max_no_of_animations = animation_index.len;

    const Frame = u32;
    const Animation = struct {
        duration: f32,
        frames: [max_no_of_frames]PackedFrame,
        len: usize,
    };

    if (transforms.len > 20) {
        @compileError("Too many transforms in AnimationBuffer, max is 20");
    }

    return struct {
        data: [max_no_of_animations]Animation = std.mem.zeroes([max_no_of_animations]Animation),
        // data: BufferData = std.mem.zeroes(BufferData),

        pub fn reader(self: *const @This()) AnimationBufferReader {
            return .{
                .ptr = self,
                .impl = &.{
                    .readAnimation = readAnimation,
                    .transformFrame = transformFrame,
                },
            };
        }

        pub fn transformFrame(
            frame_data: PackedFrame,
            prev: RenderableFrame,
        ) RenderableFrame {
            var next = prev;
            for (0..transforms.len) |transform_idx| {
                if (frame_data.transform_mask & (@as(u20, 1) << @as(u5, @intCast(transform_idx))) != 0) {
                    const transform = inline for (transforms, 0..) |transform, idx| {
                        if (idx == transform_idx) {
                            break transform;
                        }
                    } else unreachable;

                    next = transform(frame_data, next);
                }
            }
            return next;
        }

        pub fn writeAnimation(
            self: *@This(),
            comptime animation_type: AnimationType,
            duration: f32,
            frames: []const Frame,
        ) void {
            const animation_idx = comptime blk: {
                for (animation_index, 0..) |anim, i| {
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
                if (frame_buffer[i].transform_mask & t_lim != 0) {
                    @compileError(
                        "Trying to write a frame with a transform idx higher than the number of defined transforms in the buffer",
                    );
                }
            }

            self.data[animation_idx] = .{
                .frames = frame_buffer,
                .duration = duration,
                .len = frames.len,
            };
        }

        pub fn readAnimation(
            ctx: *const anyopaque,
            animation_type: u8,
        ) !AnyAnimation {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            const atype: AnimationType = @enumFromInt(animation_type);
            const animation_idx = blk: {
                for (animation_index, 0..) |anim, i| {
                    if (anim == atype) {
                        break :blk i;
                    }
                }
                return AnimationBufferError.InvalidAnimation;
            };
            const animation = &self.data[animation_idx];
            return .{
                .ctx = ctx,
                .data = .{
                    .duration = animation.duration,
                    .frames = animation.frames[0..animation.len],
                    .type = animation_type,
                },
            };
        }
    };
}

pub const AnimationData = struct {
    duration: f32,
    frames: []const PackedFrame,
    type: u8,
};

pub const AnyAnimation = struct {
    data: AnimationData,
    speed: f32 = 1,
    clock: f32 = 0,
    frame_idx: usize = 0,
    on_finished: ?Callback = null,
    freeze_on_last_frame: bool = false,
    ctx: *const anyopaque,

    pub const Callback = struct {
        context: *anyopaque,
        call_ptr: *const fn (*anyopaque, *AnyAnimation) void,

        pub fn call(self: Callback, animation: *AnyAnimation) void {
            self.call_ptr(self.context, animation);
        }
    };

    pub fn update(self: *AnyAnimation, delta_time: f32) void {
        if (self.data.frames.len == 0) {
            return;
        }

        self.clock += delta_time * self.speed;

        if (self.clock > self.data.duration) {
            if (self.on_finished) |callback| {
                callback.call(self);
            } else if (self.freeze_on_last_frame) {
                self.clock = self.data.duration;
            } else {
                self.clock = @mod(self.clock, self.data.duration);
            }
        }
    }

    pub fn getFrame(self: *const AnyAnimation) PackedFrame {
        const anim_length: f32 = @floatFromInt(self.data.frames.len);
        const frame_duration: f32 = self.data.duration / anim_length;
        const frame_idx: usize = @min(
            @as(usize, @intFromFloat(@floor(self.clock / frame_duration))),
            self.data.frames.len - 1,
        );
        return self.data.frames[frame_idx];
    }

    pub fn renderFrame(self: *const AnyAnimation, texture_map: Sprite.SpriteTextureMap, texture: rl.Texture2D, pos: rl.Vector2) void {
        const buf_reader: *const AnimationBufferReader = @ptrCast(@alignCast(self.ctx));
        const frame_data = self.getFrame();
        const src = texture_map[frame_data.frame_idx];
        const dest = .{
            .x = pos.x,
            .y = pos.y,
            .width = @abs(src.width),
            .height = @abs(src.height),
        };
        const prev = .{
            .src = src,
            .dest = dest,
            .offset = .{ 0, 0 },
            .rotation = 0,
            .tint = rl.WHITE,
        };
        buf_reader.transformFrame(frame_data, prev).render(texture);
    }
};

pub const PackedFrame = packed struct(u32) {
    frame_idx: u12,
    transform_mask: u20,

    pub fn zero() PackedFrame {
        return .{ .transform_mask = 0, .frame_idx = 0 };
    }
};

pub const RenderableFrame = struct {
    src: rl.Rectangle,
    dest: rl.Rectangle,
    offset: rl.Vector2,
    rotation: f32,
    tint: rl.Color,

    pub fn render(self: RenderableFrame, texture: rl.Texture2D) void {
        texture.drawPro(
            self.src,
            self.dest,
            self.offset,
            self.rotation,
            self.tint,
        );
    }
};

pub const NoAnimationsType = enum(u8) {
    Idle,
};
pub const NoAnimationsBuffer = AnimationBuffer(NoAnimationsType, &.{.Idle}, .{}, 1);
pub fn getNoAnimationsBuffer() NoAnimationsBuffer {
    // @compileLog("Building no-animations buffer...");
    var buffer = NoAnimationsBuffer{};
    buffer.writeAnimation(.Idle, 0.5, &.{1});
    return buffer;
}

pub fn frameFromU16(frame_int: u32) PackedFrame {
    return @bitCast(frame_int);
}

pub fn f(frame: PackedFrame) u32 {
    return @bitCast(frame);
}

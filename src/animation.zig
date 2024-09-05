const std = @import("std");

pub const AnimationBufferReader = struct {
    ptr: *const anyopaque,
    impl: *const Interface,

    pub const Interface = struct {
        readAnimation: *const fn (ctx: *const anyopaque, animation_type: AnimationType) AnimationBufferError!AnimationData,
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

        pub fn reader(self: *const @This()) AnimationBufferReader {
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
            ctx: *const anyopaque,
            animation_type: AnimationType,
        ) !AnimationData {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
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
    frames: []const u8,
};

pub const AnimationType = enum(usize) {
    Idle,
    Walk,
    Roll,
    Hit,
    Death,
    Attack,
    Jump,
    Slipping,
};

pub const NoAnimationsBuffer = AnimationBuffer(&.{.Idle}, 1);
pub fn getNoAnimationsBuffer() NoAnimationsBuffer {
    var buffer = NoAnimationsBuffer{};
    buffer.writeAnimation(.Idle, 0.5, &.{1});
    return buffer;
}

const Behavior = @This();
const Platform = @import("platform.zig");
const rl = @import("raylib");
const shapes = @import("../shapes.zig");
const std = @import("std");

const MAX_NO_OF_STATES = 5;

state: [MAX_NO_OF_STATES * 8]u8 = undefined,
impl: *const Interface,

pub const Interface = struct {
    setup: *const fn (*Behavior) void,
    update: *const fn (*Behavior, *Platform, f32) void,
};

pub fn setup(self: *Behavior) void {
    return self.impl.setup(self);
}

pub fn update(self: *Behavior, platform: *Platform, delta_time: f32) void {
    return self.impl.update(self, platform, delta_time);
}

pub const KeyType = struct {
    key: []const u8,
    T: type,
};
pub fn StateManager(key_types: []const KeyType) type {
    if (key_types.len > MAX_NO_OF_STATES) {
        @compileError("Behavior state manager must have a number of key val pairs lesser than or equal to the max no of allowed states");
    }
    const index_map = std.StaticStringMap(usize).initComptime(blk: {
        comptime var kvs_list: []const struct { []const u8, usize } = &.{};
        for (key_types, 0..) |pair, i| {
            kvs_list = kvs_list ++ .{.{ pair.key, i * 8 }};
        }
        break :blk kvs_list;
    });
    const type_map = std.StaticStringMap(type).initComptime(blk: {
        comptime var kvs_list: []const struct { []const u8, type } = &.{};
        for (key_types) |pair| {
            if (@sizeOf(pair.T) > 64) {
                @compileError("State manager byte sizes bigger than 64 bytes are currently not supported");
            }
            kvs_list = kvs_list ++ .{.{ pair.key, pair.T }};
        }
        break :blk kvs_list;
    });
    return struct {
        pub fn getState(behavior: *Behavior, comptime key: []const u8) type_map.get(key).? {
            const T = type_map.get(key).?;
            const i = index_map.get(key).?;
            const state_bytes = behavior.state[i .. i + 8];
            return std.mem.bytesToValue(T, state_bytes);
        }

        pub fn setState(behavior: *Behavior, comptime key: []const u8, value: type_map.get(key).?) void {
            const i = index_map.get(key).?;
            const state_bytes = std.mem.toBytes(value);
            for (i..i + 8, 0..) |c, d| {
                behavior.state[c] = state_bytes[d];
            }
        }
    };
}

pub fn KeyframedMovement(keyframes: []const shapes.IPos, speed: f32) type {
    const State = StateManager(&.{.{
        .key = "keyframe_idx",
        .T = usize,
    }});

    return struct {
        pub fn init() Behavior {
            return .{ .impl = &.{
                .update = updateFn,
                .setup = setupFn,
            } };
        }

        inline fn getKeyframeIdx(b: *Behavior) usize {
            return State.getState(b, "keyframe_idx");
        }

        inline fn setKeyframeIdx(b: *Behavior, value: usize) void {
            return State.setState(b, "keyframe_idx", value);
        }

        pub fn setupFn(b: *Behavior) void {
            setKeyframeIdx(b, 0);
        }

        inline fn getAbsKeyframe(keyframe: shapes.IPos, platform: *Platform) shapes.IPos {
            var new = keyframe;
            new.x += @as(i32, @intFromFloat(@round(platform.initial_hitbox.x)));
            new.y += @as(i32, @intFromFloat(@round(platform.initial_hitbox.y)));
            return new;
        }

        pub fn updateFn(b: *Behavior, platform: *Platform, _: f32) void {
            var keyframe_idx = getKeyframeIdx(b);
            const platform_rect = platform.getHitboxRect();
            var abs_keyframe = getAbsKeyframe(keyframes[keyframe_idx], platform);

            if (@as(i32, @intFromFloat(platform_rect.x)) == abs_keyframe.x and @as(i32, @intFromFloat(platform_rect.y)) == abs_keyframe.y) {
                keyframe_idx = (keyframe_idx + 1) % keyframes.len;
                abs_keyframe = getAbsKeyframe(keyframes[keyframe_idx], platform);
                setKeyframeIdx(b, keyframe_idx);
            }

            const platform_pos = rl.Vector2{ .x = platform_rect.x, .y = platform_rect.y };
            platform.speed = (rl.Vector2{
                .x = @floatFromInt(abs_keyframe.x),
                .y = @floatFromInt(abs_keyframe.y),
            }).subtract(platform_pos).normalize().scale(speed);
        }
    };
}

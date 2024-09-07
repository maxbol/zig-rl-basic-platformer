const Behavior = @This();
const Platform = @import("platform.zig");
const rl = @import("raylib");
const std = @import("std");

const MAX_NO_OF_STATES = 5;

state: [MAX_NO_OF_STATES]usize = undefined,
impl: *const Interface,

pub const Interface = struct {
    update: *const fn (*Behavior, *Platform, f32) void,
};

pub fn update(self: *Behavior, platform: *Platform, delta_time: f32) void {
    return self.impl.update(self, platform, delta_time);
}

pub const KeyValPair = struct {
    key: []const u8,
    T: type,
};
pub fn StateManager(key_val_pairs: []KeyValPair) type {
    if (key_val_pairs.len > MAX_NO_OF_STATES) {
        @compileError("Behavior state manager must have a number of key val pairs lesser than or equal to the max no of allowed states");
    }
    const key_map = std.StaticStringMap(usize).initComptime(blk: {
        comptime var kvs_list = .{};
        for (key_val_pairs, 0..) |pair, i| {
            kvs_list = kvs_list ++ .{ pair.key, i };
        }
        break :blk kvs_list;
    });
    const type_map = std.StaticStringMap(type).initComptime(blk: {
        comptime var kvs_list = .{};
        for (key_val_pairs) |pair| {
            if (@sizeOf(pair.T) > 64) {
                @compileError("State manager byte sizes bigger than 64 bytes are currently not supported");
            }
            kvs_list = kvs_list ++ .{ pair.key, pair.T };
        }
        break :blk kvs_list;
    });
    return struct {
        pub fn getState(behavior: *Behavior, comptime key: []const u8) type_map.get(key) {
            const i = key_map.get(key);
            const state_bytes = behavior.state[i];
            const T = type_map.get(key);
            return std.mem.bytesToValue(T, std.mem.toBytes(state_bytes));
        }

        pub fn setState(behavior: *Behavior, comptime key: []const u8, value: type_map.get(key)) void {
            const i = key_map.get(key);
            const usize_val = std.mem.bytesToValue(usize, std.mem.toBytes(value));
            behavior.state[i] = usize_val;
        }
    };
}

pub fn KeyframedMovement(keyframes: []rl.Vector2, speed: f32) type {
    const stateManager = StateManager(&.{.{
        .key = "keyframe_idx",
        .T = usize,
    }}){};

    return struct {
        pub fn behavior() Behavior {
            return .{ .impl = &.{
                .update = updateFn,
            } };
        }

        fn getKeyframesIdx(b: *Behavior) usize {
            return stateManager.getState(b, "keyframe_idx");
        }

        pub fn updateFn(b: *Behavior, platform: *Platform, _: f32) void {
            var keyframe_idx = b.getKeyframesIdx();
            var current_keyframe = keyframes[keyframe_idx];
            const platform_rect = platform.getHitboxRect();

            if (platform_rect.x == current_keyframe.x and platform_rect.y == current_keyframe.y) {
                keyframe_idx = (keyframe_idx + 1) % keyframes.len;
                current_keyframe = keyframes[keyframe_idx];
                stateManager.setState(b, "keyframe_idx", keyframe_idx);
            }
            const platform_pos = rl.Vector2{ .x = platform_rect.x, .y = platform_rect.y };
            platform.speed = current_keyframe.subtract(platform_pos).normalize().scale(speed);
        }
    };
}

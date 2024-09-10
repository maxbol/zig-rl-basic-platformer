const Player = @import("../player.zig");
const Sprite = @import("../../sprite.zig");
const constants = @import("../../constants.zig");
const rl = @import("raylib");

var texture: ?rl.Texture = null;

fn loadTexture() rl.Texture {
    if (texture) |t| {
        return t;
    }
    texture = rl.loadTexture("assets/sprites/knight.png");
    return texture.?;
}

fn getAnimations() Player.AnimationBuffer {
    var buffer = Player.AnimationBuffer{};

    buffer.writeAnimation(.Idle, 0.5, &.{ 1, 2, 3, 4 });
    buffer.writeAnimation(.Jump, 0.1, &.{4});
    buffer.writeAnimation(.Walk, 1, blk: {
        var data: [16]u8 = undefined;
        for (17..33, 0..) |i, idx| {
            data[idx] = @intCast(i);
        }
        break :blk &data;
    });
    buffer.writeAnimation(.Roll, 0.8, blk: {
        var data: [8]u8 = undefined;
        for (41..49, 0..) |i, idx| {
            data[idx] = @intCast(i);
        }
        break :blk &data;
    });
    buffer.writeAnimation(.Hit, 0.15, blk: {
        var data: [3]u8 = undefined;
        // for (49..53, 0..) |i, idx| {
        for (49..52, 0..) |i, idx| {
            data[idx] = @intCast(i);
        }
        break :blk &data;
    });
    buffer.writeAnimation(.Death, 1, blk: {
        var data: [4]u8 = undefined;
        for (57..61, 0..) |i, idx| {
            data[idx] = @intCast(i);
        }
        break :blk &data;
    });
    buffer.writeAnimation(.Slipping, 0.3, blk: {
        var data: [16]u8 = undefined;
        for (17..33, 0..) |i, idx| {
            data[idx] = @intCast(i);
        }
        break :blk &data;
    });

    return buffer;
}

pub const Knight = Player.Prefab(
    .{ .x = 0, .y = 0, .width = constants.TILE_SIZE, .height = 20 },
    .{ .x = 8, .y = 8 },
    Sprite.Prefab(
        32,
        32,
        loadTexture,
        getAnimations(),
        Player.AnimationType.Idle,
        rl.Vector2{ .x = 0, .y = 0 },
    ),
);

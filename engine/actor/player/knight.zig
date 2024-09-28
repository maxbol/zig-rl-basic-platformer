const Player = @import("../player.zig");
const Sprite = @import("../../sprite.zig");
const an = @import("../../animation.zig");
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

fn getAnimationBuffer() Player.AnimationBuffer {
    // @compileLog("Building player/knight animation buffer...");
    var buffer = Player.AnimationBuffer{};

    buffer.writeAnimation(
        .Idle,
        0.5,
        &.{
            1,
            an.f(.{ .transform_mask = 0b1, .frame_idx = 2 }),
            3,
            4,
        },
    );
    buffer.writeAnimation(.Jump, 0.1, &.{4});
    buffer.writeAnimation(.Walk, 1, blk: {
        var data: [16]u32 = undefined;
        for (17..33, 0..) |i, idx| {
            data[idx] = @intCast(i);
        }
        break :blk &data;
    });
    buffer.writeAnimation(.Roll, 0.8, blk: {
        var data: [8]u32 = undefined;
        for (41..49, 0..) |i, idx| {
            data[idx] = @intCast(i);
        }
        break :blk &data;
    });
    buffer.writeAnimation(.Hit, 0.15, blk: {
        var data: [3]u32 = undefined;
        // for (49..53, 0..) |i, idx| {
        for (49..52, 0..) |i, idx| {
            data[idx] = @intCast(i);
        }
        break :blk &data;
    });
    buffer.writeAnimation(.Death, 1, blk: {
        var data: [4]u32 = undefined;
        for (57..61, 0..) |i, idx| {
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
        getAnimationBuffer(),
        Player.AnimationType.Idle,
        rl.Vector2{ .x = 0, .y = 0 },
    ),
);

const Player = @import("../player.zig");
const an = @import("../../animation.zig");
const constants = @import("../../constants.zig");
const rl = @import("raylib");

var texture: ?rl.Texture = null;

pub const Transforms = struct {
    pub fn rotate45Deg(frame: rl.RenderTexture) rl.RenderTexture {
        return an.Transforms.rotate(frame, 45, .Center);
    }

    pub fn scale3X(frame: rl.RenderTexture) rl.RenderTexture {
        return an.Transforms.scale(frame, 3);
    }
};

pub const SpriteBuffer = an.SpriteBuffer(
    Player.AnimationType,
    &.{
        .Idle,
        .Hit,
        .Walk,
        .Death,
        .Roll,
        .Jump,
    },
    .{
        Transforms.rotate45Deg,
        Transforms.scale3X,
    },
    loadTexture,
    .{ .x = 32, .y = 32 },
    16,
);

fn loadTexture() rl.Texture {
    if (texture) |t| {
        return t;
    }
    texture = rl.loadTexture("assets/sprites/knight.png");
    return texture.?;
}

var sprite_buffer: SpriteBuffer = buf: {
    var buffer = SpriteBuffer{};

    // @compileLog("Building player/knight animation buffer...");
    buffer.writeAnimation(
        .Idle,
        0.5,
        &.{
            1,
            2,
            3,
            4,
        },
    );
    // buffer.writeAnimation(.Jump, 0.1, &.{an.f(.{ .frame_pointer = 4, .transform_mask = 0b10 })});
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

    break :buf buffer;
};

fn getSpriteReader() an.AnySpriteBuffer {
    sprite_buffer.prebakeBuffer();
    return sprite_buffer.reader();
}

pub const Knight = Player.Prefab(
    .{ .x = 0, .y = 0, .width = constants.TILE_SIZE, .height = 20 },
    .{ .x = 0, .y = 4 },
    getSpriteReader,
);

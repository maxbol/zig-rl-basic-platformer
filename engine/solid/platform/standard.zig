const Platform = @import("../platform.zig");
const Sprite = @import("../../sprite.zig");
const an = @import("../../animation.zig");
const behavior = @import("../platform_behaviors.zig");
const rl = @import("raylib");
const std = @import("std");

var texture: ?rl.Texture2D = null;

fn loadTexture() rl.Texture2D {
    return texture orelse {
        texture = rl.loadTexture("assets/sprites/platforms.png");
        return texture.?;
    };
}

fn BuildPrefab(platform_type: u8, offset: usize, size: usize) type {
    const row = @divFloor(offset, 4);
    const col = offset % 4;

    const hitbox = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = size * 16,
        .height = 8,
    };

    const sprite_offset = rl.Vector2{
        .x = 0,
        .y = 0,
    };

    return Platform.Prefab(
        platform_type,
        hitbox,
        sprite_offset,
        struct {
            var sprite_buffer = blk: {
                var buffer = an.SpriteBuffer(
                    Platform.AnimationType,
                    &.{.Dull},
                    .{},
                    loadTexture,
                    .{ .x = size * 16, .y = 15 },
                    1,
                ){};

                buffer.writeAnimation(.Dull, 1, &.{1});

                buffer.texture_map_offset = rl.Vector2{
                    .x = col * 16,
                    .y = row * 16,
                };

                break :blk buffer;
            };
            fn getSpriteReader() an.AnySpriteBuffer {
                sprite_buffer.prebakeBuffer();
                return sprite_buffer.reader();
            }
        }.getSpriteReader,
        &.{behavior.KeyframedMovement(&.{ .{ .x = 0, .y = 0 }, .{ .x = 100, .y = 0 } }, 60)},
    );
}

pub const Platform1 = BuildPrefab(0, 0, 1);
pub const Platform2 = BuildPrefab(1, 1, 2);
pub const Platform3 = BuildPrefab(2, 4, 1);
pub const Platform4 = BuildPrefab(3, 5, 2);
pub const Platform5 = BuildPrefab(4, 8, 1);
pub const Platform6 = BuildPrefab(5, 9, 2);
pub const Platform7 = BuildPrefab(6, 12, 1);
pub const Platform8 = BuildPrefab(7, 13, 2);

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

fn BuildPrefab(offset: usize, size: usize) type {
    const row = @divFloor(offset, 4);
    const col = offset % 4;

    const hitbox = rl.Rectangle{
        .x = 0,
        .y = 0,
        .width = size * 16,
        .height = 9,
    };

    const sprite_offset = rl.Vector2{
        .x = 0,
        .y = 0,
    };

    const sprite_map_offset = rl.Vector2{
        .x = col * 16,
        .y = row * 16,
    };

    return Platform.Prefab(
        hitbox,
        sprite_offset,
        Sprite.Prefab(
            size * 16,
            16,
            loadTexture,
            an.getNoAnimationsBuffer(),
            an.NoAnimationsType.Idle,
            sprite_map_offset,
        ),
        &.{behavior.KeyframedMovement(&.{ .{ .x = 0, .y = 0 }, .{ .x = 100, .y = 0 } }, 60)},
    );
}

pub const Platform1 = BuildPrefab(0, 1);
pub const Platform2 = BuildPrefab(1, 2);
pub const Platform3 = BuildPrefab(4, 1);
pub const Platform4 = BuildPrefab(5, 2);
pub const Platform5 = BuildPrefab(8, 1);
pub const Platform6 = BuildPrefab(9, 2);
pub const Platform7 = BuildPrefab(12, 1);
pub const Platform8 = BuildPrefab(13, 2);

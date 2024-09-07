const Behavior = @import("../platform_behaviors.zig");
const Platform = @import("../platform.zig");
const Sprite = @import("../../sprite.zig");
const an = @import("../../animation.zig");
const rl = @import("raylib");

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
            .Idle,
            sprite_map_offset,
        ),
        &.{
            Behavior.KeyframedMovement(&.{}, 10).init(),
        },
    );
}

const Collectable = @This();
const Player = @import("../actor/player.zig");
const Scene = @import("../scene.zig");
const Sprite = @import("../sprite.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");

onCollected: *const fn (self: *Collectable, player: *Player) void,

collectable_type: u8,
hitbox: rl.Rectangle,
initial_hitbox: rl.Rectangle,
sprite: Sprite,
sprite_offset: rl.Vector2,
is_collected: bool = false,
is_deleted: bool = false,

pub fn stub() Collectable {
    return .{
        .collectable_type = undefined,
        .hitbox = undefined,
        .initial_hitbox = undefined,
        .sprite = undefined,
        .sprite_offset = undefined,
        .onCollected = undefined,
        .is_collected = false,
        .is_deleted = true,
    };
}

pub fn Prefab(
    collectable_type: u8,
    hitbox: rl.Rectangle,
    sprite_offset: rl.Vector2,
    SpritePrefab: anytype,
    onCollected: *const fn (self: *Collectable, player: *Player) void,
) type {
    return struct {
        pub const Sprite = SpritePrefab;

        pub fn init(pos: rl.Vector2) Collectable {
            const sprite = SpritePrefab.init();

            var collectable_hitbox = hitbox;
            collectable_hitbox.x = pos.x;
            collectable_hitbox.y = pos.y;

            return Collectable.init(collectable_type, collectable_hitbox, sprite, sprite_offset, onCollected);
        }
    };
}

pub fn init(collectable_type: u8, hitbox: rl.Rectangle, sprite: Sprite, sprite_offset: rl.Vector2, onCollected: *const fn (self: *Collectable, player: *Player) void) Collectable {
    return .{
        .collectable_type = collectable_type,
        .initial_hitbox = hitbox,
        .hitbox = hitbox,
        .sprite = sprite,
        .sprite_offset = sprite_offset,
        .onCollected = onCollected,
    };
}

pub fn getHitboxRect(self: *const Collectable) rl.Rectangle {
    return self.hitbox;
}

pub fn getInitialPos(self: *const Collectable) rl.Vector2 {
    return .{
        .x = self.initial_hitbox.x,
        .y = self.initial_hitbox.y,
    };
}

pub fn delete(self: *Collectable) void {
    self.is_deleted = true;
}

pub fn update(self: *Collectable, scene: *Scene, delta_time: f32) !void {
    if (self.is_collected or self.is_deleted) {
        return;
    }

    if (rl.checkCollisionRecs(scene.player.actor().getHitboxRect(), self.hitbox)) {
        self.is_collected = true;
        self.onCollected(self, scene.player);
    }

    try self.sprite.update(scene, delta_time);
}

pub fn draw(self: *const Collectable, scene: *const Scene) void {
    if (self.is_collected or self.is_deleted) {
        return;
    }
    const sprite_pos = helpers.getRelativePos(self.sprite_offset, self.hitbox);
    self.sprite.draw(scene, sprite_pos, rl.Color.white);
}

pub const Coin = @import("collectables/coin.zig").Coin;

pub const prefabs: [1]type = .{
    Coin,
};

pub fn initCollectableByIndex(index: usize, pos: rl.Vector2) !Collectable {
    inline for (prefabs, 0..) |CollectablePrefab, i| {
        if (i == index) {
            return CollectablePrefab.init(pos);
        }
    }
    return Scene.SpawnError.NoSuchItem;
}

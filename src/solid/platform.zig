const Platform = @import("platform.zig");
const Scene = @import("../scene.zig");
const Solid = @import("solid.zig");
const SolidCollidable = @import("solid_collidable.zig");
const Sprite = @import("../sprite.zig");
const Behavior = @import("platform_behaviors.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");

behaviors: []Behavior,
collidable: SolidCollidable,
initial_hitbox: rl.Rectangle,
is_deleted: bool = false,
sprite: Sprite,
sprite_offset: rl.Vector2,
speed: rl.Vector2 = .{ .x = 0, .y = 0 },

pub fn Prefab(hitbox: rl.Rectangle, sprite_offset: rl.Vector2, SpritePrefab: anytype, behaviors: []Behavior) type {
    return struct {
        pub const Sprite = SpritePrefab;
        pub const hitbox_static = hitbox;
        pub const spr_offset = sprite_offset;

        pub fn init(pos: rl.Vector2) Platform {
            const sprite = SpritePrefab.init();

            var platform_hitbox = hitbox;
            platform_hitbox.x += pos.x;
            platform_hitbox.y += pos.y;

            const behaviors_any: [behaviors.len]behavior.AnyBehavior = undefined;
            for (behaviors, 0..) |Behavior, i| {
                _ = b; // autofix
                behaviors_any[i] = behaviors[i].any();
            }

            return Platform.init(platform_hitbox, sprite, sprite_offset, behaviors_any);
        }
    };
}

pub fn init(hitbox: rl.Rectangle, sprite: Sprite, sprite_offset: rl.Vector2, behaviors: []behavior.AnyBehavior) Platform {
    _ = behaviors; // autofix
    return .{
        .collidable = SolidCollidable.init(hitbox),
        .initial_hitbox = hitbox,
        .sprite = sprite,
        .sprite_offset = sprite_offset,
    };
}

pub fn reset(self: *Platform) void {
    self.* = Platform.init(self.initial_hitbox, self.sprite);
    self.sprite.reset();
}

pub fn delete(self: *Platform) void {
    self.is_deleted = true;
}

pub fn solid(self: *Platform) Solid {
    return .{
        .ptr = self,
        .impl = &.{
            .getCollidable = getCollidableCast,
            .getHitboxRect = getHitboxRectCast,
        },
    };
}

pub inline fn getCollidable(self: *const Platform) SolidCollidable {
    return self.collidable;
}

pub inline fn getHitboxRect(self: *const Platform) rl.Rectangle {
    return self.collidable.hitbox;
}

pub fn getInitialPos(self: *const Platform) rl.Vector2 {
    return rl.Vector2.init(self.initial_hitbox.x, self.initial_hitbox.y);
}

fn getCollidableCast(ctx: *const anyopaque) SolidCollidable {
    const self: *const Platform = @ptrCast(@alignCast(ctx));
    return self.getCollidable();
}

fn getHitboxRectCast(ctx: *const anyopaque) rl.Rectangle {
    const self: *const Platform = @ptrCast(@alignCast(ctx));
    return self.getHitboxRect();
}

pub fn update(self: *Platform, scene: *Scene, delta_time: f32) !void {
    try self.sprite.update(scene, delta_time);
}

pub fn draw(self: *const Platform, scene: *const Scene) void {
    const sprite_pos = helpers.getRelativePos(self.sprite_offset, self.collidable.hitbox);
    self.sprite.draw(scene, sprite_pos, rl.Color.white);
}

pub const Platform1 = @import("platform/standard.zig").Platform1;
pub const Platform2 = @import("platform/standard.zig").Platform2;
pub const Platform3 = @import("platform/standard.zig").Platform3;
pub const Platform4 = @import("platform/standard.zig").Platform4;
pub const Platform5 = @import("platform/standard.zig").Platform5;
pub const Platform6 = @import("platform/standard.zig").Platform6;
pub const Platform7 = @import("platform/standard.zig").Platform7;
pub const Platform8 = @import("platform/standard.zig").Platform8;

pub const prefabs: [8]type = .{
    Platform1,
    Platform2,
    Platform3,
    Platform4,
    Platform5,
    Platform6,
    Platform7,
    Platform8,
};
pub fn initPlatformByIndex(index: usize, pos: rl.Vector2) !Platform {
    inline for (prefabs, 0..) |PlatformPrefab, i| {
        if (i == index) {
            return PlatformPrefab.init(pos);
        }
    }
    return Scene.SpawnError.NoSuchItem;
}

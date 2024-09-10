const Behavior = @import("platform_behaviors.zig");
const Platform = @import("platform.zig");
const RigidBody = @import("rigid_body.zig");
const Scene = @import("../scene.zig");
const Solid = @import("solid.zig");
const Sprite = @import("../sprite.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");
const shapes = @import("../shapes.zig");

pub const MAX_NO_OF_BEHAVIORS = 5;

behaviors: [MAX_NO_OF_BEHAVIORS]Behavior,
behaviors_amount: usize,
rigid_body: RigidBody,
initial_hitbox: rl.Rectangle,
is_collidable: bool = true,
is_deleted: bool = false,
sprite: Sprite,
sprite_offset: rl.Vector2,
speed: rl.Vector2 = .{ .x = 0, .y = 0 },

pub fn Prefab(hitbox: rl.Rectangle, sprite_offset: rl.Vector2, SpritePrefab: anytype, behaviors: anytype) type {
    return struct {
        pub const Sprite = SpritePrefab;
        pub const hitbox_static = hitbox;
        pub const spr_offset = sprite_offset;

        pub fn init(pos: shapes.IPos) Platform {
            const sprite = SpritePrefab.init();

            var platform_hitbox = hitbox;
            platform_hitbox.x += @floatFromInt(pos.x);
            platform_hitbox.y += @floatFromInt(pos.y);

            var behaviors_any: [Platform.MAX_NO_OF_BEHAVIORS]Behavior = undefined;
            const behaviors_amount = behaviors.len;
            inline for (behaviors, 0..) |B, i| {
                behaviors_any[i] = B.init();
                behaviors_any[i].setup();
            }

            return Platform.init(platform_hitbox, sprite, sprite_offset, behaviors_any, behaviors_amount);
        }
    };
}

pub fn init(
    hitbox: rl.Rectangle,
    sprite: Sprite,
    sprite_offset: rl.Vector2,
    behaviors: [MAX_NO_OF_BEHAVIORS]Behavior,
    behaviors_amount: usize,
) Platform {
    return .{
        .behaviors = behaviors,
        .behaviors_amount = behaviors_amount,
        .rigid_body = RigidBody.init(hitbox),
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
            .isCollidable = isCollidableCast,
            .getHitboxRect = getHitboxRectCast,
            .setIsCollidable = setIsCollidableCast,
        },
    };
}

pub inline fn isCollidable(self: *const Platform) bool {
    return self.is_collidable;
}

pub inline fn setIsCollidable(self: *Platform, is_collidable: bool) void {
    self.is_collidable = is_collidable;
}

pub inline fn getHitboxRect(self: *const Platform) rl.Rectangle {
    return self.rigid_body.hitbox;
}

pub fn getInitialPos(self: *const Platform) rl.Vector2 {
    return rl.Vector2.init(self.initial_hitbox.x, self.initial_hitbox.y);
}

fn isCollidableCast(ctx: *const anyopaque) bool {
    const self: *const Platform = @ptrCast(@alignCast(ctx));
    return self.isCollidable();
}

fn setIsCollidableCast(ctx: *anyopaque, is_collidable: bool) void {
    const self: *Platform = @ptrCast(@alignCast(ctx));
    self.setIsCollidable(is_collidable);
}

fn getHitboxRectCast(ctx: *const anyopaque) rl.Rectangle {
    const self: *const Platform = @ptrCast(@alignCast(ctx));
    return self.getHitboxRect();
}

pub fn update(self: *Platform, scene: *Scene, delta_time: f32) !void {
    try self.sprite.update(scene, delta_time);

    for (0..self.behaviors_amount) |i| {
        self.behaviors[i].update(self, delta_time);
    }

    if (self.speed.x != 0 or self.speed.y != 0) {
        self.rigid_body.move(scene, self.solid(), self.speed.x * delta_time, self.speed.y * delta_time);
    }
}

pub fn draw(self: *const Platform, scene: *const Scene) void {
    const sprite_pos = helpers.getRelativePos(self.sprite_offset, self.rigid_body.hitbox);
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
pub fn initPlatformByIndex(index: usize, pos: shapes.IPos) !Platform {
    inline for (prefabs, 0..) |PlatformPrefab, i| {
        if (i == index) {
            return PlatformPrefab.init(pos);
        }
    }
    return Scene.SpawnError.NoSuchItem;
}

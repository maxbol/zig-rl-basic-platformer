const Effect = @This();
const Scene = @import("scene.zig");
const Sprite = @import("sprite.zig");
const an = @import("animation.zig");
const rl = @import("raylib");
const std = @import("std");

pub const AnimationType = enum(u8) {
    Invisible,
    Playing,
};

pub const AnimationBuffer = an.AnimationBuffer(
    AnimationType,
    &.{
        .Invisible,
        .Playing,
    },
    6,
);

pub fn Prefab(SpritePrefab: type) type {
    return struct {
        pub const width = SpritePrefab.SIZE_X;
        pub const height = SpritePrefab.SIZE_Y;

        pub fn init(pos: rl.Vector2, onEffectFinished: Sprite.Callback, x_flip: bool) Effect {
            var sprite = SpritePrefab.init();
            sprite.setFlip(.XFlip, x_flip);
            return Effect.init(pos, sprite, onEffectFinished);
        }
    };
}

onEffectFinished: Sprite.Callback,
position: rl.Vector2,
sprite: Sprite,
initialized: bool = false,

pub fn init(pos: rl.Vector2, sprite: Sprite, onEffectFinished: Sprite.Callback) Effect {
    return .{ .position = pos, .sprite = sprite, .onEffectFinished = onEffectFinished };
}

fn onAnimationFinished(ctx: *anyopaque, sprite: *Sprite, scene: *Scene) void {
    const self: *Effect = @ptrCast(@alignCast(ctx));

    sprite.setAnimation(AnimationType.Invisible, .{});

    self.onEffectFinished.call(
        sprite,
        scene,
    );
}

pub fn update(self: *Effect, scene: *Scene, dt: f32) !void {
    if (!self.initialized) {
        self.sprite.setAnimation(
            AnimationType.Playing,
            .{
                .on_animation_finished = .{
                    .call_ptr = onAnimationFinished,
                    .context = self,
                },
            },
        );
        self.initialized = true;
    }
    try self.sprite.update(scene, dt);
}

pub fn draw(self: *const Effect, scene: *const Scene) void {
    self.sprite.draw(scene, self.position, rl.Color.white);
}

pub const Dust = @import("effect/dust.zig").Dust;

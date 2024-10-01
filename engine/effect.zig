const Effect = @This();
const Scene = @import("scene.zig");
const Sprite = @import("sprite.zig");
const an = @import("animation.zig");
const rl = @import("raylib");
const shapes = @import("shapes.zig");
const std = @import("std");

pub const AnimationType = enum(u8) {
    Invisible,
    Playing,
};

pub fn Prefab(getSpriteReader: *const fn () an.AnySpriteBuffer, sprite_size: shapes.IPos) type {
    return struct {
        pub const width = sprite_size.x;
        pub const height = sprite_size.y;
        pub const sprite_reader = getSpriteReader;

        pub fn init(pos: rl.Vector2, onEffectFinished: an.Animation.Callback, x_flip: bool) Effect {
            var sprite: an.Sprite = sprite_reader().sprite() catch @panic("Failed to read sprite");
            sprite.flip_mask.x = x_flip;
            return Effect.init(pos, sprite, onEffectFinished);
        }
    };
}

onEffectFinished: an.Animation.Callback,
position: rl.Vector2,
sprite: an.Sprite,
initialized: bool = false,

pub fn init(pos: rl.Vector2, sprite: an.Sprite, onEffectFinished: an.Animation.Callback) Effect {
    return .{ .position = pos, .sprite = sprite, .onEffectFinished = onEffectFinished };
}

fn onAnimationFinished(ctx: *anyopaque, animation: *an.Animation) void {
    const self: *Effect = @ptrCast(@alignCast(ctx));
    self.sprite.setAnimation(AnimationType.Invisible, .{});
    self.onEffectFinished.call(animation);
}

pub fn update(self: *Effect, scene: *Scene, dt: f32) !void {
    _ = scene; // autofix
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

    self.sprite.update(dt);
}

pub fn draw(self: *const Effect, scene: *const Scene) void {
    const pos = an.DrawPosition.init(self.position, .TopLeft, .{ .x = 0, .y = 0 });
    self.sprite.draw(scene, pos, rl.Color.white);
}

pub const Dust = @import("effect/dust.zig").Dust;

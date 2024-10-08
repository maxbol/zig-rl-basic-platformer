const Effect = @This();
const Scene = @import("scene.zig");
const an = @import("animation.zig");
const rl = @import("raylib");
const shapes = @import("shapes.zig");
const std = @import("std");

pub const AnimationType = enum(u8) {
    Stopped,
    Playing,
};

pub fn Prefab(getSpriteReader: *const fn () an.AnySpriteBuffer, sprite_size: shapes.IPos, autoplay: bool) type {
    return struct {
        pub const width = sprite_size.x;
        pub const height = sprite_size.y;
        pub const sprite_reader = getSpriteReader;

        pub fn init(pos: an.DrawPosition, onEffectFinished: ?an.Animation.Callback, x_flip: bool) Effect {
            var sprite: an.Sprite = sprite_reader().sprite() catch @panic("Failed to read sprite");
            sprite.flip_mask.x = x_flip;
            return Effect.init(pos, sprite, onEffectFinished, autoplay);
        }
    };
}

onEffectFinished: ?an.Animation.Callback,
position: an.DrawPosition,
sprite: an.Sprite,
initialized: bool = false,
autoplay: bool,

pub fn init(pos: an.DrawPosition, sprite: an.Sprite, onEffectFinished: ?an.Animation.Callback, autoplay: bool) Effect {
    return .{ .position = pos, .sprite = sprite, .onEffectFinished = onEffectFinished, .autoplay = autoplay };
}

fn handleAnimationFinished(ctx: *anyopaque, animation: *an.Animation) void {
    const self: *Effect = @ptrCast(@alignCast(ctx));
    self.stop();
    if (self.onEffectFinished) |onEffectFinished| {
        onEffectFinished.call(animation);
    }
}

pub fn stop(self: *Effect) void {
    self.sprite.setAnimation(AnimationType.Stopped, .{});
}

pub fn play(self: *Effect) void {
    self.sprite.setAnimation(
        AnimationType.Playing,
        .{
            .on_animation_finished = .{
                .call_ptr = handleAnimationFinished,
                .context = self,
            },
        },
    );
}

pub fn update(self: *Effect, scene: *Scene, dt: f32) !void {
    _ = scene; // autofix
    if (self.autoplay) {
        self.play();
        self.autoplay = false;
    }

    self.sprite.update(dt);
}

pub fn draw(self: *const Effect, scene: *const Scene) void {
    self.sprite.draw(scene, self.position, rl.Color.white);
}

pub const Dust = @import("effect/dust.zig").Dust;
pub const weapons = @import("effect/weapons.zig");

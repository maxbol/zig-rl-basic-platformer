const Actor = @import("actor.zig");
const Effect = @import("../effect.zig");
const Scene = @import("../scene.zig");
const Weapon = @This();
const an = @import("../animation.zig");
const rl = @import("raylib");

face_dir: i2 = 1,
type: u8,
pos: an.DrawPosition,
sprite: an.Sprite,

pub const AnimationType = enum(u8) {
    CarriedLeft,
    CarriedRight,
    AttackRight,
    AttackLeft,
};

pub fn Prefab(weapon_type: u8, getSpriteReader: *const fn () an.AnySpriteBuffer) type {
    return struct {
        pub const sprite_reader = getSpriteReader;

        pub fn init() Weapon {
            const sprite = sprite_reader().sprite() catch @panic("Failed to read sprite");
            return .{
                .pos = an.DrawPosition.init(.{ .x = 0, .y = 0, .width = 0, .height = 0 }, .Center, .{ .x = 0, .y = 0 }),
                .type = weapon_type,
                .sprite = sprite,
            };
        }
    };
}

pub fn init(sprite: an.Sprite) Weapon {
    return .{
        .sprite = sprite,
    };
}

fn revertToCarried(ctx: *anyopaque, _: *an.Animation) void {
    const self: *Weapon = @ptrCast(@alignCast(ctx));
    self.sprite.setAnimation(if (self.face_dir == 1) AnimationType.CarriedRight else AnimationType.CarriedLeft, .{});
}

pub fn attack(self: *Weapon, actor: Actor) void {
    _ = actor; // autofix
    const attack_type = if (self.face_dir == -1) AnimationType.AttackLeft else AnimationType.AttackRight;

    self.sprite.setAnimation(attack_type, .{ .on_animation_finished = .{
        .context = self,
        .call_ptr = revertToCarried,
    } });
}

pub fn update(self: *Weapon, scene: *Scene, actor: Actor, delta_time: f32) !void {
    _ = scene; // autofix
    const actor_sprite = actor.getSprite();
    const sprite_flip_mask = actor_sprite.flip_mask;

    self.face_dir = if (actor_sprite.flip_mask.x) -1 else 1;

    if (self.sprite.animation.anim_data.type == @intFromEnum(AnimationType.CarriedLeft) or
        self.sprite.animation.anim_data.type == @intFromEnum(AnimationType.CarriedRight))
    {
        self.sprite.setAnimation(if (self.face_dir == 1) AnimationType.CarriedRight else AnimationType.CarriedLeft, .{});
    }

    self.pos = an.DrawPosition.init(
        actor.getHitboxRect(),
        if (self.face_dir == 1) .CenterLeft else .CenterRight,
        .{ .x = @as(f32, @floatFromInt(self.face_dir)) * 2, .y = -5 },
    );
    self.sprite.flip_mask = sprite_flip_mask;

    self.sprite.update(delta_time);
}

pub fn draw(self: *const Weapon, scene: *const Scene) void {
    self.sprite.draw(scene, self.pos, rl.Color.white);
}

pub const WeaponExcalibur = @import("weapons/excalibur.zig").WeaponExcalibur;

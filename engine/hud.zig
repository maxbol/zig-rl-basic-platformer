const Collectable = @import("actor/collectable.zig");
const Player = @import("actor/player.zig");
const HUD = @This();
const Scene = @import("scene.zig");
const Sprite = @import("sprite.zig");
const an = @import("animation.zig");
const rl = @import("raylib");
const std = @import("std");
const tracing = @import("tracing.zig");

player: *Player,
sprite_lives: an.Sprite,
sprite_points: an.Sprite,
font: rl.Font = undefined,

pub fn init(player: *Player, font: rl.Font) HUD {
    const sprite_lives = Collectable.HealthGrape.sprite_reader().sprite() catch @panic("Failed to read sprite");
    const sprite_points = Collectable.Coin.sprite_reader().sprite() catch @panic("Failed to read sprite");
    return .{
        .player = player,
        .sprite_lives = sprite_lives,
        .sprite_points = sprite_points,
        .font = font,
    };
}

pub fn update(self: *HUD, delta_time: f32) void {
    const zone = tracing.ZoneN(@src(), "HUD Update");
    defer zone.End();

    self.sprite_points.update(delta_time);
    self.sprite_lives.update(delta_time);
}

pub fn draw(self: *HUD, scene: *const Scene) void {
    const zone = tracing.ZoneN(@src(), "HUD Draw");
    defer zone.End();

    const lives_left = self.player.lives;
    const points_gained = self.player.score;

    const lives_draw_x = scene.gamestate.viewport.rectangle.x + 10;
    const lives_draw_y = scene.gamestate.viewport.rectangle.y + 10;

    const sprite_points_frame = self.sprite_points.animation.getFrame() orelse return;
    const sprite_lives_frame = self.sprite_lives.animation.getFrame() orelse return;

    const sprite_points_size_x = @as(f32, @floatFromInt(sprite_points_frame.width));
    const sprite_points_size_y = @as(f32, @floatFromInt(sprite_points_frame.height));
    const sprite_lives_size_x = @as(f32, @floatFromInt(sprite_lives_frame.width));
    const sprite_lives_size_y = @as(f32, @floatFromInt(sprite_lives_frame.height));
    _ = sprite_lives_size_x; // autofix
    _ = sprite_lives_size_y; // autofix
    _ = sprite_points_size_y; // autofix

    const points_draw_x = scene.gamestate.viewport.rectangle.x + scene.gamestate.viewport.rectangle.width - sprite_points_size_x - 10;
    const points_draw_y = scene.gamestate.viewport.rectangle.y + 10;

    for (0..Player.max_lives) |i| {
        const pos = .{ .x = lives_draw_x + @as(f32, @floatFromInt(i * 20)), .y = lives_draw_y };
        const color = if (i < lives_left) rl.Color.white else rl.Color.white.fade(0.2);
        self.sprite_lives.drawDirect(pos, color);
    }

    self.sprite_points.drawDirect(.{ .x = points_draw_x, .y = points_draw_y }, rl.Color.white);

    var points_fmt_buf: [20]u8 = undefined;
    const points_str = std.fmt.bufPrintZ(&points_fmt_buf, "{d: <10}", .{points_gained}) catch {
        @panic("Failed to format points string");
    };

    rl.drawTextEx(
        self.font,
        points_str,
        .{ .x = points_draw_x - 50 + 1, .y = points_draw_y + 3 + 1 },
        9,
        0,
        rl.Color.black,
    );
    rl.drawTextEx(
        self.font,
        points_str,
        .{ .x = points_draw_x - 50, .y = points_draw_y + 3 },
        9,
        0,
        rl.Color.white,
    );
}

const Collectable = @import("actor/collectable.zig");
const Player = @import("actor/player.zig");
const HUD = @This();
const Scene = @import("scene.zig");
const Sprite = @import("sprite.zig");
const rl = @import("raylib");
const std = @import("std");

player: *Player,
sprite_lives: Sprite,
sprite_points: Sprite,
font: rl.Font = undefined,

pub fn init(player: *Player, font: rl.Font) HUD {
    const sprite_lives = Collectable.HealthGrape.Sprite.init();
    const sprite_points = Collectable.Coin.Sprite.init();
    return .{
        .player = player,
        .sprite_lives = sprite_lives,
        .sprite_points = sprite_points,
        .font = font,
    };
}

pub fn update(self: *HUD, scene: *Scene, delta_time: f32) !void {
    try self.sprite_points.update(scene, delta_time);
    try self.sprite_lives.update(scene, delta_time);
}

pub fn draw(self: *HUD, scene: *const Scene) void {
    const lives_left = self.player.lives;
    const points_gained = self.player.score;

    const lives_draw_x = scene.gamestate.viewport.rectangle.x + 10;
    const lives_draw_y = scene.gamestate.viewport.rectangle.y + 10;

    const points_draw_x = scene.gamestate.viewport.rectangle.x + scene.gamestate.viewport.rectangle.width - self.sprite_points.size.x - 10;
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

const Actor = @import("actor/actor.zig");
const std = @import("std");
const rl = @import("raylib");

pub const RAD2DEG = 180.0 / std.math.pi;

pub const WINDOW_SIZE_X = 1600;
pub const WINDOW_SIZE_Y = 900;

pub const GAME_SIZE_X = 640;
pub const GAME_SIZE_Y = 360;

pub const TILE_SIZE = 16;
pub const BIGGEST_MOB_SPRITE_SIZE = Actor.Mob.getBiggestMobSpriteSize();

pub const VIEWPORT_PADDING_X = TILE_SIZE + (GAME_SIZE_X % TILE_SIZE / 2);
pub const VIEWPORT_PADDING_Y = TILE_SIZE + (GAME_SIZE_Y % TILE_SIZE / 2);

pub const VIEWPORT_BIG_WIDTH = GAME_SIZE_X - (VIEWPORT_PADDING_X * 2);
pub const VIEWPORT_BIG_HEIGHT = GAME_SIZE_Y - (VIEWPORT_PADDING_Y * 2);

pub const VIEWPORT_SMALL_WIDTH = VIEWPORT_BIG_WIDTH - (TILE_SIZE * 10);
pub const VIEWPORT_SMALL_HEIGHT = VIEWPORT_BIG_HEIGHT - (TILE_SIZE * 5);

pub const VIEWPORT_BIG_RECT = rl.Rectangle.init(
    VIEWPORT_PADDING_X,
    VIEWPORT_PADDING_Y,
    VIEWPORT_BIG_WIDTH,
    VIEWPORT_BIG_HEIGHT,
);
pub const VIEWPORT_SMALL_RECT = rl.Rectangle.init(
    VIEWPORT_PADDING_X,
    VIEWPORT_PADDING_Y,
    VIEWPORT_SMALL_WIDTH,
    VIEWPORT_SMALL_HEIGHT,
);

pub const PATH_SCENES = "scenes/";

pub const MOB_AMOUNT = 20;
pub const MOB_SPACING = 200;

pub const MAX_AMOUNT_OF_BG_LAYERS = 2;
pub const MAX_AMOUNT_OF_FG_LAYERS = 1;

pub const MAX_AMOUNT_OF_MOBS = 3100;

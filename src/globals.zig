const Actor = @import("actor/actor.zig");
const Editor = @import("editor.zig");
const Scene = @import("scene.zig");
const Sprite = @import("sprite.zig");
const TileLayer = @import("tile_layer/tile_layer.zig");
const Viewport = @import("viewport.zig");
const constants = @import("constants.zig");
const controls = @import("controls.zig");
const debug = @import("debug.zig");
const rl = @import("raylib");
const static = @import("static.zig");
const std = @import("std");

pub var debug_flags: []const debug.DebugFlag = undefined;
pub var editor: *Editor = undefined;
pub var editor_mode: bool = false;
pub var font: rl.Font = undefined;
pub var mob_actors: [constants.MOB_AMOUNT]Actor = undefined;
pub var mobs: [constants.MOB_AMOUNT]Actor.Mob = undefined;
pub var mobs_starting_pos: [constants.MOB_AMOUNT]rl.Vector2 = undefined;
pub var music: rl.Music = undefined;
pub var on_save_sfx: rl.Sound = undefined;
pub var player: Actor.Player = undefined;
pub var player_animations: static.PlayerAnimationBuffer = undefined;
pub var rand: std.Random = undefined;
pub var scene_file = "data/scenes/level1.scene";
// pub var slime_animations: static.MobAnimationBuffer = undefined;
pub var viewport: Viewport = undefined;
pub var vmouse = controls.VirtualMouse{};

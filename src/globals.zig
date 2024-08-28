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

pub var bg_layers: [constants.MAX_AMOUNT_OF_BG_LAYERS]?static.BgTileLayer = .{null} ** constants.MAX_AMOUNT_OF_BG_LAYERS;
pub var bg_layers_count: u8 = 0;
pub var debug_flags: []const debug.DebugFlag = undefined;
pub var editor: Editor = undefined;
pub var editor_mode: bool = false;
pub var fg_layers: [constants.MAX_AMOUNT_OF_FG_LAYERS]?static.FgTileLayer = .{null} ** constants.MAX_AMOUNT_OF_FG_LAYERS;
pub var fg_layers_count: u8 = 0;
pub var main_layer: static.MainLayer = undefined;
pub var mob_actors: [constants.MOB_AMOUNT]Actor = undefined;
pub var mobs: [constants.MOB_AMOUNT]Actor.Mob = undefined;
pub var player: Actor.Player = undefined;
pub var player_animations: static.PlayerAnimationBuffer = undefined;
pub var rand: std.Random = undefined;
pub var scene: Scene = undefined;
pub var slime_animations: static.MobAnimationBuffer = undefined;
pub var tileset_image: rl.Image = undefined;
pub var tileset: static.Tileset512 = undefined;
pub var viewport: Viewport = undefined;
pub var vmouse = controls.VirtualMouse{};

var bg_layers_pointers: [constants.MAX_AMOUNT_OF_BG_LAYERS]TileLayer = undefined;
pub fn getBgLayers() []TileLayer {
    for (0..bg_layers_count) |idx| {
        bg_layers_pointers[idx] = (bg_layers[idx] orelse @panic("Out of bound load of bg layer")).tileLayer();
    }
    return bg_layers_pointers[0..bg_layers_count];
}

var fg_layers_pointers: [constants.MAX_AMOUNT_OF_FG_LAYERS]TileLayer = undefined;
pub fn getFgLayers() []TileLayer {
    for (0..fg_layers_count) |idx| {
        fg_layers_pointers[idx] = (fg_layers[idx] orelse @panic("Out of bound load of fg layer")).tileLayer();
    }
    return fg_layers_pointers[0..fg_layers_count];
}

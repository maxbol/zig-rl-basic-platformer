const Actor = @import("actor/actor.zig");
const Collectable = @import("collectable/collectable.zig");
const Editor = @This();
const Overlay = @import("editor/overlay.zig");
const Palette = @import("editor/palette.zig");
const Scene = @import("scene.zig");
const Sprite = @import("sprite.zig");
const TileLayer = @import("tile_layer/tile_layer.zig");
const an = @import("animation.zig");
const constants = @import("constants.zig");
const controls = @import("controls.zig");
const globals = @import("globals.zig");
const helpers = @import("helpers.zig");
const rg = @import("raygui");
const rl = @import("raylib");
const shapes = @import("shapes.zig");
const std = @import("std");

allocator: std.mem.Allocator,

active_layer: TileLayer,
scene: *Scene,
vmouse: *controls.VirtualMouse,

active_palette: Palette.ActivePaletteType,

palette_collectables: *Palette.CollectablePalette,
palette_mob: *Palette.MobPalette,
palette_tiles: *Palette.TilePalette,

overlay_collectables: *Overlay.CollectableOverlay,
overlay_mob: *Overlay.MobOverlay,
overlay_tiles: *Overlay.TileOverlay,

save_btn_rect: rl.Rectangle = undefined,
save_btn_hover: bool = false,

const tile_palette_cols_per_row = 9;

pub fn create(allocator: std.mem.Allocator, scene: *Scene, vmouse: *controls.VirtualMouse) !*Editor {
    const palette_mob = try allocator.create(Palette.MobPalette);
    const palette_collectables = try allocator.create(Palette.CollectablePalette);
    const palette_tiles = try allocator.create(Palette.TilePalette);
    const overlay_collectables = try allocator.create(Overlay.CollectableOverlay);
    const overlay_mob = try allocator.create(Overlay.MobOverlay);
    const overlay_tiles = try allocator.create(Overlay.TileOverlay);
    const editor = try allocator.create(Editor);

    palette_mob.* = Palette.MobPalette.init(
        onFocus,
        constants.VIEWPORT_PADDING_X,
        constants.GAME_SIZE_Y - Palette.MobPalette.window_height - constants.VIEWPORT_PADDING_X,
    );
    palette_collectables.* = Palette.CollectablePalette.init(
        onFocus,
        constants.VIEWPORT_PADDING_X + (palette_mob.window.width) + 10,
        constants.GAME_SIZE_Y - (Palette.CollectablePalette.window_height) - constants.VIEWPORT_PADDING_X,
    );
    palette_tiles.* = Palette.TilePalette.init(onFocus);

    overlay_mob.* = Overlay.MobOverlay.init(palette_mob, &scene.mobs);
    overlay_collectables.* = Overlay.CollectableOverlay.init(palette_collectables, &scene.collectables);
    overlay_tiles.* = Overlay.TileOverlay.init(palette_tiles);

    editor.* = Editor{
        .allocator = allocator,
        .active_palette = .None,
        .palette_mob = palette_mob,
        .palette_collectables = palette_collectables,
        .palette_tiles = palette_tiles,
        .active_layer = scene.main_layer,
        .scene = scene,
        .vmouse = vmouse,
        .overlay_mob = overlay_mob,
        .overlay_collectables = overlay_collectables,
        .overlay_tiles = overlay_tiles,
    };

    editor.initSaveButton();

    return editor;
}

pub fn destroy(self: *Editor) void {
    self.allocator.destroy(self.overlay_mob);
    self.allocator.destroy(self.overlay_collectables);
    self.allocator.destroy(self.overlay_tiles);
    self.allocator.destroy(self.palette_mob);
    self.allocator.destroy(self.palette_collectables);
    self.allocator.destroy(self.palette_tiles);
    self.allocator.destroy(self);
}

fn onFocus(self: *Editor, palette_type: Palette.ActivePaletteType) void {
    self.active_palette = palette_type;
}

fn initSaveButton(self: *Editor) void {
    self.save_btn_rect = rl.Rectangle.init(
        constants.GAME_SIZE_X - 100,
        constants.GAME_SIZE_Y - 50,
        100 - constants.VIEWPORT_PADDING_X,
        50 - constants.VIEWPORT_PADDING_Y,
    );
}

fn updateSaveButton(self: *Editor) void {
    self.save_btn_hover = rl.checkCollisionPointRec(self.vmouse.pos, self.save_btn_rect);

    if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left) and self.save_btn_hover) {
        const file = helpers.openFile(globals.scene_file, .{ .mode = .write_only }) catch {
            std.log.err("Failed to open file {s}\n", .{globals.scene_file});
            std.process.exit(1);
        };
        self.scene.writeBytes(file.writer(), false) catch |err| {
            std.log.err("Failed to write scene to file: {!}\n", .{err});
            std.process.exit(1);
        };

        rl.playSound(globals.on_save_sfx);
    }
}

fn drawSaveButton(self: *const Editor) void {
    const color = if (self.save_btn_hover) rl.Color.green else rl.Color.white;
    rl.drawTextEx(globals.font, "Save", rl.Vector2.init(self.save_btn_rect.x + 5, self.save_btn_rect.y + 5), 18, 2, color);
    rl.drawRectangleLinesEx(self.save_btn_rect, 2, color);
}

pub fn update(self: *Editor, delta_time: f32) !void {
    self.palette_tiles.update(self, delta_time);
    try self.palette_mob.update(self, delta_time);
    try self.palette_collectables.update(self, delta_time);

    switch (self.active_palette) {
        .None => {},
        .Tile => {
            self.overlay_tiles.update(self, delta_time);
        },
        .Collectable => {
            try self.overlay_collectables.update(self, delta_time);
        },
        .Mob => {
            try self.overlay_mob.update(self, delta_time);
        },
    }

    self.updateSaveButton();
}

pub fn draw(self: *const Editor) void {
    self.palette_tiles.draw(self, self.active_palette == .Tile);
    self.palette_mob.draw(self, self.active_palette == .Mob);
    self.palette_collectables.draw(self, self.active_palette == .Collectable);

    switch (self.active_palette) {
        .None => {},
        .Tile => {
            self.overlay_tiles.draw(self);
        },
        .Collectable => {
            self.overlay_collectables.draw(self);
        },
        .Mob => {
            self.overlay_mob.draw(self);
        },
    }
    self.drawSaveButton();
}

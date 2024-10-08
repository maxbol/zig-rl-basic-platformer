const Actor = @import("actor/actor.zig");
const Editor = @This();
const GameState = @import("gamestate.zig");
const Overlay = @import("editor/overlay.zig");
const Palette = @import("editor/palette.zig");
const Scene = @import("scene.zig");
const TileLayer = @import("tile_layer/tile_layer.zig");
const an = @import("animation.zig");
const constants = @import("constants.zig");
const controls = @import("controls.zig");
const helpers = @import("helpers.zig");
const rg = @import("raygui");
const rl = @import("raylib");
const tracing = @import("tracing.zig");
const shapes = @import("shapes.zig");
const std = @import("std");

allocator: std.mem.Allocator,

active_layer_idx: i16,
gamestate: *GameState,
scene: *Scene,
vmouse: *controls.VirtualMouse,

active_palette: Palette.ActivePaletteType,

palette_collectables: *Palette.CollectablePalette,
palette_mob: *Palette.MobPalette,
palette_platform: *Palette.PlatformPalette,
palette_mysterybox: *Palette.MysteryBoxPalette,
palette_tiles: *Palette.TilePalette,

overlay_collectables: Overlay.CollectableOverlay,
overlay_mob: Overlay.MobOverlay,
overlay_platform: Overlay.PlatformOverlay,
overlay_mysterybox: Overlay.MysteryBoxOverlay,
overlay_tiles: Overlay.TileOverlay,

save_btn_rect: rl.Rectangle = undefined,
save_btn_hover: bool = false,

const tile_palette_cols_per_row = 9;

pub fn create(allocator: std.mem.Allocator, gamestate: *GameState, scene: *Scene, vmouse: *controls.VirtualMouse) !*Editor {
    const palette_mob = try allocator.create(Palette.MobPalette);
    const palette_collectables = try allocator.create(Palette.CollectablePalette);
    const palette_platform = try allocator.create(Palette.PlatformPalette);
    const palette_mysterybox = try allocator.create(Palette.MysteryBoxPalette);
    const palette_tiles = try allocator.create(Palette.TilePalette);
    const editor = try allocator.create(Editor);

    var x_adjust: f32 = constants.VIEWPORT_PADDING_X;
    palette_mob.* = Palette.MobPalette.init(
        onFocus,
        x_adjust,
        constants.GAME_SIZE_Y - Palette.MobPalette.window_height - constants.VIEWPORT_PADDING_Y,
    );
    x_adjust += palette_mob.window.width + 10;
    palette_collectables.* = Palette.CollectablePalette.init(
        onFocus,
        x_adjust,
        constants.GAME_SIZE_Y - Palette.CollectablePalette.window_height - constants.VIEWPORT_PADDING_Y,
    );
    x_adjust += palette_collectables.window.width + 10;
    palette_platform.* = Palette.PlatformPalette.init(
        onFocus,
        x_adjust,
        constants.GAME_SIZE_Y - Palette.PlatformPalette.window_height - constants.VIEWPORT_PADDING_Y,
    );
    x_adjust += palette_platform.window.width + 10;
    palette_mysterybox.* = Palette.MysteryBoxPalette.init(
        onFocus,
        x_adjust,
        constants.GAME_SIZE_Y - Palette.MysteryBoxPalette.window_height - constants.VIEWPORT_PADDING_Y,
    );

    palette_tiles.* = Palette.TilePalette.init(onFocus);

    const overlay_mob = Overlay.MobOverlay.init(palette_mob, &scene.mobs);
    const overlay_collectables = Overlay.CollectableOverlay.init(palette_collectables, &scene.collectables);
    const overlay_platform = Overlay.PlatformOverlay.init(palette_platform, &scene.platforms);
    const overlay_mysterybox = Overlay.MysteryBoxOverlay.init(palette_mysterybox, &scene.mystery_boxes);
    const overlay_tiles = Overlay.TileOverlay.init(palette_tiles);

    editor.* = Editor{
        .active_layer_idx = 0,
        .active_palette = .None,
        .allocator = allocator,
        .gamestate = gamestate,
        .overlay_collectables = overlay_collectables,
        .overlay_mob = overlay_mob,
        .overlay_mysterybox = overlay_mysterybox,
        .overlay_platform = overlay_platform,
        .overlay_tiles = overlay_tiles,
        .palette_collectables = palette_collectables,
        .palette_mob = palette_mob,
        .palette_mysterybox = palette_mysterybox,
        .palette_platform = palette_platform,
        .palette_tiles = palette_tiles,
        .scene = scene,
        .vmouse = vmouse,
    };

    editor.initSaveButton();

    return editor;
}

pub fn destroy(self: *Editor) void {
    self.allocator.destroy(self.palette_mob);
    self.allocator.destroy(self.palette_collectables);
    self.allocator.destroy(self.palette_platform);
    self.allocator.destroy(self.palette_mysterybox);
    self.allocator.destroy(self.palette_tiles);
    self.allocator.destroy(self);
}

pub fn getActiveLayer(self: *const Editor) TileLayer {
    if (self.active_layer_idx < 0) {
        return self.scene.bg_layers.items[self.scene.bg_layers.items.len - @abs(self.active_layer_idx)];
    }
    if (self.active_layer_idx > 0) {
        return self.scene.fg_layers.items[@intCast(self.active_layer_idx - 1)];
    }
    return self.scene.main_layer;
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
        const file = helpers.openFile(self.scene.gamestate.scene_file, .{ .mode = .write_only }) catch {
            std.log.err("Failed to open file {s}\n", .{self.scene.gamestate.scene_file});
            std.process.exit(1);
        };
        self.scene.writeBytes(file.writer(), false) catch |err| {
            std.log.err("Failed to write scene to file: {!}\n", .{err});
            std.process.exit(1);
        };

        rl.playSound(self.gamestate.on_save_sfx);
    }
}

fn drawSaveButton(self: *const Editor) void {
    const color = if (self.save_btn_hover) rl.Color.green else rl.Color.white;
    rl.drawTextEx(self.gamestate.font, "Save", rl.Vector2.init(self.save_btn_rect.x + 5, self.save_btn_rect.y + 5), 18, 2, color);
    rl.drawRectangleLinesEx(self.save_btn_rect, 2, color);
}

pub fn update(self: *Editor, delta_time: f32) !void {
    self.scene.layer_visibility_treshold = self.active_layer_idx;

    if (rl.isKeyPressed(rl.KeyboardKey.key_home) and -@as(i16, @intCast(self.scene.bg_layers.items.len)) < self.active_layer_idx) {
        self.active_layer_idx -= 1;
    }
    if (rl.isKeyPressed(rl.KeyboardKey.key_end) and self.scene.fg_layers.items.len > self.active_layer_idx) {
        self.active_layer_idx += 1;
    }

    if (rl.isKeyPressed(rl.KeyboardKey.key_left_bracket)) {
        const active_layer = self.getActiveLayer();
        const shift = rl.isKeyDown(rl.KeyboardKey.key_left_shift);
        const change = if (shift) rl.Vector2.init(0, 1) else rl.Vector2.init(1, 0);
        const new_size = active_layer.getSize().subtract(change);
        var row_size = active_layer.getRowSize();
        if (!shift) {
            row_size -= 1;
        }
        active_layer.resizeLayer(new_size, row_size);
    }

    if (rl.isKeyPressed(rl.KeyboardKey.key_right_bracket)) {
        const active_layer = self.getActiveLayer();
        const shift = rl.isKeyDown(rl.KeyboardKey.key_left_shift);
        const change = if (shift) rl.Vector2.init(0, 1) else rl.Vector2.init(1, 0);
        const new_size = active_layer.getSize().add(change);
        var row_size = active_layer.getRowSize();
        if (!shift) {
            row_size += 1;
        }
        active_layer.resizeLayer(new_size, row_size);
    }

    self.palette_tiles.update(self, delta_time);
    try self.palette_mob.update(self, delta_time);
    try self.palette_collectables.update(self, delta_time);
    try self.palette_platform.update(self, delta_time);
    try self.palette_mysterybox.update(self, delta_time);

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
        .Platform => {
            try self.overlay_platform.update(self, delta_time);
        },
        .MysteryBox => {
            try self.overlay_mysterybox.update(self, delta_time);
        },
    }

    self.updateSaveButton();
}

pub fn draw(self: *const Editor) void {
    const zone = tracing.ZoneN(@src(), "Editor draw");
    defer zone.End();

    self.palette_tiles.draw(self, self.active_palette == .Tile);
    self.palette_mob.draw(self, self.active_palette == .Mob);
    self.palette_collectables.draw(self, self.active_palette == .Collectable);
    self.palette_platform.draw(self, self.active_palette == .Platform);
    self.palette_mysterybox.draw(self, self.active_palette == .MysteryBox);

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
        .Platform => {
            self.overlay_platform.draw(self);
        },
        .MysteryBox => {
            self.overlay_mysterybox.draw(self);
        },
    }
    self.drawSaveButton();
}

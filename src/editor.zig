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

overlay_collectables: *Overlay.CollectableOverlay = undefined,
overlay_mob: *Overlay.MobOverlay = undefined,

save_btn_rect: rl.Rectangle = undefined,
save_btn_hover: bool = false,

tile_editor_scene_overlay_mouse_grid_pos: ?shapes.IPos = null,

tile_palette_window: rl.Rectangle = undefined,
tile_palette_row_offset: usize = 0,
tile_palette_focus: bool = false,
tile_palette_hover_tile: ?usize = null,
tile_palette_start_idx: usize = 0,
tile_palette_end_idx: usize = 0,
tile_palette_selected_tile: ?usize = null,

const tile_palette_cols_per_row = 9;

pub fn create(allocator: std.mem.Allocator, scene: *Scene, vmouse: *controls.VirtualMouse) !*Editor {
    const palette_mob = try allocator.create(Palette.MobPalette);
    const palette_collectables = try allocator.create(Palette.CollectablePalette);
    const overlay_collectables = try allocator.create(Overlay.CollectableOverlay);
    const overlay_mob = try allocator.create(Overlay.MobOverlay);
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

    overlay_mob.* = Overlay.MobOverlay.init(palette_mob, &scene.mobs);
    overlay_collectables.* = Overlay.CollectableOverlay.init(palette_collectables, &scene.collectables);

    editor.* = Editor{
        .allocator = allocator,
        .active_palette = .None,
        .palette_mob = palette_mob,
        .palette_collectables = palette_collectables,
        .active_layer = scene.main_layer,
        .scene = scene,
        .vmouse = vmouse,
        .overlay_mob = overlay_mob,
        .overlay_collectables = overlay_collectables,
    };

    editor.initTilePaletteWindow();
    editor.initSaveButton();

    return editor;
}

pub fn destroy(self: *Editor) void {
    self.allocator.destroy(self.overlay_mob);
    self.allocator.destroy(self.overlay_collectables);
    self.allocator.destroy(self.palette_mob);
    self.allocator.destroy(self.palette_collectables);
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

fn initTilePaletteWindow(self: *Editor) void {
    const editor_x = constants.GAME_SIZE_X - (constants.TILE_SIZE * tile_palette_cols_per_row) - constants.VIEWPORT_PADDING_X;
    const editor_y = constants.VIEWPORT_PADDING_Y;
    const editor_width = constants.TILE_SIZE * tile_palette_cols_per_row;
    const editor_height = constants.VIEWPORT_SMALL_HEIGHT;

    self.tile_palette_window = rl.Rectangle.init(editor_x, editor_y, editor_width, editor_height);
}

fn updateSaveButton(self: *Editor) void {
    self.save_btn_hover = rl.checkCollisionPointRec(self.vmouse.pos, self.save_btn_rect);

    if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left) and self.save_btn_hover) {
        const file = helpers.openFile(globals.scene_file, .{ .mode = .write_only }) catch {
            std.log.err("Failed to open file {s}\n", .{globals.scene_file});
            std.process.exit(1);
        };
        self.scene.writeBytes(file.writer(), true) catch |err| {
            std.log.err("Failed to write scene to file: {!}\n", .{err});
            std.process.exit(1);
        };

        rl.playSound(globals.on_save_sfx);
    }
}

fn updateTileEditorSceneOverlay(self: *Editor) void {
    if (self.active_palette != .Tile) {
        return;
    }

    const scene = self.scene;
    const layer = self.active_layer;

    self.tile_editor_scene_overlay_mouse_grid_pos = self.vmouse.getGridPosition(scene, layer) orelse return;

    if (rl.isMouseButtonDown(rl.MouseButton.mouse_button_left)) blk: {
        const selected_tile = self.tile_palette_selected_tile orelse break :blk;
        const mouse_grid_pos = self.tile_editor_scene_overlay_mouse_grid_pos orelse break :blk;
        const tile_idx = layer.getTileIdxFromRowAndCol(
            @intCast(mouse_grid_pos.y),
            @intCast(mouse_grid_pos.x),
        );
        layer.writeTile(tile_idx, @intCast(selected_tile));
    }
}

fn updateTilePaletteWindow(self: *Editor) void {
    const layer = self.active_layer;
    const tileset = layer.getTileset();

    if (rl.isKeyPressed(rl.KeyboardKey.key_page_down)) {
        self.tile_palette_row_offset += 1;
    } else if (rl.isKeyPressed(rl.KeyboardKey.key_page_up) and self.tile_palette_row_offset > 0) {
        self.tile_palette_row_offset -= 1;
    }

    const max_visible_rows: usize = @divFloor(
        @as(usize, @intFromFloat(self.tile_palette_window.height)),
        constants.TILE_SIZE,
    );

    self.tile_palette_start_idx = tile_palette_cols_per_row * self.tile_palette_row_offset;
    self.tile_palette_end_idx = self.tile_palette_start_idx + (max_visible_rows * tile_palette_cols_per_row);

    const mouse_pos = self.vmouse.getMousePosition();

    self.tile_palette_hover_tile = null;
    if (rl.checkCollisionPointRec(mouse_pos, self.tile_palette_window)) {
        self.tile_palette_focus = true;

        for (self.tile_palette_start_idx..self.tile_palette_end_idx) |tile_idx| {
            const tile_rect = tileset.getRect(tile_idx) orelse continue;
            const tile_pos = self.getTilePaletteTileDest(tile_idx, self.tile_palette_row_offset);
            const col_rect = rl.Rectangle.init(tile_pos.x, tile_pos.y, tile_rect.width, tile_rect.height);

            if (rl.checkCollisionPointRec(mouse_pos, col_rect) and self.tile_palette_hover_tile == null) {
                self.tile_palette_hover_tile = tile_idx;
            }
        }
    } else {
        self.tile_palette_focus = false;
    }

    if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left) and self.tile_palette_hover_tile != null) {
        self.tile_palette_selected_tile = self.tile_palette_hover_tile;
        self.onFocus(.Tile);
    }
}

fn drawSaveButton(self: *const Editor) void {
    const color = if (self.save_btn_hover) rl.Color.green else rl.Color.white;
    rl.drawTextEx(globals.font, "Save", rl.Vector2.init(self.save_btn_rect.x + 5, self.save_btn_rect.y + 5), 18, 2, color);
    rl.drawRectangleLinesEx(self.save_btn_rect, 2, color);
}

fn drawTileEditorSceneOverlay(self: *const Editor) void {
    if (self.active_palette != .Tile) {
        return;
    }

    const layer = self.active_layer;
    const scroll = layer.getScrollState();

    const selected_tile = self.tile_palette_selected_tile orelse return;
    const mouse_grid_pos = self.tile_editor_scene_overlay_mouse_grid_pos orelse return;

    for (scroll.scroll_y_tiles..scroll.include_y_tiles + 1) |row_idx| {
        for (scroll.scroll_x_tiles..scroll.include_x_tiles + 1) |col_idx| {
            if (mouse_grid_pos.x != col_idx or mouse_grid_pos.y != row_idx) {
                continue;
            }
            layer.drawTileAt(
                @intCast(selected_tile),
                row_idx,
                col_idx,
                rl.Color.green.fade(0.5),
            );
        }
    }
}

fn drawTilePaletteWindow(self: *const Editor) void {
    // Draw window border
    helpers.drawRectBorder(self.tile_palette_window, 1, rl.Color.white);

    const layer = self.active_layer;
    const tileset = layer.getTileset();

    for (self.tile_palette_start_idx..self.tile_palette_end_idx) |tile_idx| {
        const tile_rect = tileset.getRect(tile_idx);

        if (tile_rect) |rect| {
            const dest = self.getTilePaletteTileDest(tile_idx, self.tile_palette_row_offset);

            var color = rl.Color.white.fade(0.5);

            if (self.tile_palette_selected_tile == tile_idx) {
                color = rl.Color.green;
            } else if (self.tile_palette_hover_tile == tile_idx) {
                color = rl.Color.white;
            }

            rl.drawTextureRec(tileset.getTexture(), rect, dest, color);
        }
    }
}

pub fn update(self: *Editor, delta_time: f32) !void {
    try self.palette_mob.update(self, delta_time);
    try self.palette_collectables.update(self, delta_time);
    self.updateTilePaletteWindow();

    switch (self.active_palette) {
        .None => {},
        .Tile => {
            self.updateTileEditorSceneOverlay();
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
    self.palette_mob.draw(self);
    self.palette_collectables.draw(self);
    self.drawTilePaletteWindow();

    switch (self.active_palette) {
        .None => {},
        .Tile => {
            self.drawTileEditorSceneOverlay();
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

fn getTilePaletteTileDest(self: *const Editor, tile_idx: usize, row_offset: usize) rl.Vector2 {
    const row_idx = @divFloor(tile_idx, tile_palette_cols_per_row);

    const x: f32 = self.tile_palette_window.x + @as(
        f32,
        @floatFromInt((tile_idx % tile_palette_cols_per_row)),
    ) * constants.TILE_SIZE;

    const y: f32 = self.tile_palette_window.y + @as(
        f32,
        @floatFromInt(row_idx),
    ) * constants.TILE_SIZE - @as(f32, @floatFromInt(row_offset)) * constants.TILE_SIZE;

    return rl.Vector2.init(x, y);
}

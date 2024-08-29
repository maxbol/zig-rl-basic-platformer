const Editor = @This();
const Scene = @import("scene.zig");
const TileLayer = @import("tile_layer/tile_layer.zig");
const constants = @import("constants.zig");
const controls = @import("controls.zig");
const globals = @import("globals.zig");
const helpers = @import("helpers.zig");
const rg = @import("raygui");
const rl = @import("raylib");
const shapes = @import("shapes.zig");
const std = @import("std");

active_layer: TileLayer,
scene: *Scene,
vmouse: *controls.VirtualMouse,

save_btn_rect: rl.Rectangle = undefined,
save_btn_hover: bool = false,

scene_overlay_mouse_grid_pos: ?shapes.IPos = null,

tile_palette_window: rl.Rectangle = undefined,
tile_palette_row_offset: usize = 0,
tile_palette_focus: bool = false,
tile_palette_hover_tile: ?usize = null,
tile_palette_start_idx: usize = 0,
tile_palette_end_idx: usize = 0,
tile_palette_selected_tile: ?usize = null,

const tile_palette_cols_per_row = 9;

pub fn init(scene: *Scene, vmouse: *controls.VirtualMouse) Editor {
    return .{
        .active_layer = scene.main_layer,
        .scene = scene,
        .vmouse = vmouse,
    };
}

fn updateSaveButton(self: *Editor) void {
    self.save_btn_rect = rl.Rectangle.init(
        constants.GAME_SIZE_X - 100,
        constants.GAME_SIZE_Y - 50,
        100 - constants.VIEWPORT_PADDING_X,
        50 - constants.VIEWPORT_PADDING_Y,
    );
    self.save_btn_hover = rl.checkCollisionPointRec(self.vmouse.pos, self.save_btn_rect);

    if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left) and self.save_btn_hover) {
        const file = helpers.openFile(globals.scene_file, .{ .mode = .write_only }) catch {
            std.log.err("Failed to open file {s}\n", .{globals.scene_file});
            std.process.exit(1);
        };
        self.scene.writeBytes(file.writer()) catch |err| {
            std.log.err("Failed to write scene to file: {!}\n", .{err});
            std.process.exit(1);
        };

        rl.playSound(globals.on_save_sfx);
    }
}

fn updateSceneOverlay(self: *Editor) void {
    const scene = self.scene;
    const layer = self.active_layer;

    self.scene_overlay_mouse_grid_pos = self.vmouse.getGridPosition(scene, layer) orelse return;

    if (rl.isMouseButtonDown(rl.MouseButton.mouse_button_left)) blk: {
        const selected_tile = self.tile_palette_selected_tile orelse break :blk;
        const mouse_grid_pos = self.scene_overlay_mouse_grid_pos orelse break :blk;
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

    const editor_x = constants.GAME_SIZE_X - (constants.TILE_SIZE * tile_palette_cols_per_row) - constants.VIEWPORT_PADDING_X;
    const editor_y = constants.VIEWPORT_PADDING_Y;
    const editor_width = constants.TILE_SIZE * tile_palette_cols_per_row;
    const editor_height = constants.VIEWPORT_SMALL_HEIGHT;

    self.tile_palette_window = rl.Rectangle.init(editor_x, editor_y, editor_width, editor_height);

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

    if (rl.isMouseButtonDown(rl.MouseButton.mouse_button_left) and self.tile_palette_hover_tile != null) {
        self.tile_palette_selected_tile = self.tile_palette_hover_tile;
    }
}

fn drawSaveButton(self: *const Editor) void {
    const color = if (self.save_btn_hover) rl.Color.green else rl.Color.white;
    rl.drawTextEx(globals.font, "Save", rl.Vector2.init(self.save_btn_rect.x + 5, self.save_btn_rect.y + 5), 18, 2, color);
    rl.drawRectangleLinesEx(self.save_btn_rect, 2, color);
}

fn drawSceneOverlay(self: *const Editor) void {
    const layer = self.active_layer;
    const scroll = layer.getScrollState();

    const selected_tile = self.tile_palette_selected_tile orelse return;
    const mouse_grid_pos = self.scene_overlay_mouse_grid_pos orelse return;

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

pub fn update(self: *Editor, _: f32) void {
    self.updateTilePaletteWindow();
    self.updateSaveButton();
    self.updateSceneOverlay();
}

pub fn draw(self: *const Editor) void {
    self.drawTilePaletteWindow();
    self.drawSaveButton();
    self.drawSceneOverlay();
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

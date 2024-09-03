const Actor = @import("actor/actor.zig");
const Editor = @This();
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

active_layer: TileLayer,
scene: *Scene,
vmouse: *controls.VirtualMouse,

mob_palette_window: rl.Rectangle = undefined,
mob_palette_sprites: [Actor.Mob.bestiary.len]Sprite = undefined,
mob_palette_sprite_rects: [Actor.Mob.bestiary.len]rl.Rectangle = undefined,
mob_palette_hover_mob: ?usize = null,
mob_palette_selected_mob: ?usize = null,
mob_palette_hover_eraser: bool = false,
mob_palette_eraser_mode: bool = false,
mob_palette_eraser_rect: rl.Rectangle = rl.Rectangle.init(0, 0, 0, 0),
mob_palette_eraser_sprite: Sprite = undefined,

mob_editor_scene_overlay_mouse_scene_pos: ?rl.Vector2 = null,
mod_editor_scene_overlay_marked_for_deletion: [constants.MAX_AMOUNT_OF_MOBS]bool = undefined,
mob_editor_scene_overlay_no_marked_for_deletion: u8 = 0,

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
const mob_palette_cols = 5;
const mob_palette_rows = 2;
const mob_palette_biggest_sprite_size = @max(constants.BIGGEST_MOB_SPRITE_SIZE, @max(EraserSprite.SIZE_X, EraserSprite.SIZE_Y));
const mob_editor_scene_overlay_eraser_radius = 20;

pub fn init(scene: *Scene, vmouse: *controls.VirtualMouse) Editor {
    var editor = Editor{
        .active_layer = scene.main_layer,
        .scene = scene,
        .vmouse = vmouse,
    };

    editor.initMobPaletteWindow();
    editor.initTilePaletteWindow();
    editor.initSaveButton();

    return editor;
}

fn initSaveButton(self: *Editor) void {
    self.save_btn_rect = rl.Rectangle.init(
        constants.GAME_SIZE_X - 100,
        constants.GAME_SIZE_Y - 50,
        100 - constants.VIEWPORT_PADDING_X,
        50 - constants.VIEWPORT_PADDING_Y,
    );
}

fn initMobPaletteWindow(self: *Editor) void {
    const editor_width = mob_palette_biggest_sprite_size * mob_palette_cols;
    const editor_height = mob_palette_biggest_sprite_size * mob_palette_rows;
    const editor_x = constants.VIEWPORT_PADDING_X;
    const editor_y = constants.GAME_SIZE_Y - editor_height - constants.VIEWPORT_PADDING_X;

    // Init window rect
    self.mob_palette_window = rl.Rectangle.init(editor_x, editor_y, editor_width, editor_height);

    // Init sprites
    self.mob_palette_eraser_sprite = EraserSprite.init();
    inline for (Actor.Mob.bestiary, 0..) |MobPrefab, i| {
        const sprite = MobPrefab.Sprite.init();
        self.mob_palette_sprites[i] = sprite;
    }

    // Init destination rects
    // TODO 01/09/2024: Move to update() logic
    for (0..mob_palette_rows * mob_palette_cols) |i| {
        if (i > self.mob_palette_sprites.len) {
            break;
        }

        const col = @divFloor(i, mob_palette_cols);
        const row = i % mob_palette_cols;

        var rect: *rl.Rectangle = undefined;
        var sprite: *Sprite = undefined;

        if (i == self.mob_palette_sprites.len) {
            sprite = &self.mob_palette_eraser_sprite;
            rect = &self.mob_palette_eraser_rect;
        } else {
            sprite = &self.mob_palette_sprites[i];
            rect = &self.mob_palette_sprite_rects[i];
        }

        const padding_x = mob_palette_biggest_sprite_size - sprite.size.x;
        const padding_y = mob_palette_biggest_sprite_size - sprite.size.y;
        const x = self.mob_palette_window.x + @as(f32, @floatFromInt(row)) * mob_palette_biggest_sprite_size + padding_x;
        const y = self.mob_palette_window.y + @as(f32, @floatFromInt(col)) * mob_palette_biggest_sprite_size + padding_y;
        const pos = rl.Vector2{ .x = x, .y = y };

        rect.* = rl.Rectangle.init(
            pos.x,
            pos.y,
            sprite.size.x,
            sprite.size.y,
        );
    }
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
        self.scene.writeBytes(file.writer()) catch |err| {
            std.log.err("Failed to write scene to file: {!}\n", .{err});
            std.process.exit(1);
        };

        rl.playSound(globals.on_save_sfx);
    }
}

fn updateTileEditorSceneOverlay(self: *Editor) void {
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

fn updateMobEditorSceneOverlay(self: *Editor) !void {
    self.mob_editor_scene_overlay_mouse_scene_pos = self.vmouse.getScenePosition(self.scene);
    self.mod_editor_scene_overlay_marked_for_deletion = undefined;

    if (self.mob_palette_eraser_mode and self.mob_editor_scene_overlay_mouse_scene_pos != null) {
        for (self.scene.mobs_starting_pos, 0..) |pos, i| {
            const mob_hitbox = self.scene.mobs[i].collidable.hitbox;
            const h_rect = rl.Rectangle.init(
                pos.x,
                pos.y,
                mob_hitbox.width,
                mob_hitbox.height,
            );

            const should_delete = rl.checkCollisionCircleRec(
                self.mob_editor_scene_overlay_mouse_scene_pos.?,
                mob_editor_scene_overlay_eraser_radius,
                h_rect,
            );

            self.mod_editor_scene_overlay_marked_for_deletion[i] = should_delete;
        }

        if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
            for (0..self.scene.mobs_amount) |i| {
                if (self.mod_editor_scene_overlay_marked_for_deletion[i]) {
                    self.scene.removeMob(i);
                }
            }
        }
    }

    if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
        const selected_mob = self.mob_palette_selected_mob orelse return;
        const mouse_scene_pos = self.mob_editor_scene_overlay_mouse_scene_pos orelse return;
        const sprite = self.mob_palette_sprites[selected_mob];
        const spawn_pos = rl.Vector2.init(
            mouse_scene_pos.x - (sprite.size.x / 2),
            mouse_scene_pos.y - (sprite.size.y / 2),
        );
        try self.scene.spawnMob(selected_mob, spawn_pos);
    }
}

fn updateMobPaletteWindow(self: *Editor, delta_time: f32) !void {
    for (0..self.mob_palette_sprites.len) |i| {
        try self.mob_palette_sprites[i].update(self.scene, delta_time);
    }
    try self.mob_palette_eraser_sprite.update(self.scene, delta_time);

    const mouse_pos = self.vmouse.getMousePosition();

    self.mob_palette_hover_eraser = false;
    self.mob_palette_hover_mob = null;
    if (rl.checkCollisionPointRec(mouse_pos, self.mob_palette_window)) {
        for (self.mob_palette_sprite_rects, 0..) |col_rect, i| {
            if (rl.checkCollisionPointRec(mouse_pos, col_rect)) {
                self.mob_palette_hover_mob = i;
            }
        }
        if (rl.checkCollisionPointRec(mouse_pos, self.mob_palette_eraser_rect)) {
            self.mob_palette_hover_eraser = true;
        }
    }

    if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
        if (self.mob_palette_hover_mob != null) {
            self.mob_palette_selected_mob = self.mob_palette_hover_mob;
            self.mob_palette_eraser_mode = false;
            self.tile_palette_selected_tile = null;
        } else if (self.mob_palette_hover_eraser) {
            std.debug.print("Going into eraser mode\n", .{});
            self.mob_palette_selected_mob = null;
            self.mob_palette_eraser_mode = true;
            self.tile_palette_selected_tile = null;
        }
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
        self.mob_palette_selected_mob = null;
        self.mob_palette_eraser_mode = false;
    }
}

fn drawSaveButton(self: *const Editor) void {
    const color = if (self.save_btn_hover) rl.Color.green else rl.Color.white;
    rl.drawTextEx(globals.font, "Save", rl.Vector2.init(self.save_btn_rect.x + 5, self.save_btn_rect.y + 5), 18, 2, color);
    rl.drawRectangleLinesEx(self.save_btn_rect, 2, color);
}

fn drawMobEditorSceneOverlay(self: *const Editor) void {
    const mouse_scene_pos = self.mob_editor_scene_overlay_mouse_scene_pos orelse return;

    for (0..self.scene.mobs_amount) |i| {
        if (self.scene.mobs[i].is_deleted) {
            continue;
        }
        const pos = self.scene.mobs_starting_pos[i];
        const is_marked_for_deletion = self.mod_editor_scene_overlay_marked_for_deletion[i];
        const color = if (is_marked_for_deletion) rl.Color.red.fade(0.5) else rl.Color.white.fade(0.5);
        self.scene.mobs[i].sprite.draw(self.scene, pos, color);
    }
    const selected_mob = self.mob_palette_selected_mob;

    if (selected_mob) |mob_idx| {
        const sprite = self.mob_palette_sprites[mob_idx];
        const draw_pos = rl.Vector2.init(
            mouse_scene_pos.x - (sprite.size.x / 2),
            mouse_scene_pos.y - (sprite.size.y / 2),
        );
        sprite.draw(self.scene, draw_pos, rl.Color.green.fade(0.5));
    } else if (self.mob_palette_eraser_mode) {
        rl.drawCircle(
            @intFromFloat(self.vmouse.pos.x),
            @intFromFloat(self.vmouse.pos.y),
            mob_editor_scene_overlay_eraser_radius,
            rl.Color.red.fade(0.5),
        );
    }
}

fn drawTileEditorSceneOverlay(self: *const Editor) void {
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

fn drawMobPaletteWindow(self: *const Editor) void {
    helpers.drawRectBorder(self.mob_palette_window, 1, rl.Color.white);

    for (0..mob_palette_rows * mob_palette_cols) |i| {
        if (i > self.mob_palette_sprites.len) {
            break;
        }

        var dest: *const rl.Rectangle = undefined;
        var sprite: *const Sprite = undefined;
        var color: rl.Color = undefined;

        if (i == self.mob_palette_sprites.len) {
            color = blk: {
                if (self.mob_palette_eraser_mode) {
                    break :blk rl.Color.green;
                }
                if (self.mob_palette_hover_eraser) {
                    break :blk rl.Color.white;
                }
                break :blk rl.Color.white.fade(0.5);
            };
            sprite = &self.mob_palette_eraser_sprite;
            std.debug.print("Should be drawing eraser sprite\n", .{});
            dest = &self.mob_palette_eraser_rect;
        } else {
            color = blk: {
                if (self.mob_palette_selected_mob == i) {
                    break :blk rl.Color.green;
                } else if (self.mob_palette_hover_mob == i) {
                    break :blk rl.Color.white;
                }
                break :blk rl.Color.white.fade(0.5);
            };
            sprite = &self.mob_palette_sprites[i];
            dest = &self.mob_palette_sprite_rects[i];
        }

        rl.drawRectangleLinesEx(dest.*, 1, color);
        if (sprite.getSourceRect()) |rect| {
            const pos = rl.Vector2{ .x = dest.x, .y = dest.y };
            sprite.texture.drawRec(rect, pos, color);
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
    try self.updateMobPaletteWindow(delta_time);
    try self.updateMobEditorSceneOverlay();
    self.updateTilePaletteWindow();
    self.updateSaveButton();
    self.updateTileEditorSceneOverlay();
}

pub fn draw(self: *const Editor) void {
    self.drawMobPaletteWindow();
    self.drawMobEditorSceneOverlay();
    self.drawTilePaletteWindow();
    self.drawTileEditorSceneOverlay();
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

fn loadEraserTexture() rl.Texture2D {
    std.debug.print("loading eraser texture\n", .{});
    return rl.loadTexture("assets/icons/eraser.png");
}

const EraserSprite = Sprite.Prefab(
    24,
    24,
    loadEraserTexture,
    an.getNoAnimationsBuffer(),
    .Idle,
);

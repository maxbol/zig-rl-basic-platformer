const Editor = @import("../editor.zig");
const Palette = @import("palette.zig");
const Sprite = @import("../sprite.zig");
const an = @import("../animation.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");

pub fn PrefabPalette(
    ItemType: type,
    palette_type: Palette.ActivePaletteType,
    item_size: f32,
    no_cols: usize,
    no_rows: usize,
) type {
    return struct {
        pub const Item = ItemType;
        pub const window_width = item_size * no_cols;
        pub const window_height = item_size * no_rows;

        on_focus: *const fn (editor: *Editor, palette_type: Palette.ActivePaletteType) void,
        window: rl.Rectangle,
        sprites: [ItemType.prefabs.len]Sprite,
        eraser_sprite: Sprite,
        sprite_rects: [ItemType.prefabs.len]rl.Rectangle = undefined,
        hover_item: ?usize = null,
        hover_eraser: bool = false,
        selected_item: ?usize = null,
        eraser_mode: bool = false,
        eraser_rect: rl.Rectangle = rl.Rectangle.init(0, 0, 0, 0),

        pub fn init(on_focus: *const fn (editor: *Editor, palette_type: Palette.ActivePaletteType) void, offset_x: f32, offset_y: f32) @This() {
            const window = rl.Rectangle.init(offset_x, offset_y, window_width, window_height);

            const eraser_sprite = EraserSprite.init();

            var sprites: [ItemType.prefabs.len]Sprite = undefined;
            inline for (ItemType.prefabs, 0..) |Prefab, i| {
                sprites[i] = Prefab.Sprite.init();
            }

            return .{
                .window = window,
                .sprites = sprites,
                .eraser_sprite = eraser_sprite,
                .on_focus = on_focus,
            };
        }

        pub fn update(self: *@This(), editor: *Editor, delta_time: f32) !void {
            for (0..no_rows * no_cols) |i| {
                if (i > self.sprites.len) {
                    break;
                }

                const col = @divFloor(i, no_cols);
                const row = i % no_cols;

                var rect: *rl.Rectangle = undefined;
                var sprite: *Sprite = undefined;

                if (i == self.sprites.len) {
                    sprite = &self.eraser_sprite;
                    rect = &self.eraser_rect;
                } else {
                    sprite = &self.sprites[i];
                    rect = &self.sprite_rects[i];
                }

                const padding_x = item_size - sprite.size.x;
                const padding_y = item_size - sprite.size.y;
                const x = self.window.x + @as(f32, @floatFromInt(row)) * item_size + padding_x;
                const y = self.window.y + @as(f32, @floatFromInt(col)) * item_size + padding_y;
                const pos = rl.Vector2{ .x = x, .y = y };

                rect.* = rl.Rectangle.init(
                    pos.x,
                    pos.y,
                    sprite.size.x,
                    sprite.size.y,
                );
            }

            for (0..self.sprites.len) |i| {
                try self.sprites[i].update(editor.scene, delta_time);
            }

            try self.eraser_sprite.update(editor.scene, delta_time);

            const mouse_pos = editor.vmouse.getMousePosition();

            self.hover_eraser = false;
            self.hover_item = null;
            if (rl.checkCollisionPointRec(mouse_pos, self.window)) {
                for (self.sprite_rects, 0..) |col_rect, i| {
                    if (rl.checkCollisionPointRec(mouse_pos, col_rect)) {
                        self.hover_item = i;
                    }
                }
                if (rl.checkCollisionPointRec(mouse_pos, self.eraser_rect)) {
                    self.hover_eraser = true;
                }
            }

            if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
                if (self.hover_item != null) {
                    self.selected_item = self.hover_item;
                    self.eraser_mode = false;
                    self.on_focus(editor, palette_type);
                } else if (self.hover_eraser) {
                    self.selected_item = null;
                    self.eraser_mode = true;
                    self.on_focus(editor, palette_type);
                }
            }
        }

        pub fn draw(self: *const @This(), _: *const Editor, is_focused: bool) void {
            helpers.drawRectBorder(self.window, 1, rl.Color.white);

            for (0..no_rows * no_cols) |i| {
                if (i > self.sprites.len) {
                    break;
                }

                var dest: *const rl.Rectangle = undefined;
                var sprite: *const Sprite = undefined;
                var color: rl.Color = undefined;

                if (i == self.sprites.len) {
                    color = blk: {
                        if (is_focused and self.eraser_mode) {
                            break :blk rl.Color.green;
                        }
                        if (self.hover_eraser) {
                            break :blk rl.Color.white;
                        }
                        break :blk rl.Color.white.fade(0.5);
                    };
                    sprite = &self.eraser_sprite;
                    dest = &self.eraser_rect;
                } else {
                    color = blk: {
                        if (is_focused and self.selected_item == i) {
                            break :blk rl.Color.green;
                        }
                        if (self.hover_item == i) {
                            break :blk rl.Color.white;
                        }
                        break :blk rl.Color.white.fade(0.5);
                    };
                    sprite = &self.sprites[i];
                    dest = &self.sprite_rects[i];
                }

                rl.drawRectangleLinesEx(dest.*, 1, color);
                if (sprite.getSourceRect()) |rect| {
                    const pos = rl.Vector2{ .x = dest.x, .y = dest.y };
                    sprite.texture.drawRec(rect, pos, color);
                }
            }
        }
    };
}

fn loadEraserTexture() rl.Texture2D {
    return rl.loadTexture("assets/icons/eraser.png");
}

const EraserSprite = Sprite.Prefab(
    24,
    24,
    loadEraserTexture,
    an.getNoAnimationsBuffer(),
    .Idle,
);

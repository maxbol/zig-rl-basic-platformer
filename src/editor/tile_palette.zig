const Editor = @import("../editor.zig");
const Palette = @import("palette.zig");
const TilePalette = @This();
const constants = @import("../constants.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");

window: rl.Rectangle,
row_offset: usize = 0,
is_focused: bool = false,
hover_tile: ?usize = null,
start_idx: usize = 0,
end_idx: usize = 0,
selected_tile: ?usize = null,
on_focus: *const fn (*Editor, Palette.ActivePaletteType) void,

pub const cols_per_row = 9;

pub fn init(on_focus: *const fn (*Editor, Palette.ActivePaletteType) void) TilePalette {
    const window_x = constants.GAME_SIZE_X - (constants.TILE_SIZE * cols_per_row) - constants.VIEWPORT_PADDING_X;
    const window_y = constants.VIEWPORT_PADDING_Y;
    const window_width = constants.TILE_SIZE * cols_per_row;
    const window_height = constants.VIEWPORT_SMALL_HEIGHT;
    const window = rl.Rectangle.init(window_x, window_y, window_width, window_height);

    return .{ .on_focus = on_focus, .window = window };
}

pub fn update(self: *TilePalette, editor: *Editor, _: f32) void {
    const layer = editor.active_layer;
    const tileset = layer.getTileset();

    if (rl.isKeyPressed(rl.KeyboardKey.key_page_down)) {
        self.row_offset += 1;
    } else if (rl.isKeyPressed(rl.KeyboardKey.key_page_up) and self.row_offset > 0) {
        self.row_offset -= 1;
    }

    const max_visible_rows: usize = @divFloor(
        @as(usize, @intFromFloat(self.window.height)),
        constants.TILE_SIZE,
    );

    self.start_idx = cols_per_row * self.row_offset;
    self.end_idx = self.start_idx + (max_visible_rows * cols_per_row);

    const mouse_pos = editor.vmouse.getMousePosition();

    self.hover_tile = null;
    if (rl.checkCollisionPointRec(mouse_pos, self.window)) {
        for (self.start_idx..self.end_idx) |tile_idx| {
            const tile_rect = tileset.getRect(tile_idx) orelse continue;
            const tile_pos = self.getTilePaletteTileDest(tile_idx, self.row_offset);
            const col_rect = rl.Rectangle.init(tile_pos.x, tile_pos.y, tile_rect.width, tile_rect.height);

            if (rl.checkCollisionPointRec(mouse_pos, col_rect) and self.hover_tile == null) {
                self.hover_tile = tile_idx;
                break;
            }
        }
    }

    if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left) and self.hover_tile != null) {
        self.selected_tile = self.hover_tile;
        self.on_focus(editor, .Tile);
    }
}

pub fn draw(self: *const TilePalette, editor: *const Editor, is_focused: bool) void {
    // Draw window border
    helpers.drawRectBorder(self.window, 1, rl.Color.white);

    const layer = editor.active_layer;
    const tileset = layer.getTileset();

    for (self.start_idx..self.end_idx) |tile_idx| {
        const tile_rect = tileset.getRect(tile_idx);

        if (tile_rect) |rect| {
            const dest = self.getTilePaletteTileDest(tile_idx, self.row_offset);

            var color = rl.Color.white.fade(0.5);

            if (is_focused and self.selected_tile == tile_idx) {
                color = rl.Color.green;
            } else if (self.hover_tile == tile_idx) {
                color = rl.Color.white;
            }

            rl.drawTextureRec(tileset.getTexture(), rect, dest, color);
        }
    }
}

pub fn getTilePaletteTileDest(self: *const TilePalette, tile_idx: usize, row_offset: usize) rl.Vector2 {
    const row_idx = @divFloor(tile_idx, cols_per_row);

    const x: f32 = self.window.x + @as(
        f32,
        @floatFromInt((tile_idx % cols_per_row)),
    ) * constants.TILE_SIZE;

    const y: f32 = self.window.y + @as(
        f32,
        @floatFromInt(row_idx),
    ) * constants.TILE_SIZE - @as(f32, @floatFromInt(row_offset)) * constants.TILE_SIZE;

    return rl.Vector2.init(x, y);
}

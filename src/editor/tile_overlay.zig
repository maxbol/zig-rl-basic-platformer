const Editor = @import("../editor.zig");
const TileOverlay = @This();
const TilePalette = @import("tile_palette.zig");
const rl = @import("raylib");
const shapes = @import("../shapes.zig");

palette: *const TilePalette,
mouse_grid_pos: ?shapes.IPos = null,

pub fn init(palette: *const TilePalette) TileOverlay {
    return .{
        .palette = palette,
    };
}

pub fn update(self: *TileOverlay, editor: *Editor, _: f32) void {
    if (editor.active_palette != .Tile) {
        return;
    }

    const scene = editor.scene;
    const layer = editor.active_layer;

    self.mouse_grid_pos = editor.vmouse.getGridPosition(scene, layer) orelse return;

    if (rl.isMouseButtonDown(rl.MouseButton.mouse_button_left)) blk: {
        const selected_tile = self.palette.selected_tile orelse break :blk;
        const mouse_grid_pos = self.mouse_grid_pos orelse break :blk;
        const tile_idx = layer.getTileIdxFromRowAndCol(
            @intCast(mouse_grid_pos.y),
            @intCast(mouse_grid_pos.x),
        );
        layer.writeTile(tile_idx, @intCast(selected_tile));
    }
}

pub fn draw(self: *const TileOverlay, editor: *const Editor) void {
    if (editor.active_palette != .Tile) {
        return;
    }

    const layer = editor.active_layer;
    const scroll = layer.getScrollState();

    const selected_tile = self.palette.selected_tile orelse return;
    const mouse_grid_pos = self.mouse_grid_pos orelse return;

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

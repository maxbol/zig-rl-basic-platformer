const Entity = @import("../entity.zig");
const Scene = @import("../scene.zig");
const TileLayer = @This();
const Tileset = @import("../tileset/tileset.zig");
const debug = @import("../debug.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");
const shapes = @import("../shapes.zig");

ptr: *anyopaque,
impl: *const Interface,

pub const Interface = struct {
    didCollideThisFrame: *const fn (ctx: *anyopaque, tile_idx: usize) bool,
    getFlags: *const fn (ctx: *anyopaque) u8,
    getPixelSize: *const fn (ctx: *anyopaque) rl.Vector2,
    getScrollState: *const fn (ctx: *anyopaque) *const Scrollable,
    getSize: *const fn (ctx: *anyopaque) rl.Vector2,
    getTileFromRowAndCol: *const fn (ctx: *anyopaque, row_idx: usize, col_idx: usize) ?u8,
    getTileIdxFromRowAndCol: *const fn (ctx: *anyopaque, row_idx: usize, col_idx: usize) usize,
    getTileset: *const fn (ctx: *anyopaque) Tileset,
    storeCollisionData: *const fn (ctx: *anyopaque, tile_idx: usize, did_collide: bool) void,
    update: *const fn (ctx: *anyopaque, scene: *Scene, delta_time: f32) Entity.UpdateError!void,
    wasTestedThisFrame: *const fn (ctx: *anyopaque, tile_idx: usize) bool,
    writeTile: *const fn (ctx: *anyopaque, tile_idx: usize, tile: u8) void,
};

pub fn getFlags(self: TileLayer) u8 {
    return self.impl.getFlags(self.ptr);
}

pub fn getPixelSize(self: TileLayer) rl.Vector2 {
    return self.impl.getPixelSize(self.ptr);
}

pub fn getSize(self: TileLayer) rl.Vector2 {
    return self.impl.getSize(self.ptr);
}

pub fn getTileset(self: TileLayer) Tileset {
    return self.impl.getTileset(self.ptr);
}

pub fn getTileIdxFromRowAndCol(self: TileLayer, row_idx: usize, col_idx: usize) usize {
    return self.impl.getTileIdxFromRowAndCol(self.ptr, row_idx, col_idx);
}

pub fn getTileFromRowAndCol(self: TileLayer, row_idx: usize, col_idx: usize) ?u8 {
    return self.impl.getTileFromRowAndCol(self.ptr, row_idx, col_idx);
}

pub fn getScrollState(self: TileLayer) *const Scrollable {
    return self.impl.getScrollState(self.ptr);
}

pub fn update(self: TileLayer, scene: *Scene, delta_time: f32) Entity.UpdateError!void {
    return self.impl.update(self.ptr, scene, delta_time);
}

pub fn storeCollisionData(self: TileLayer, tile_idx: usize, did_collide: bool) void {
    return self.impl.storeCollisionData(self.ptr, tile_idx, did_collide);
}

pub fn didCollideThisFrame(self: TileLayer, tile_idx: usize) bool {
    return self.impl.didCollideThisFrame(self.ptr, tile_idx);
}

pub fn wasTestedThisFrame(self: TileLayer, tile_idx: usize) bool {
    return self.impl.wasTestedThisFrame(self.ptr, tile_idx);
}

pub fn writeTile(self: TileLayer, tile_idx: usize, tile: u8) void {
    return self.impl.writeTile(self.ptr, tile_idx, tile);
}

inline fn drawTileAtImpl(
    tileset: Tileset,
    tile: u8,
    scroll: *const Scrollable,
    tile_size: rl.Vector2,
    row_idx: usize,
    col_idx: usize,
    tint: rl.Color,
) void {
    const row_offset: f32 = @floatFromInt(row_idx - scroll.scroll_y_tiles);
    const col_offset: f32 = @floatFromInt(col_idx - scroll.scroll_x_tiles);

    var cull_x: f32 = 0;
    var cull_y: f32 = 0;

    if (col_idx == scroll.scroll_x_tiles) {
        cull_x = scroll.sub_tile_scroll_x;
    } else if (col_idx == scroll.include_x_tiles) {
        cull_x = -(tile_size.x - scroll.sub_tile_scroll_x);
    }

    if (row_idx == scroll.scroll_y_tiles) {
        cull_y = scroll.sub_tile_scroll_y;
    } else if (row_idx == scroll.include_y_tiles) {
        cull_y = -(tile_size.y - scroll.sub_tile_scroll_y);
    }

    const dest_x: f32 = scroll.viewport_x_adjust + col_offset * tile_size.x - scroll.sub_tile_scroll_x;
    const dest_y: f32 = scroll.viewport_y_adjust + row_offset * tile_size.y - scroll.sub_tile_scroll_y;
    const dest = rl.Vector2.init(dest_x, dest_y);

    tileset.drawRect(tile, dest, cull_x, cull_y, tint);
}

pub fn drawTileAt(self: TileLayer, tile: u8, row_idx: usize, col_idx: usize, tint: rl.Color) void {
    const tileset = self.getTileset();
    const tile_size = tileset.getTileSize();
    const scroll = self.getScrollState();
    drawTileAtImpl(tileset, tile, scroll, tile_size, row_idx, col_idx, tint);
}

pub fn draw(self: TileLayer, _: *const Scene) void {
    const scroll = self.getScrollState();
    const tileset = self.getTileset();
    const tile_size = tileset.getTileSize();
    for (scroll.scroll_y_tiles..scroll.include_y_tiles + 1) |row_idx| {
        for (scroll.scroll_x_tiles..scroll.include_x_tiles + 1) |col_idx| {
            const tile = self.getTileFromRowAndCol(row_idx, col_idx) orelse continue;
            drawTileAtImpl(tileset, tile, scroll, tile_size, row_idx, col_idx, rl.Color.white);
        }
    }
}

pub fn drawDebug(layer: TileLayer, scene: *const Scene) void {
    if (!debug.isDebugFlagSet(.ShowCollidedTiles) and !debug.isDebugFlagSet(.ShowTestedTiles)) {
        return;
    }

    const scrollable = layer.getScrollState();
    const tileset = layer.getTileset();

    for (scrollable.scroll_y_tiles..scrollable.include_y_tiles + 1) |row_idx| {
        for (scrollable.scroll_x_tiles..scrollable.include_x_tiles + 1) |col_idx| {
            const tile_idx = layer.getTileIdxFromRowAndCol(row_idx, col_idx);

            const tile_rect: rl.Rectangle = scene.getViewportAdjustedPos(
                rl.Rectangle,
                helpers.getPixelRect(tileset.getTileSize(), rl.Rectangle{
                    .x = @floatFromInt(col_idx),
                    .y = @floatFromInt(row_idx),
                    .width = 1,
                    .height = 1,
                }),
            );

            if (debug.isDebugFlagSet(.ShowCollidedTiles) and layer.didCollideThisFrame(tile_idx)) {
                rl.drawRectangleRec(tile_rect, rl.Color.green.alpha(0.5));
            } else if (debug.isDebugFlagSet(.ShowTestedTiles) and layer.wasTestedThisFrame(tile_idx)) {
                rl.drawRectangleRec(tile_rect, rl.Color.red.alpha(0.5));
            }
        }
    }
}

pub fn collideAt(layer: TileLayer, rect: shapes.IRect, grid_rect: shapes.IRect) bool {
    const tileset = layer.getTileset();
    const tile_size = shapes.IPos.fromVec2(tileset.getTileSize());

    const min_row: usize = @intCast(@max(0, grid_rect.y - 1));
    const max_row: usize = @intCast(@max(0, grid_rect.y + grid_rect.height + 1));

    const min_col: usize = @intCast(@max(0, grid_rect.x - 1));
    const max_col: usize = @intCast(@max(0, grid_rect.x + grid_rect.width + 1));

    for (min_row..max_row) |row_idx| {
        for (min_col..max_col) |col_idx| {
            const tile_idx = layer.getTileIdxFromRowAndCol(row_idx, col_idx);
            const tile = layer.getTileFromRowAndCol(row_idx, col_idx) orelse continue;

            if (!tileset.isCollidable(tile)) {
                continue;
            }

            const tile_rect: shapes.IRect = helpers.getPixelPos(tile_size, shapes.IRect{
                .x = @intCast(col_idx),
                .y = @intCast(row_idx),
                .width = tile_size.x,
                .height = tile_size.y,
            });

            const is_colliding = rect.isColliding(tile_rect);

            layer.storeCollisionData(tile_idx, is_colliding);

            if (is_colliding) {
                return true;
            }
        }
    }

    return false;
}

pub const FixedSizeTileLayer = @import("fixed_size_tile_layer.zig").FixedSizeTileLayer;
pub const LayerFlag = @import("layer_flag.zig").LayerFlag;
pub const Scrollable = @import("scrollable.zig");

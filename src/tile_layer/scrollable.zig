const Scene = @import("../scene.zig");
const Scrollable = @This();
const an = @import("../animation.zig");
const TileLayer = @import("tile_layer.zig");
const LayerFlag = @import("layer_flag.zig").LayerFlag;

scroll_x_tiles: usize = 0,
scroll_y_tiles: usize = 0,
sub_tile_scroll_x: f32 = 0,
sub_tile_scroll_y: f32 = 0,
include_x_tiles: usize = 0,
include_y_tiles: usize = 0,
viewport_x_adjust: f32 = 0,
viewport_y_adjust: f32 = 0,

pub fn update(self: *Scrollable, scene: *Scene, layer: TileLayer) an.AnimationBufferError!void {
    const viewport = scene.viewport;
    const scroll_state = scene.scroll_state;

    const tile_size = layer.getTileset().getTileSize();
    const viewport_rect = viewport.rectangle;

    const pixel_size = layer.getPixelSize();

    const max_x_scroll: f32 = @max(pixel_size.x - viewport_rect.width, 0);
    const max_y_scroll: f32 = @max(pixel_size.y - viewport_rect.height, 0);

    const scroll_state_x = blk: {
        if ((layer.getFlags() & @intFromEnum(LayerFlag.InvertXScroll)) > 0) {
            break :blk 1 - scroll_state.x;
        }
        break :blk scroll_state.x;
    };

    const scroll_state_y = blk: {
        if ((layer.getFlags() & @intFromEnum(LayerFlag.InvertYScroll)) > 0) {
            break :blk 1 - scroll_state.y;
        }
        break :blk scroll_state.y;
    };

    const scroll_x_pixels: f32 = @round(scroll_state_x * max_x_scroll);
    const scroll_y_pixels: f32 = @round(scroll_state_y * max_y_scroll);

    self.scroll_x_tiles = @intFromFloat(@floor(scroll_x_pixels / tile_size.x));
    self.scroll_y_tiles = @intFromFloat(@floor(scroll_y_pixels / tile_size.y));

    self.sub_tile_scroll_x = @mod(scroll_x_pixels, tile_size.x);
    self.sub_tile_scroll_y = @mod(scroll_y_pixels, tile_size.y);

    const viewport_tile_size_x: usize = @intFromFloat(@floor(viewport_rect.width / tile_size.x));
    const viewport_tile_size_y: usize = @intFromFloat(@floor(viewport_rect.height / tile_size.y));

    self.include_x_tiles = self.scroll_x_tiles + viewport_tile_size_x;
    self.include_y_tiles = self.scroll_y_tiles + viewport_tile_size_y;

    self.viewport_x_adjust = viewport_rect.x;
    self.viewport_y_adjust = viewport_rect.y;
}

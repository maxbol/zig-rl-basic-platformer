const TileLayer = @import("tile_layer/tile_layer.zig");
const Tileset = @import("tileset/tileset.zig");
const an = @import("animation.zig");

pub const XS_TILE_LAYER_SIZE = 50;
pub const SMALL_TILE_LAYER_SIZE = 1000;
pub const MEDIUM_TILE_LAYER_SIZE = 5000;
pub const LARGE_TILE_LAYER_SIZE = 10000;
pub const XL_TILE_LAYER_SIZE = 50000;

pub const XsTileLayerArray = [1]XsTileLayer;
pub const Tileset512 = Tileset.FixedSizeTileset(512);
pub const XsTileLayer = TileLayer.FixedSizeTileLayer(XS_TILE_LAYER_SIZE);
pub const SmallTileLayer = TileLayer.FixedSizeTileLayer(SMALL_TILE_LAYER_SIZE);
pub const MediumTileLayer = TileLayer.FixedSizeTileLayer(MEDIUM_TILE_LAYER_SIZE);
pub const LargeTileLayer = TileLayer.FixedSizeTileLayer(LARGE_TILE_LAYER_SIZE);
pub const XlTileLayer = TileLayer.FixedSizeTileLayer(XL_TILE_LAYER_SIZE);
pub const PlayerAnimationBuffer = an.AnimationBuffer(&.{
    .Idle,
    .Hit,
    .Walk,
    .Death,
    .Roll,
    .Jump,
}, 16);
pub const MobAnimationBuffer = an.AnimationBuffer(&.{
    .Walk,
    .Attack,
    .Hit,
}, 6);

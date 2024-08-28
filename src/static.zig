const TileLayer = @import("tile_layer/tile_layer.zig");
const Tileset = @import("tileset/tileset.zig");
const an = @import("animation.zig");

pub const BgTileLayerArray = [1]BgTileLayer;
pub const Tileset512 = Tileset.FixedSizeTileset(512);
pub const MainLayer = TileLayer.FixedSizeTileLayer(100 * 40, Tileset512);
pub const BgTileLayer = TileLayer.FixedSizeTileLayer(1 * 35, Tileset512);
pub const FgTileLayer = TileLayer.FixedSizeTileLayer(1 * 35, Tileset512);
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

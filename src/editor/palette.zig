const Actor = @import("../actor/actor.zig");
const Collectable = @import("../collectable/collectable.zig");
const PrefabPalette = @import("prefab_palette.zig").PrefabPalette;

pub const ActivePaletteType = enum {
    None,
    Mob,
    Collectable,
    Tile,
};

pub const MobPalette = PrefabPalette(Actor.Mob, ActivePaletteType.Mob, 24, 5, 2);
pub const CollectablePalette = PrefabPalette(Collectable, ActivePaletteType.Collectable, 24, 3, 2);
pub const TilePalette = @import("tile_palette.zig");

const Actor = @import("../actor/actor.zig");
const PrefabPalette = @import("prefab_palette.zig").PrefabPalette;
const Solid = @import("../solid/solid.zig");

pub const ActivePaletteType = enum {
    None,
    Mob,
    Collectable,
    Tile,
    Platform,
    MysteryBox,
};

pub const MobPalette = PrefabPalette(Actor.Mob, .Mob, 24, 5, 2);
pub const CollectablePalette = PrefabPalette(Actor.Collectable, .Collectable, 24, 3, 2);
pub const PlatformPalette = PrefabPalette(Solid.Platform, .Platform, 32, 3, 2);
pub const MysteryBoxPalette = PrefabPalette(Solid.MysteryBox, .MysteryBox, 16, 3, 2);
pub const TilePalette = @import("tile_palette.zig");

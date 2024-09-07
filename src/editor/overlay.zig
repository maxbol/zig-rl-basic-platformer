const Palette = @import("palette.zig");
const PrefabOverlay = @import("prefab_overlay.zig").PrefabOverlay;
const Scene = @import("../scene.zig");
const constants = @import("../constants.zig");

pub const MobOverlay = PrefabOverlay(Palette.MobPalette, Scene.spawnMob, constants.MAX_AMOUNT_OF_MOBS);
pub const CollectableOverlay = PrefabOverlay(Palette.CollectablePalette, Scene.spawnCollectable, constants.MAX_AMOUNT_OF_COLLECTABLES);
pub const PlatformOverlay = PrefabOverlay(Palette.PlatformPalette, Scene.spawnPlatform, constants.MAX_AMOUNT_OF_PLATFORMS);
pub const TileOverlay = @import("tile_overlay.zig");

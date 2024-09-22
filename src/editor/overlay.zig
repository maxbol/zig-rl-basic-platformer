const Palette = @import("palette.zig");
const PrefabOverlay = @import("prefab_overlay.zig").PrefabOverlay;
const Scene = @import("../scene.zig");
const constants = @import("../constants.zig");
const rl = @import("raylib");

fn spawnMob(scene: *Scene, item_idx: usize, pos: rl.Vector2) anyerror!void {
    _ = try scene.spawnMob(item_idx, pos);
}

fn spawnCollectable(scene: *Scene, item_idx: usize, pos: rl.Vector2) anyerror!void {
    _ = try scene.spawnCollectable(item_idx, pos);
}

fn spawnPlatform(scene: *Scene, item_idx: usize, pos: rl.Vector2) anyerror!void {
    _ = try scene.spawnPlatform(item_idx, pos);
}

fn spawnMysteryBox(scene: *Scene, item_idx: usize, pos: rl.Vector2) anyerror!void {
    _ = try scene.spawnMysteryBox(item_idx, pos);
}

pub const MobOverlay = PrefabOverlay(
    Palette.MobPalette,
    spawnMob,
    Scene.deleteMob,
    constants.MAX_AMOUNT_OF_MOBS,
);
pub const CollectableOverlay = PrefabOverlay(
    Palette.CollectablePalette,
    spawnCollectable,
    Scene.deleteCollectable,
    constants.MAX_AMOUNT_OF_COLLECTABLES,
);
pub const PlatformOverlay = PrefabOverlay(
    Palette.PlatformPalette,
    spawnPlatform,
    Scene.deletePlatform,
    constants.MAX_AMOUNT_OF_PLATFORMS,
);
pub const MysteryBoxOverlay = PrefabOverlay(
    Palette.MysteryBoxPalette,
    spawnMysteryBox,
    Scene.deleteMysteryBox,
    constants.MAX_AMOUNT_OF_MYSTERY_BOXES,
);
pub const TileOverlay = @import("tile_overlay.zig");

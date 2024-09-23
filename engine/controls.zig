const Scene = @import("scene.zig");
const TileLayer = @import("tile_layer/tile_layer.zig");
const constants = @import("constants.zig");
const helpers = @import("helpers.zig");
const rl = @import("raylib");
const shapes = @import("shapes.zig");

pub const KBD_MOVE_RIGHT: *const [1]rl.KeyboardKey = &.{rl.KeyboardKey.key_d};
pub const KBD_MOVE_LEFT: *const [1]rl.KeyboardKey = &.{rl.KeyboardKey.key_a};
pub const KBD_JUMP: *const [1]rl.KeyboardKey = &.{rl.KeyboardKey.key_w};
pub const KBD_ROLL: *const [1]rl.KeyboardKey = &.{rl.KeyboardKey.key_h};
pub const KBD_PAUSE: *const [1]rl.KeyboardKey = &.{rl.KeyboardKey.key_p};

pub fn isKeyboardControlDown(key_binding: []const rl.KeyboardKey) bool {
    for (key_binding) |key| {
        if (rl.isKeyDown(key)) {
            return true;
        }
    }
    return false;
}

pub fn isKeyboardControlPressed(key_binding: []const rl.KeyboardKey) bool {
    for (key_binding) |key| {
        if (rl.isKeyPressed(key)) {
            return true;
        }
    }
    return false;
}

pub const VirtualMouse = struct {
    pos: rl.Vector2 = .{ .x = 0, .y = 0 },

    pub fn getMousePosition(self: *const VirtualMouse) rl.Vector2 {
        return self.pos;
    }

    pub fn getLayerPosition(self: *const VirtualMouse, scene: *const Scene, layer: TileLayer) ?rl.Vector2 {
        if (!rl.checkCollisionPointRec(self.pos, scene.viewport.rectangle)) {
            return null;
        }

        return layer.getLayerPosition(self.pos);
    }

    pub fn getScenePosition(self: *const VirtualMouse, scene: *const Scene) ?rl.Vector2 {
        return self.getLayerPosition(scene, scene.main_layer);
    }

    pub fn getGridPosition(self: *const VirtualMouse, scene: *const Scene, layer: TileLayer) ?shapes.IPos {
        const layer_pos = self.getLayerPosition(scene, layer) orelse return null;
        return helpers.getGridPos(
            shapes.IPos.fromVec2(layer.getTileset().getTileSize()),
            shapes.IPos.fromVec2(layer_pos),
        );
    }

    pub fn update(self: *VirtualMouse, scale: f32) void {
        const mouse = rl.getMousePosition();
        const screen_width: f32 = @floatFromInt(rl.getScreenWidth());
        const screen_height: f32 = @floatFromInt(rl.getScreenHeight());
        self.pos.x = (mouse.x - (screen_width - (constants.GAME_SIZE_X * scale)) * 0.5) / scale;
        self.pos.y = (mouse.y - (screen_height - (constants.GAME_SIZE_Y * scale)) * 0.5) / scale;
        self.pos = self.pos.clamp(rl.Vector2.init(0, 0), rl.Vector2.init(constants.GAME_SIZE_X, constants.GAME_SIZE_Y));
    }
};

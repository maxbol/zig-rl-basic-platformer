const Actor = @import("../actor/actor.zig");
const Palette = @import("palette.zig");
const Editor = @import("../editor.zig");
const Scene = @import("../scene.zig");
const constants = @import("../constants.zig");
const rl = @import("raylib");
const std = @import("std");

pub const eraser_radius = 20;

pub fn PrefabOverlay(PaletteType: type, spawn_fn: fn (scene: *Scene, item_idx: usize, pos: rl.Vector2) Scene.SpawnError!void, max_amount_of_items: usize) type {
    return struct {
        palette: *const PaletteType,
        mouse_scene_pos: ?rl.Vector2 = null,
        marked_for_deletion: [max_amount_of_items]bool = undefined,
        no_marked_for_deletion: usize = 0,
        scene_data: []PaletteType.Item,

        pub fn init(palette: *const PaletteType, scene_data: []PaletteType.Item) @This() {
            return .{
                .palette = palette,
                .scene_data = scene_data,
            };
        }

        pub fn update(self: *@This(), editor: *Editor, _: f32) !void {
            self.mouse_scene_pos = editor.vmouse.getScenePosition(editor.scene);
            self.marked_for_deletion = undefined;

            if (self.palette.eraser_mode and self.mouse_scene_pos != null) {
                for (self.scene_data, 0..) |item, i| {
                    const mob_hitbox = item.getHitboxRect();
                    const pos = item.getInitialPos();

                    const h_rect = rl.Rectangle.init(
                        pos.x,
                        pos.y,
                        mob_hitbox.width,
                        mob_hitbox.height,
                    );

                    const should_delete = rl.checkCollisionCircleRec(
                        self.mouse_scene_pos.?,
                        eraser_radius,
                        h_rect,
                    );

                    self.marked_for_deletion[i] = should_delete;
                }

                if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
                    for (0..self.scene_data.len) |i| {
                        if (self.marked_for_deletion[i]) {
                            self.scene_data[i].delete();
                        }
                    }
                }
            }

            if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
                const selected_item = self.palette.selected_item orelse return;
                const mouse_scene_pos = self.mouse_scene_pos orelse return;
                const sprite = self.palette.sprites[selected_item];
                const sprite_offset = self.palette.sprite_offsets[selected_item];
                const spawn_pos = rl.Vector2.init(
                    mouse_scene_pos.x - (sprite.size.x / 2) + sprite_offset.x,
                    mouse_scene_pos.y - (sprite.size.y / 2) + sprite_offset.y,
                );
                try spawn_fn(editor.scene, selected_item, spawn_pos);
            }
        }

        pub fn draw(self: *const @This(), editor: *const Editor) void {
            const mouse_scene_pos = self.mouse_scene_pos orelse return;

            for (self.scene_data, 0..) |item, i| {
                if (item.is_deleted) {
                    continue;
                }

                var pos = item.getInitialPos();
                pos.x -= item.sprite_offset.x;
                pos.y -= item.sprite_offset.y;
                const is_marked_for_deletion = self.marked_for_deletion[i];
                const color = if (is_marked_for_deletion) rl.Color.red.fade(0.5) else rl.Color.white.fade(0.5);
                item.sprite.draw(editor.scene, pos, color);
            }

            const selected_item = self.palette.selected_item;
            if (selected_item) |item_idx| {
                const sprite = self.palette.sprites[item_idx];
                const draw_pos = rl.Vector2.init(
                    mouse_scene_pos.x - (sprite.size.x / 2),
                    mouse_scene_pos.y - (sprite.size.y / 2),
                );
                sprite.draw(editor.scene, draw_pos, rl.Color.green.fade(0.5));
            } else if (self.palette.eraser_mode) {
                rl.drawCircle(
                    @intFromFloat(editor.vmouse.pos.x),
                    @intFromFloat(editor.vmouse.pos.y),
                    eraser_radius,
                    rl.Color.red.fade(0.5),
                );
            }
        }
    };
}

const Actor = @import("../actor/actor.zig");
const GameState = @import("../gamestate.zig");
const Palette = @import("palette.zig");
const Editor = @import("../editor.zig");
const Scene = @import("../scene.zig");
const an = @import("../animation.zig");
const constants = @import("../constants.zig");
const rl = @import("raylib");
const shapes = @import("../shapes.zig");
const std = @import("std");

pub const eraser_radius = 20;

pub fn PrefabOverlay(
    PaletteType: type,
    spawn_fn: fn (
        scene: *Scene,
        item_type: usize,
        pos: rl.Vector2,
        gamestate: *GameState,
    ) anyerror!void,
    remove_fn: fn (
        scene: *Scene,
        item_idx: usize,
    ) void,
    max_amount_of_items: usize,
) type {
    return struct {
        palette: *const PaletteType,
        mouse_scene_pos: ?rl.Vector2 = null,
        marked_for_deletion: [max_amount_of_items]bool = undefined,
        no_marked_for_deletion: usize = 0,
        scene_data: *std.ArrayList(PaletteType.Item),
        snap_to_grid: bool = false,

        pub fn init(palette: *const PaletteType, scene_data: *std.ArrayList(PaletteType.Item)) @This() {
            return .{
                .palette = palette,
                .scene_data = scene_data,
            };
        }

        pub fn update(self: *@This(), editor: *Editor, _: f32) !void {
            const mouse_scene_pos = editor.vmouse.getScenePosition(editor.scene);

            self.mouse_scene_pos = mouse_scene_pos;
            self.marked_for_deletion = undefined;
            self.snap_to_grid = false;

            // Snap to grid?
            if (rl.isKeyDown(rl.KeyboardKey.key_left_shift)) {
                const layer = editor.getActiveLayer();
                const mouse_grid_pos = editor.vmouse.getGridPosition(editor.scene, layer);
                if (mouse_grid_pos) |pos| {
                    const tile_size = layer.getTileset().getTileSize();
                    self.mouse_scene_pos = rl.Vector2.init(
                        @as(f32, @floatFromInt(pos.x)) * tile_size.x,
                        @as(f32, @floatFromInt(pos.y)) * tile_size.y,
                    );
                    self.snap_to_grid = true;
                }
            }

            if (self.palette.eraser_mode and self.mouse_scene_pos != null) {
                for (self.scene_data.items, 0..) |item, i| {
                    const mob_hitbox = item.getHitboxRect();
                    const pos = item.getInitialPos();

                    const h_rect = rl.Rectangle.init(
                        pos.x,
                        pos.y,
                        mob_hitbox.width,
                        mob_hitbox.height,
                    );

                    const should_delete = rl.checkCollisionCircleRec(
                        mouse_scene_pos.?,
                        eraser_radius,
                        h_rect,
                    );

                    self.marked_for_deletion[i] = should_delete;
                }

                if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
                    for (0..self.scene_data.items.len) |i| {
                        if (self.marked_for_deletion[i]) {
                            remove_fn(editor.scene, i);
                        }
                    }
                }
            }

            if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) blk: {
                const selected_item = self.palette.selected_item orelse break :blk;
                const msp = self.mouse_scene_pos orelse return;
                const sprite = self.palette.sprites[selected_item];
                const sprite_frame = sprite.animation.getFrame() orelse break :blk;
                const sprite_size_x = @as(f32, @floatFromInt(sprite_frame.width));
                const sprite_size_y = @as(f32, @floatFromInt(sprite_frame.height));

                const sprite_offset = self.palette.sprite_offsets[selected_item];
                const spawn_pos = rl.Vector2.init(
                    msp.x - (if (self.snap_to_grid) 0 else sprite_size_x / 2) + sprite_offset.x,
                    msp.y - (if (self.snap_to_grid) 0 else sprite_size_y / 2) + sprite_offset.y,
                );
                try spawn_fn(editor.scene, selected_item, spawn_pos, editor.gamestate);
            }
        }

        pub fn draw(self: *const @This(), editor: *const Editor) void {
            const mouse_scene_pos = self.mouse_scene_pos orelse return;

            for (self.scene_data.items, 0..) |item, i| {
                if (item.is_deleted) {
                    continue;
                }

                // var pos = item.getInitialPos();
                //
                // pos.x -= item.sprite_offset.x;
                // pos.y -= item.sprite_offset.y;
                const pos = an.DrawPosition.init(
                    item.getInitialPos(),
                    .TopLeft,
                    item.sprite_offset,
                );
                const is_marked_for_deletion = self.marked_for_deletion[i];
                const color = if (is_marked_for_deletion) rl.Color.red.fade(0.5) else rl.Color.white.fade(0.5);
                item.sprite.draw(editor.scene, pos, color);
            }

            const selected_item = self.palette.selected_item;
            if (selected_item) |item_idx| {
                const sprite = self.palette.sprites[item_idx];
                const draw_pos = an.DrawPosition.init(
                    mouse_scene_pos,
                    .Center,
                    .{ .x = 0, .y = 0 },
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

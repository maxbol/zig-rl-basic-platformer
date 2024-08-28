const Tileset = @This();
const constants = @import("../constants.zig");
const debug = @import("../debug.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");
const std = @import("std");

ptr: *anyopaque,
impl: *const Interface,

pub const Interface = struct {
    getRect: *const fn (ctx: *anyopaque, tile_index: usize) ?rl.Rectangle,
    getRectMap: *const fn (ctx: *anyopaque) []?rl.Rectangle,
    getTexture: *const fn (ctx: *anyopaque) rl.Texture2D,
    getTileSize: *const fn (ctx: *anyopaque) rl.Vector2,
    isCollidable: *const fn (ctx: *anyopaque, tile_index: usize) bool,
};

pub fn getRectMap(self: Tileset) []?rl.Rectangle {
    return self.impl.getRectMap(self.ptr);
}

pub fn getTexture(self: Tileset) rl.Texture2D {
    return self.impl.getTexture(self.ptr);
}

pub fn isCollidable(self: Tileset, tile_index: usize) bool {
    return self.impl.isCollidable(self.ptr, tile_index);
}

pub fn getTileSize(self: Tileset) rl.Vector2 {
    return self.impl.getTileSize(self.ptr);
}

pub fn getRect(self: Tileset, tile_idx: usize) ?rl.Rectangle {
    return self.impl.getRect(self.ptr, tile_idx);
}

pub fn drawRect(self: Tileset, tile_index: usize, dest: rl.Vector2, cull_x: f32, cull_y: f32, tint: rl.Color) void {
    const rect = self.getRect(tile_index) orelse {
        // std.log.warn("Warning: tile index {d} not found in tilemap\n", .{tile_index});
        return;
    };

    const drawn = helpers.culledRectDraw(self.getTexture(), rect, dest, tint, cull_x, cull_y);

    if (debug.isDebugFlagSet(.ShowTilemapDebug)) {
        const r = drawn[0];
        const d = drawn[1];

        var debug_label_buf: [8]u8 = undefined;
        const debug_label = std.fmt.bufPrintZ(&debug_label_buf, "{d}", .{tile_index}) catch {
            std.log.err("Error: failed to format debug label\n", .{});
            return;
        };
        rl.drawRectangleLines(@intFromFloat(d.x), @intFromFloat(d.y), @intFromFloat(r.width), @intFromFloat(r.height), rl.Color.red);
        rl.drawText(debug_label, @intFromFloat(d.x), @intFromFloat(d.y), @intFromFloat(@floor(r.width / 2)), rl.Color.red);
    }
}

pub const FixedSizeTileset = @import("fixed_size_tileset.zig").FixedSizeTileset;

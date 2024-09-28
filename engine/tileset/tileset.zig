const Tileset = @This();
const constants = @import("../constants.zig");
const debug = @import("../debug.zig");
const helpers = @import("../helpers.zig");
const rl = @import("raylib");
const std = @import("std");

ptr: *anyopaque,
impl: *const Interface,

pub const Interface = struct {
    destroy: *const fn (ctx: *anyopaque) void,
    getRect: *const fn (ctx: *anyopaque, tile_index: usize) ?rl.Rectangle,
    getRectMap: *const fn (ctx: *anyopaque) []?rl.Rectangle,
    getTexture: *const fn (ctx: *anyopaque) rl.Texture2D,
    getTileSize: *const fn (ctx: *anyopaque) rl.Vector2,
    getTileFlags: *const fn (ctx: *anyopaque, tile_index: usize) u8,
    isCollidable: *const fn (ctx: *anyopaque, tile_index: usize) bool,
    tileHasFlag: *const fn (ctx: *anyopaque, tile_index: usize, flag: TileFlag) bool,
};

pub fn destroy(self: Tileset) void {
    return self.impl.destroy(self.ptr);
}

pub fn getRectMap(self: Tileset) []?rl.Rectangle {
    return self.impl.getRectMap(self.ptr);
}

pub fn getTexture(self: Tileset) rl.Texture2D {
    return self.impl.getTexture(self.ptr);
}

pub fn getTileFlags(self: Tileset, tile_index: usize) u8 {
    return self.impl.getTileFlags(self.ptr, tile_index);
}

pub fn isCollidable(self: Tileset, tile_index: usize) bool {
    return self.impl.isCollidable(self.ptr, tile_index);
}

pub fn getTileSize(self: Tileset) rl.Vector2 {
    return self.impl.getTileSize(self.ptr);
}

pub fn tileHasFlag(self: Tileset, tile_index: usize, flag: TileFlag) bool {
    return self.impl.tileHasFlag(self.ptr, tile_index, flag);
}

pub fn getRect(self: Tileset, tile_idx: usize) ?rl.Rectangle {
    return self.impl.getRect(self.ptr, tile_idx);
}

pub fn drawRect(self: Tileset, tile_index: usize, dest: rl.Vector2, cull_x: f32, cull_y: f32, tint: rl.Color) void {
    const rect = self.getRect(tile_index) orelse {
        // std.log.warn("Warning: tile index {d} not found in tilemap\n", .{tile_index});
        return;
    };

    const dst_rect = rl.Rectangle.init(dest.x, dest.y, rect.width, rect.height);
    const drawn = helpers.culledRectDraw(self.getTexture(), rect, dst_rect, tint, cull_x, cull_y);

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

pub const TILESET_SIZE_256 = 256;
pub const TILESET_SIZE_512 = 512;
pub const TILESET_SIZE_1024 = 1024;
pub const TILESET_SIZE_2048 = 2048;
pub const TILESET_SIZE_4096 = 4096;

pub const FixedSizeTileset = @import("fixed_size_tileset.zig").FixedSizeTileset;

pub const Tileset256 = FixedSizeTileset(256);
pub const Tileset512 = FixedSizeTileset(512);
pub const Tileset1024 = FixedSizeTileset(1024);
pub const Tileset2048 = FixedSizeTileset(2048);
pub const Tileset4096 = FixedSizeTileset(4096);

pub const data_format_version = 1;

pub fn readBytes(allocator: std.mem.Allocator, reader: anytype) !Tileset {
    // Version byte
    const version = try reader.readByte();
    if (version != data_format_version) {
        @panic("Invalid data format version");
    }

    // Tile size
    const tile_size_x_bytes = try reader.readBytesNoEof(4);
    const tile_size_y_bytes = try reader.readBytesNoEof(4);
    const tile_size_x: f32 = std.mem.bytesToValue(
        f32,
        &tile_size_x_bytes,
    );
    const tile_size_y: f32 = std.mem.bytesToValue(
        f32,
        &tile_size_y_bytes,
    );
    const tile_size = rl.Vector2.init(tile_size_x, tile_size_y);

    // Map size
    const map_size = try reader.readInt(u16, std.builtin.Endian.big);

    // Collision map
    var flag_map = std.mem.zeroes([TILESET_SIZE_4096]u8);
    for (0..map_size) |byte_idx| {
        const byte = try reader.readByte();
        flag_map[byte_idx] = byte;
        // for (0..8) |bit_idx| {
        //     if (byte & (@as(u8, 1) << (7 - @as(u3, @intCast(bit_idx)))) != 0) {
        //         collision_map[(byte_idx * 8) + bit_idx] = true;
        //     }
        // }
    }

    // Image data
    var image_data_buf: [1024 * 30]u8 = undefined;
    const image_data_len = try reader.readAll(&image_data_buf);
    const image_data = image_data_buf[0..image_data_len];

    if (map_size >= TILESET_SIZE_4096) {
        return error.TilesetTooBig;
    }

    if (map_size >= TILESET_SIZE_2048) {
        return (try Tileset4096.create(image_data, tile_size, flag_map[0..4096], allocator)).tileset();
    } else if (map_size >= TILESET_SIZE_1024) {
        return (try Tileset2048.create(image_data, tile_size, flag_map[0..2048], allocator)).tileset();
    } else if (map_size >= TILESET_SIZE_512) {
        return (try Tileset1024.create(image_data, tile_size, flag_map[0..1024], allocator)).tileset();
    } else if (map_size >= TILESET_SIZE_256) {
        return (try Tileset512.create(image_data, tile_size, flag_map[0..512], allocator)).tileset();
    } else {
        return (try Tileset256.create(image_data, tile_size, flag_map[0..256], allocator)).tileset();
    }
}

pub fn loadTilesetFromFile(allocator: std.mem.Allocator, file_path: []const u8) !Tileset {
    const Cache = struct {
        var map: ?std.StringHashMap(Tileset) = null;
    };
    if (Cache.map == null) {
        Cache.map = std.StringHashMap(Tileset).init(allocator);
    }
    if (Cache.map.?.contains(file_path)) {
        return Cache.map.?.get(file_path) orelse unreachable;
    }
    const file = try helpers.openFile(file_path, .{ .mode = .read_only });
    defer file.close();
    return readBytes(allocator, file.reader());
}

pub const TileFlag = enum(u8) {
    Collidable = 0b00000001,
    Slippery = 0b00000010,
    Deadly = 0b00000100,

    pub fn mask(flags: []TileFlag) u8 {
        var result: u8 = 0;
        for (flags) |flag| {
            result |= flag;
        }
        return result;
    }
};

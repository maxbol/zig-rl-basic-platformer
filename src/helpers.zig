const rl = @import("raylib");
const std = @import("std");

pub fn buildRectMap(comptime size: usize, source_width: i32, source_height: i32, rec_width: f32, rec_height: f32, x_dir: i2, y_dir: i2) [size]?rl.Rectangle {
    const source_read_max_x: f32 = @floor(@as(f32, @floatFromInt(source_width)) / rec_width);
    const source_read_max_y: f32 = @floor(@as(f32, @floatFromInt(source_height)) / rec_height);

    const source_width_f: f32 = @floatFromInt(source_width);
    const source_height_f: f32 = @floatFromInt(source_height);

    if (source_read_max_x * rec_width != source_width_f) {
        std.log.warn("Warning: source width is not a multiple of rec width\n", .{});
    }

    if (source_read_max_y * rec_height != source_height_f) {
        std.log.warn("Warning: source height is not a multiple of rec height\n", .{});
    }

    var x_cursor: f32 = 0;
    var y_cursor: f32 = 0;
    var tile_index: usize = 1;

    var map: [size]?rl.Rectangle = .{null} ** size;

    while (y_cursor <= source_read_max_y - 1) : (y_cursor += 1) {
        x_cursor = 0;
        while (x_cursor <= source_read_max_x - 1) : ({
            x_cursor += 1;
            tile_index += 1;
        }) {
            map[tile_index] = rl.Rectangle.init(x_cursor * rec_width, y_cursor * rec_height, rec_width * @as(f32, @floatFromInt(x_dir)), rec_height * @as(f32, @floatFromInt(y_dir)));
        }
    }

    return map;
}

pub fn culledRectDraw(texture: rl.Texture2D, rect: rl.Rectangle, dest: rl.Vector2, tint: rl.Color, cull_x: f32, cull_y: f32) struct { rl.Rectangle, rl.Vector2 } {
    var r = rect;
    var d = dest;

    const width_dir = std.math.sign(r.width);
    const height_dir = std.math.sign(r.height);

    std.debug.assert(rect.width != 0);

    // Some of this logic is somewhat convoluted and hard to understand.
    // Basically we swap some parts of the logic around based on whether the source
    // rect has a negative width or height, which indicates that is should be drawn
    // flipped. A flipped sprite needs to be culled somewhat differently.

    if (width_dir * cull_x > 0) {
        r.x += width_dir * cull_x;
        r.width -= cull_x;
        if (r.width >= 0) {
            d.x += cull_x;
        }
    } else if (width_dir * cull_x < 0) {
        r.width += cull_x;
        if (r.width < 0) {
            d.x += cull_x;
        }
    }

    if (height_dir * cull_y > 0) {
        r.y += height_dir * cull_y;
        r.height -= cull_y;
        if (r.height >= 0) {
            d.y += cull_y;
        }
    } else if (height_dir * cull_y < 0) {
        r.height += cull_y;
        if (r.height < 0) {
            d.y += cull_y;
        }
    }

    texture.drawRec(r, d, tint);

    return .{ r, d };
}

pub fn getMovementVectors() [16]rl.Vector2 {
    // This constant can't be constructed in comptime because it uses extern calls to raylib.
    // I'm not sure if there is a better way of solving this.
    return .{
        // 0 - None
        rl.Vector2.init(0, 0),
        // 1 - Up
        rl.Vector2.init(0, -1),
        // 2 - Left
        rl.Vector2.init(-1, 0),
        // 3 - Up + Left
        rl.Vector2.init(-1, -1).scale(std.math.sqrt2).normalize(),
        // 4 - Down
        rl.Vector2.init(0, 1),
        // 5 - Up + Down (invalid)
        rl.Vector2.init(0, 0),
        // 6 - Left + Down
        rl.Vector2.init(-1, 1).scale(std.math.sqrt2).normalize(),
        // 7 - Up + Left + Down (invalid)
        rl.Vector2.init(0, 0),
        // 8 - Right
        rl.Vector2.init(1, 0),
        // 9 - Up + Right
        rl.Vector2.init(1, -1).scale(std.math.sqrt2).normalize(),
        // 10 - Left + Right (invalid)
        rl.Vector2.init(0, 0),
        // 11 - Up + Left + Right (invalid)
        rl.Vector2.init(0, 0),
        // 12 - Down + Right
        rl.Vector2.init(1, 1).scale(std.math.sqrt2).normalize(),
        // 13 - Up + Down + Right (invalid)
        rl.Vector2.init(0, 0),
        // 14 - Left + Down + Right (invalid)
        rl.Vector2.init(0, 0),
        // 15 - Up + Left + Down + Right (invalid)
        rl.Vector2.init(0, 0),
    };
}

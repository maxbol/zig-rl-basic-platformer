const rl = @import("raylib");
const std = @import("std");
const shapes = @import("shapes.zig");

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

// Creates the smallest possible rectangle that contains both rect_a and rect_b
pub fn combineRects(rect_a: rl.Rectangle, rect_b: rl.Rectangle) rl.Rectangle {
    const min_x = @min(rect_a.x, rect_b.x);
    const min_y = @min(rect_a.y, rect_b.y);
    const max_x = @max(rect_a.x + rect_a.width, rect_b.x + rect_b.width);
    const max_y = @max(rect_a.y + rect_a.height, rect_b.y + rect_b.height);

    return rl.Rectangle.init(min_x, min_y, max_x - min_x, max_y - min_y);
}

pub fn drawVec2AsArrow(origin: rl.Vector2, vec: rl.Vector2, color: rl.Color) void {
    const arrow_head = origin.add(vec);
    // const arrow_head_left = origin.add(vec.add(vec.rotate(-45).normalize().scale(5)));
    // const arrow_head_right = origin.add(vec.add(vec.rotate(45).normalize().scale(5)));

    rl.drawLineV(origin, arrow_head, color);
    // rl.drawTriangle(arrow_head, arrow_head_left, arrow_head_right, color);
}

pub fn getAbsolutePos(origin: anytype, pos: anytype) @TypeOf(pos) {
    var new = pos;
    new.x += origin.x;
    new.y += origin.y;
    return new;
}

pub fn getRelativePos(origin: anytype, pos: anytype) rl.Vector2 {
    return .{
        .x = pos.x - origin.x,
        .y = pos.y - origin.y,
    };
}

pub fn getGridPos(grid_size: shapes.IPos, pos: shapes.IPos) shapes.IPos {
    var new = pos;
    new.x = @divFloor(new.x, grid_size.x);
    new.y = @divFloor(new.y, grid_size.y);
    return new;
}

pub fn getGridRect(grid_size: shapes.IPos, pos: shapes.IRect) @TypeOf(pos) {
    var new = pos;
    new.x = @divFloor(new.x, grid_size.x);
    new.y = @divFloor(new.y, grid_size.y);
    // new.x = @intFromFloat(@round(@as(f32, @floatFromInt(new.x)) / @as(f32, @floatFromInt(grid_size.x))));
    // new.y = @intFromFloat(@round(@as(f32, @floatFromInt(new.y)) / @as(f32, @floatFromInt(grid_size.y))));
    new.width = std.math.divCeil(@TypeOf(new.width), new.width + @mod(pos.x, grid_size.x), grid_size.x) catch {
        @panic("Something went really wrong\n");
    };
    new.height = std.math.divCeil(@TypeOf(new.height), new.height + @mod(pos.y, grid_size.y), grid_size.y) catch {
        @panic("Something went really wrong\n");
    };
    return new;
}

pub fn getPixelPos(grid_size: anytype, pos: anytype) @TypeOf(pos) {
    var new = pos;
    new.x *= grid_size.x;
    new.y *= grid_size.y;
    return new;
}

pub fn getPixelRect(grid_size: anytype, pos: anytype) @TypeOf(pos) {
    var new = pos;
    new.x *= grid_size.x;
    new.y *= grid_size.y;
    new.width *= grid_size.x;
    new.height *= grid_size.y;
    return new;
}

pub fn approach(current: f32, target: f32, increase: f32) f32 {
    if (current < target) {
        return @min(current + increase, target);
    } else {
        return @max(current - increase, target);
    }
}

pub inline fn createRandomizer() !std.Random {
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    return prng.random();
}

pub fn drawRectBorder(rect: rl.Rectangle, border_width: f32, color: rl.Color) void {
    const border_rect = rl.Rectangle.init(
        rect.x - border_width,
        rect.y - border_width,
        rect.width + (border_width * 2),
        rect.height + (border_width * 2),
    );
    rl.drawRectangleLinesEx(border_rect, border_width, color);
}

pub fn openFile(path: []const u8, flags: std.fs.File.OpenFlags) !std.fs.File {
    const cwd = std.fs.cwd();
    var exists = true;

    cwd.access(path, .{}) catch {
        exists = false;
    };

    if (exists == false) {
        _ = try cwd.createFile(path, .{});
    }

    return cwd.openFile(path, flags);
}

const an = @import("animation.zig");
const rl = @import("raylib");
const std = @import("std");

var debug_mode: u16 = 0;
var is_paused: bool = false;

pub inline fn togglePause() void {
    is_paused = !is_paused;
}

pub inline fn isPaused() bool {
    return is_paused;
}

pub const DebugFlag = enum(u16) {
    None = 0b0,
    ShowHitboxes = 0b1,
    ShowTilemapDebug = 0b10,
    ShowScrollState = 0b100,
    ShowFps = 0b1000,
    ShowSpriteOutlines = 0b10000,
    ShowTestedTiles = 0b100000,
    ShowCollidedTiles = 0b1000000,
    ShowGridBoxes = 0b10000000,
    ShowSpritePreviewer = 0b100000000,
};

pub fn isDebugFlagSet(flag: DebugFlag) bool {
    return debug_mode & @intFromEnum(flag) != 0;
}

pub fn clearDebugFlags() void {
    debug_mode = 0;
}

pub fn setDebugFlags(flags: []const DebugFlag) void {
    for (flags) |flag| {
        debug_mode |= @intFromEnum(flag);
    }
}

pub const SpriteDebugPreviewer = struct {
    sprite_reader: an.AnySpriteBuffer,

    pub fn init(sprite_reader: an.AnySpriteBuffer) SpriteDebugPreviewer {
        return .{
            .sprite_reader = sprite_reader,
        };
    }

    pub fn update(self: SpriteDebugPreviewer) void {
        _ = self; // autofix
    }

    pub fn draw(self: *const SpriteDebugPreviewer) void {
        const PADDING_X = 10;
        const PADDING_Y = 10;

        var y_offset: i32 = 0;
        //
        var it = self.sprite_reader.iterate();

        while (it.next() catch |err| {
            std.log.err("Error iterating sprite reader: {}", .{err});
            return;
        }) |animation| {
            var x_offset: i32 = 0;
            var max_y: i32 = 0;
            for (animation.anim_data.frames) |frame| {
                if (frame) |rt| {
                    rl.drawTexture(rt.texture, x_offset, y_offset, rl.Color.white);
                    x_offset += rt.texture.width + PADDING_X;
                    max_y = @max(max_y, rt.texture.height);
                }
            }
            y_offset += max_y + PADDING_Y;
        }
    }
};

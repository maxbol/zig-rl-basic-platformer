const rl = @import("raylib");
const std = @import("std");

pub const IRect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,

    pub fn fromRect(rect: rl.Rectangle) IRect {
        return .{
            .x = @intFromFloat(@floor(rect.x)),
            .y = @intFromFloat(@floor(rect.y)),
            .width = @intFromFloat(@floor(rect.width)),
            .height = @intFromFloat(@floor(rect.height)),
        };
    }

    pub fn toRect(self: IRect) rl.Rectangle {
        return rl.Rectangle.init(
            @floatFromInt(self.x),
            @floatFromInt(self.y),
            @floatFromInt(self.width),
            @floatFromInt(self.height),
        );
    }

    pub fn isColliding(self: IRect, other: IRect) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }
};

pub const IPos = struct {
    x: i32,
    y: i32,

    pub fn fromVec2(vec: rl.Vector2) IPos {
        return .{
            .x = @intFromFloat(@floor(vec.x)),
            .y = @intFromFloat(@floor(vec.y)),
        };
    }
};

pub const CollisionDirection = enum(u4) {
    None = 0,
    Up = 1,
    Down = 2,
    Left = 4,
    Right = 8,

    pub fn mask(flags: []const CollisionDirection) u4 {
        var result: u4 = 0;
        for (flags) |flag| {
            result |= @intFromEnum(flag);
        }
        return result;
    }
};

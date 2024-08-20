var debug_mode: u8 = 0;

pub const DebugFlag = enum(u8) {
    None = 0b00000000,
    ShowHitboxes = 0b00000001,
    ShowTilemapDebug = 0b00000010,
    ShowScrollState = 0b00000100,
};

pub fn isDebugFlagSet(flag: DebugFlag) bool {
    return debug_mode & @intFromEnum(flag) != 0;
}

pub fn setDebugFlags(flags: []const DebugFlag) void {
    for (flags) |flag| {
        debug_mode |= @intFromEnum(flag);
    }
}

var debug_mode: u8 = 0;
var is_paused: bool = false;

pub inline fn togglePause() void {
    is_paused = !is_paused;
}

pub inline fn isPaused() bool {
    return is_paused;
}

pub const DebugFlag = enum(u8) {
    None = 0b00000000,
    ShowHitboxes = 0b00000001,
    ShowTilemapDebug = 0b00000010,
    ShowScrollState = 0b00000100,
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

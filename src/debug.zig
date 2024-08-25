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
    ShowFps = 0b00001000,
    ShowSpriteOutlines = 0b00010000,
    ShowTestedTiles = 0b00100000,
    ShowCollidedTiles = 0b01000000,
    ShowGridBoxes = 0b10000000,
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

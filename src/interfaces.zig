const Player = @import("player.zig");
const Mob = @import("mob.zig");

pub const Actor = union {
    Player: Player,
    Mob: Mob,
};

pub const Entity = union {};

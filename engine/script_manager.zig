const GameState = @import("gamestate.zig");
const Scene = @import("scene.zig");
const ScriptManager = @This();
const std = @import("std");
const tracing = @import("tracing.zig");
const ziglua = @import("ziglua");

fn getThisMobSpeedX(lua: *Lua) i32 {
    const script = Script.current(lua) catch {
        lua.pushNil();
        return 1;
    };
    const scene = script.manager.scene;
    lua.pushNumber(scene.mobs.items[script.entity_idx].speed.x);
    return 1;
}

fn setThisMobSpeedX(lua: *Lua) i32 {
    const script = Script.current(lua) catch {
        lua.pushNil();
        return 1;
    };
    const speed_x = lua.toNumber(1) catch {
        lua.pushNil();
        return 1;
    };
    const scene = script.manager.scene;
    scene.mobs.items[script.entity_idx].speed.x = @floatCast(speed_x);
    return 0;
}

const Lua = ziglua.Lua;
const ScriptMap = std.AutoArrayHashMapUnmanaged(usize, Script);

pub const Script = struct {
    manager: *ScriptManager,
    ref: i32,
    entity_idx: usize,

    pub const SCRIPT_REF = "script_ref";

    pub fn current(lua: *Lua) !*const Script {
        switch (try lua.getGlobal(SCRIPT_REF)) {
            .light_userdata => {},
            else => |t| {
                std.debug.print("script_ref type: {s}\n", .{@tagName(t)});
                return error.InvalidScriptRef;
            },
        }
        return @ptrCast(@alignCast(try lua.toPointer(-1)));
    }

    pub fn run(script: *Script, delta_time: f32) !void {
        const zone = tracing.ZoneN(@src(), "Script Run");
        defer zone.End();

        const scene = script.manager.scene;
        if (script.entity_idx >= scene.mobs.items.len) {
            return error.InvalidEntityIndex;
        }

        const lua = script.manager.lua;

        lua.pushLightUserdata(script);
        lua.setGlobal(SCRIPT_REF);

        lua.register("get_this_mob_speed_x", ziglua.wrap(getThisMobSpeedX));
        lua.register("set_this_mob_speed_x", ziglua.wrap(setThisMobSpeedX));

        const luatype = lua.rawGetIndex(ziglua.registry_index, script.ref);
        switch (luatype) {
            .table => {},
            else => {
                return error.InvalidScriptType;
            },
        }

        _ = lua.pushString("update");
        const fn_type = lua.getTable(-2);

        switch (fn_type) {
            .function => {},
            else => {
                std.log.err("ScriptEngine: Script does not have an update method.\n", .{});
                return error.InvalidScriptType;
            },
        }

        lua.pushNumber(delta_time);
        try lua.protectedCall(1, 0, 0);

        // Not sure why this is necessary, what is not being cleaned up?
        lua.pop(1);
    }
};

// Borrowed
allocator: std.mem.Allocator,
gamestate: *GameState,
scene: *Scene,

// Owned
lua: *Lua,
ref: i32,
scripts: ScriptMap,

pub fn fromLuaRef(lua: *Lua, lua_ref: i32) !*ScriptManager {
    switch (lua.rawGetIndex(lua_ref, ziglua.registry_index)) {
        .userdata => {},
        else => {
            return error.InvalidSMRef;
        },
    }
    return @ptrCast(@alignCast(try lua.toPointer(-1)));
}

pub fn create(allocator: std.mem.Allocator, scene: *Scene, gamestate: *GameState) !*ScriptManager {
    const script_engine = try allocator.create(ScriptManager);

    script_engine.allocator = allocator;
    script_engine.gamestate = gamestate;
    script_engine.scene = scene;
    script_engine.scripts = .{};

    // Init LUA
    {
        var lua = try Lua.init(&script_engine.allocator);
        lua.openLibs();
        lua.pushLightUserdata(script_engine);
        script_engine.lua = lua;
        script_engine.ref = try lua.ref(-1);
    }

    return script_engine;
}

pub fn destroy(script_manager: *ScriptManager) void {
    script_manager.lua.deinit();
    script_manager.scripts.deinit(script_manager.allocator);
    script_manager.allocator.destroy(script_manager);
}

pub fn iterator(script_manager: *ScriptManager) ScriptMap.Iterator {
    return script_manager.scripts.iterator();
}

pub fn loadByteCode(
    script_manager: *ScriptManager,
    entity_idx: usize,
    byte_code: []const u8,
) !void {
    const zone = tracing.ZoneN(@src(), "ScriptManager Load byte code");
    defer zone.End();

    const lua = script_manager.lua;
    try lua.loadBytecode("...", byte_code);
    try lua.protectedCall(0, 1, 0);

    const is_ret_nil = lua.isNil(-1);
    std.debug.print("is_ret_nil={any}\n", .{is_ret_nil});
    // const ref = try lua.ref(-1);
    const ref = try lua.ref(-1);

    const t = lua.rawGetIndex(ziglua.registry_index, ref);

    std.log.info("t={s}\n", .{@tagName(t)});

    const script: Script = .{
        .ref = ref,
        .entity_idx = entity_idx,
        .manager = script_manager,
    };

    try script_manager.scripts.put(script_manager.allocator, entity_idx, script);
}

pub fn unloadByteCode(script_manager: *ScriptManager, entity_idx: usize) void {
    defer script_manager.scripts.swapRemove(entity_idx);
    script_manager.lua.unref((script_manager.scripts.get(entity_idx) orelse {
        std.log.warn(
            "ScriptEngine: Tried to unload script that is not in registry. Likely this means that the script was already unloaded somewhere else.\n",
            .{},
        );
        return;
    }).ref);
}

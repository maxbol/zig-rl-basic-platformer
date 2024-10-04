const std = @import("std");
pub const TracerBuild = @import("tracer-build.zig");

fn addRaylib(b: *std.Build, m: *std.Build.Module, dep_opts: anytype) void {
    const raylib_dep = b.dependency("raylib-zig", dep_opts);

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    m.linkLibrary(raylib_artifact);
    m.addImport("raylib", raylib);
    m.addImport("raygui", raygui);
}

fn addDeps(b: *std.Build, tb: TracerBuild, c: *std.Build.Step.Compile, dep_opts: anytype) void {
    tb.addTracing(b, c, dep_opts);
    addRaylib(b, &c.root_module, dep_opts);
}

pub fn build(b: *std.Build) !void {
    const hotreload = b.option(bool, "hotreload", "Enable hot-reloading") orelse false;
    const game_only = b.option(bool, "game_only", "Build only the hotloading game dynlib, not the dev environment") orelse false;
    const engine_dll_ts = b.option([]const u8, "engine_dll_ts", "Timestamp of the engine dynlib") orelse null;
    const tracy_path = b.option([]const u8, "tracy", "Enable Tracy integration. Supply path to Tracy source");
    const tracy_callstack_depth = b.option(u8, "tracy_callstack_depth", "Set desired callstack depth. Does nothing if -Dtracy_path is not provided") orelse 10;
    const tracy_include_allocation = b.option(bool, "tracy_allocation", "Include allocation information with Tracy data. Does nothing if -Dtracy is not provided") orelse (tracy_path != null);

    // Hot reload always needs to get set to true if -Dgame_only is set, otherwise no engine DLL can be built
    //
    if (game_only == true and hotreload == false) {
        std.log.err("Hot reload must be enabled if building only the game dynlib", .{});
        return error.InvalidBuild;
    }

    if (hotreload == true and tracy_path != null) {
        std.log.err("Currently no support for running tracy and hotreloading at the same time\n", .{});
        return error.InvalidBuild;
    }

    const tb = TracerBuild.init(tracy_path, tracy_callstack_depth, tracy_include_allocation);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const run_step = b.step("run", "Run the app");
    const test_step = b.step("test", "Run unit tests");
    const check_step = b.step("check", "Check if the program compiles");

    const dep_opts = .{ .target = target, .optimize = optimize, .shared = true };

    if (hotreload) {
        const engine_lib_name = if (engine_dll_ts) |ts| blk: {
            var name_buf: [256]u8 = undefined;
            break :blk std.fmt.bufPrint(&name_buf, "engine-hr-{s}", .{ts}) catch @panic("Out of memory");
        } else "engine";

        var engine_lib = b.addSharedLibrary(.{
            .name = engine_lib_name,
            .root_source_file = b.path("engine/shared.zig"),
            .target = target,
            .optimize = optimize,
            .version = .{ .major = 0, .minor = 1, .patch = 0 },
        });

        addDeps(b, tb, engine_lib, dep_opts);

        b.installArtifact(engine_lib);
        check_step.dependOn(&engine_lib.step);
    }

    if (!game_only) {
        const exe = if (hotreload) b.addExecutable(.{
            .name = "knight-jumper",
            .root_source_file = b.path("hotreload/main.zig"),
            .target = target,
            .optimize = optimize,
        }) else b.addExecutable(.{
            .name = "knight-jumper",
            .root_source_file = b.path("engine/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        addDeps(b, tb, exe, dep_opts);
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);

        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        run_step.dependOn(&run_cmd.step);
        check_step.dependOn(&exe.step);
    }

    // Build unit tests
    const engine_unit_tests = b.addTest(.{
        .root_source_file = b.path("engine/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    addDeps(b, tb, engine_unit_tests, dep_opts);

    const run_engine_unit_tests = b.addRunArtifact(engine_unit_tests);

    const hotreloader_test = b.addTest(.{
        .root_source_file = b.path("hotreload/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    addDeps(b, tb, hotreloader_test, dep_opts);

    const run_hotreloader_test = b.addRunArtifact(hotreloader_test);

    test_step.dependOn(&run_engine_unit_tests.step);
    test_step.dependOn(&run_hotreloader_test.step);
}

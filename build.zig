const std = @import("std");

fn addDeps(b: *std.Build, m: *std.Build.Module, dep_opts: anytype) void {
    const raylib_dep = b.dependency("raylib-zig", dep_opts);

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    m.linkLibrary(raylib_artifact);
    m.addImport("raylib", raylib);
    m.addImport("raygui", raygui);
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const game_only = b.option(bool, "game_only", "Build only the game, not the dev environment") orelse false;
    const engine_dll_ts = b.option([]const u8, "engine_dll_ts", "Timestamp of the engine DLL") orelse null;
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const dep_opts = .{ .target = target, .optimize = optimize, .shared = true };

    const engine_lib_name = if (engine_dll_ts) |ts| blk: {
        var name_buf: [256]u8 = undefined;
        break :blk std.fmt.bufPrint(&name_buf, "engine-hr-{s}", .{ts}) catch @panic("Out of memory");
    } else "engine";

    const engine_lib = b.addSharedLibrary(.{
        .name = engine_lib_name,
        .root_source_file = b.path("engine/root.zig"),
        .target = target,
        .optimize = optimize,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });
    addDeps(b, &engine_lib.root_module, dep_opts);
    b.installArtifact(engine_lib);

    const run_step = b.step("run", "Run the app");
    const check = b.step("check", "Check if the program compiles");

    check.dependOn(&engine_lib.step);

    if (!game_only) {
        const exe = b.addExecutable(.{
            .name = "knight-jumper",
            .root_source_file = b.path("hotreload/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        addDeps(b, &exe.root_module, dep_opts);
        b.installArtifact(exe);
        // This *creates* a Run step in the build graph, to be executed when another
        // step is evaluated that depends on it. The next line below will establish
        // such a dependency.
        const run_cmd = b.addRunArtifact(exe);

        // By making the run step depend on the install step, it will be run from the
        // installation directory rather than directly from within the cache directory.
        // This is not necessary, however, if the application depends on other installed
        // files, this ensures they will be present and in the expected location.
        run_cmd.step.dependOn(b.getInstallStep());

        // This allows the user to pass arguments to the application in the build
        // command itself, like this: `zig build run -- arg1 arg2 etc`
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        // This creates a build step. It will be visible in the `zig build --help` menu,
        // and can be selected like this: `zig build run`
        // This will evaluate the `run` step rather than the default, which is "install".
        run_step.dependOn(&run_cmd.step);
        check.dependOn(&exe.step);
    }

    const engine_unit_tests = b.addTest(.{
        .root_source_file = b.path("engine/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    addDeps(b, &engine_unit_tests.root_module, dep_opts);

    const run_exe_unit_tests = b.addRunArtifact(engine_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

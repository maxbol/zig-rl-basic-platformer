const std = @import("std");

pub const TracyOpts = struct {
    path_to_tracy: ?[]const u8,
    include_callstack: bool,
    include_allocation: bool,

    pub fn init(b: *std.Build) TracyOpts {
        const path_to_tracy = b.option([]const u8, "tracy", "Enable Tracy integration. Supply path to Tracy source");
        const include_callstack = b.option(bool, "tracy-callstack", "Include callstack information with Tracy data. Does nothing if -Dtracy is not provided") orelse (path_to_tracy != null);
        const include_allocation = b.option(bool, "tracy-allocation", "Include allocation information with Tracy data. Does nothing if -Dtracy is not provided") orelse (path_to_tracy != null);

        return .{
            .path_to_tracy = path_to_tracy,
            .include_callstack = include_callstack,
            .include_allocation = include_allocation,
        };
    }

    pub fn addTracing(self: TracyOpts, b: *std.Build, c: *std.Build.Step.Compile, dep_opts: anytype) void {
        const path = self.path_to_tracy orelse {
            std.log.info("Tracy not enabled", .{});
            return;
        };
        std.log.info("Tracy enabled", .{});

        const client_cpp = std.fs.path.join(
            b.allocator,
            &[_][]const u8{ path, "public", "TracyClient.cpp" },
        ) catch unreachable;

        // On mingw, we need to opt into windows 7+ to get some features required by tracy.
        const tracy_c_flags: []const []const u8 = if (dep_opts.target.result.isMinGW())
            &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined", "-D_WIN32_WINNT=0x601" }
        else
            &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined" };

        c.addIncludePath(b.path(path));
        c.addCSourceFiles(.{
            .files = &.{
                client_cpp,
            },
            .flags = tracy_c_flags,
        });
        c.linkLibC();
        c.linkSystemLibrary("c++");

        if (dep_opts.target.result.isMinGW()) {
            c.linkSystemLibrary("dbghelp");
            c.linkSystemLibrary("ws2_32");
        }
    }
};

fn addDeps(b: *std.Build, m: *std.Build.Module, dep_opts: anytype) void {
    const raylib_dep = b.dependency("raylib-zig", dep_opts);

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    m.linkLibrary(raylib_artifact);
    m.addImport("raylib", raylib);
    m.addImport("raygui", raygui);
}

pub fn build(b: *std.Build) void {
    // Our custom build options
    const game_only = b.option(bool, "game_only", "Build only the game, not the dev environment") orelse false;
    const engine_dll_ts = b.option([]const u8, "engine_dll_ts", "Timestamp of the engine DLL") orelse null;
    const tracy_opts = TracyOpts.init(b);
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_opts = .{ .target = target, .optimize = optimize, .shared = true };

    const engine_lib_name = if (engine_dll_ts) |ts| blk: {
        var name_buf: [256]u8 = undefined;
        break :blk std.fmt.bufPrint(&name_buf, "engine-hr-{s}", .{ts}) catch @panic("Out of memory");
    } else "engine";

    var engine_lib = b.addSharedLibrary(.{
        .name = engine_lib_name,
        .root_source_file = b.path("engine/root.zig"),
        .target = target,
        .optimize = optimize,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });
    tracy_opts.addTracing(b, engine_lib, dep_opts);
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

        tracy_opts.addTracing(b, exe, dep_opts);
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

    tracy_opts.addTracing(b, engine_unit_tests, dep_opts);
    addDeps(b, &engine_unit_tests.root_module, dep_opts);

    const run_exe_unit_tests = b.addRunArtifact(engine_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

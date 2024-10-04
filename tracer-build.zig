const TracerBuild = @This();
const std = @import("std");

path_to_tracy: ?[]const u8,
callstack_depth: u8,
include_allocation: bool,

pub fn init(path_to_tracy: ?[]const u8, callstack_depth: u8, include_allocation: bool) TracerBuild {
    return .{
        .path_to_tracy = path_to_tracy,
        .callstack_depth = callstack_depth,
        .include_allocation = include_allocation,
    };
}

pub fn addBuildOptions(tb: TracerBuild, b: *std.Build, m: *std.Build.Module) void {
    const options = b.addOptions();
    options.addOption(bool, "tracy_enabled", tb.path_to_tracy != null);
    options.addOption(bool, "include_callstack", tb.callstack_depth > 0);
    options.addOption(bool, "include_allocation", tb.include_allocation);
    m.addOptions("build_options", options);
}

pub fn addTracing(tb: TracerBuild, b: *std.Build, c: *std.Build.Step.Compile, dep_opts: anytype) void {
    tb.addBuildOptions(b, &c.root_module);

    const path = tb.path_to_tracy orelse {
        // std.log.info("Tracing not enabled", .{});
        return;
    };
    // std.log.info("Tracing enabled", .{});

    const client_cpp = std.fs.path.join(
        b.allocator,
        &[_][]const u8{ path, "public", "TracyClient.cpp" },
    ) catch unreachable;

    const include_path = std.fs.path.join(
        b.allocator,
        &[_][]const u8{ path, "public", "tracy" },
    ) catch unreachable;

    var c_flags_list = std.ArrayList([]const u8).init(b.allocator);

    c_flags_list.appendSlice(&.{
        "-DTRACY_ENABLE=1",
        "-fno-sanitize=undefined",
    }) catch unreachable;

    if (dep_opts.target.result.isMinGW()) {
        c_flags_list.appendSlice(&.{
            "-D_WIN32_WINNT=0x601",
        }) catch unreachable;
    }

    if (tb.callstack_depth > 0) {
        c_flags_list.appendSlice(&.{
            std.fmt.allocPrint(b.allocator, "-DTRACY_CALLSTACK={d}", .{tb.callstack_depth}) catch unreachable,
        }) catch unreachable;
    }

    const tracy_c_flags = c_flags_list.toOwnedSlice() catch unreachable;

    // c.addIncludePath(b.path(path));
    c.addIncludePath(b.path(include_path));
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

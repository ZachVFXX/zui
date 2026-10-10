const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zui = b.addModule("zui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Raylib
    const raylib_dep = b.dependency("raylib", .{ .target = target, .optimize = optimize });
    const raylib = raylib_dep.artifact("raylib");
    raylib.root_module.addCMacro("SUPPORT_FILEFORMAT_JPG", "1");
    zui.addImport("raylib", raylib_dep.module("raylib"));
    zui.linkLibrary(raylib);

    // Clay
    const zclay_dep = b.dependency("zclay", .{ .target = target, .optimize = optimize });
    zui.addImport("zclay", zclay_dep.module("zclay"));

    const gobject = b.dependency("gobject", .{});
    zui.addImport("pango", gobject.module("pango1"));
    zui.addImport("cairo", gobject.module("cairo1"));
    zui.addImport("pangocairo", gobject.module("pangocairo1"));
    zui.addImport("gobject", gobject.module("gobject2"));
    zui.addImport("glib", gobject.module("glib2"));

    const test_module = b.createModule(.{
        .root_source_file = b.path("test/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("zui", zui);

    // You must link the C libraries to the test module to build the executable
    test_module.linkLibrary(raylib);

    const test_exe = b.addExecutable(.{
        .name = "test_app",
        .root_module = test_module,
    });

    // debug symbol for samply
    test_exe.root_module.strip = false;
    test_exe.root_module.unwind_tables = .async;

    b.installArtifact(test_exe);

    const run = b.addRunArtifact(test_exe);
    const run_step = b.step("run", "Run test app");
    run_step.dependOn(&run.step);
}

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

    // HarfBuzz
    const harfbuzz_dep = b.dependency("harfbuzz", .{});
    const harfbuzz = b.addLibrary(.{
        .name = "harfbuzz",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libcpp = true,
        }),
        .linkage = .static,
    });

    // Use harfbuzz-world.cc instead of harfbuzz.cc
    // This bakes in libharfbuzz, libharfbuzz-subset, and libharfbuzz-raster.
    harfbuzz.root_module.addCSourceFile(.{
        .file = harfbuzz_dep.path("src/harfbuzz-world.cc"),
    });

    // Make HarfBuzz headers available to ZUI
    zui.addIncludePath(harfbuzz_dep.path("src"));
    zui.linkLibrary(harfbuzz);

    const test_module = b.createModule(.{
        .root_source_file = b.path("test/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("zui", zui);

    // You must link the C libraries to the test module to build the executable
    test_module.linkLibrary(raylib);
    test_module.linkLibrary(harfbuzz);

    const test_exe = b.addExecutable(.{
        .name = "test_app",
        .root_module = test_module,
    });

    b.installArtifact(test_exe);

    const run = b.addRunArtifact(test_exe);
    const run_step = b.step("run", "Run test app");
    run_step.dependOn(&run.step);
}

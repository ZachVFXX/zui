const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addModule("zui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,

        // .strip = false,
        // .unwind_tables = .async,
        .stack_check = true,
        .sanitize_c = .full,
        // .sanitize_thread = true,
    });

    // Sdl3
    const sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,

        // Lib options.
        .ext_image = false,
        .ext_mixer = false,
        .ext_net = false,
        .ext_shadercross = false,
        .ext_shadercross_dxc = false,
        .ext_ttf = false,
        // .log_message_stack_size = 1024,
        // .main = false,
        // .renderer_debug_text_stack_size = 1024,

        // Options passed directly to https://github.com/castholm/SDL (SDL3 C Bindings):
        .c_sdl_preferred_linkage = .static,
        // .c_sdl_strip = false,
        // .c_sdl_sanitize_c = .off,
        // .c_sdl_lto = .none,
        // .c_sdl_emscripten_pthreads = false,
        // .c_sdl_install_build_config_h = false,

        // Options if `ext_image` is enabled:
        // .image_enable_bmp = true,
        // .image_enable_gif = true,
        // .image_enable_jpg = true,
        // .image_enable_lbm = true,
        // .image_enable_pcx = true,
        // .image_enable_png = true,
        // .image_enable_pnm = true,
        // .image_enable_qoi = true,
        // .image_enable_svg = true,
        // .image_enable_tga = true,
        // .image_enable_xcf = true,
        // .image_enable_xpm = true,
        // .image_enable_xv = true,
        //
        // Options if `ext_mixer` is enabled:
        // .mixer_shared = false,
        //
        // Options if `ext_net` is enabled:
        // .net_shared = false,
    });

    lib.addImport("sdl3", sdl3.module("sdl3"));

    // Raylib
    // const raylib_dep = b.dependency("raylib", .{ .target = target, .optimize = optimize });
    // const raylib = raylib_dep.artifact("raylib");
    // raylib.root_module.addCMacro("SUPPORT_FILEFORMAT_JPG", "1");

    // zui.addImport("raylib", raylib_dep.module("raylib"));
    // zui.linkLibrary(raylib);

    const gobject = b.dependency("gobject", .{ .target = target, .optimize = optimize });
    lib.addImport("pango", gobject.module("pango1"));
    lib.addImport("cairo", gobject.module("cairo1"));
    lib.addImport("pangocairo", gobject.module("pangocairo1"));
    lib.addImport("gobject", gobject.module("gobject2"));
    lib.addImport("glib", gobject.module("glib2"));

    const test_module = b.createModule(.{
        .root_source_file = b.path("test/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("zui", lib);

    const test_exe = b.addExecutable(.{
        .name = "test_app",
        .root_module = test_module,
    });
    b.installArtifact(test_exe);

    const run = b.addRunArtifact(test_exe);
    const run_step = b.step("run", "Run test app");
    run_step.dependOn(&run.step);
}

const std = @import("std");
const zui = @import("zui");
const SdlBackend = zui.SdlBackend;
const App = zui.App;
const hash = zui.hash;

pub fn main(init: std.process.Init) !void {
    var rl = try SdlBackend.init(init.gpa, .{
        .title = "Saturn",
        .width = 800,
        .height = 600,
    });
    defer rl.deinit();
    var app = App.init(init.gpa, rl.to_backend(), .{});
    defer app.deinit();

    var img_bytes: [100 * 100 * 4]u8 = undefined;
    @memset(&img_bytes, 0xFF);
    const text_id = rl.createTexture(.{
        .w = 100,
        .h = 100,
        .rgba = &img_bytes,
    }) orelse return error.InvalidTexture;

    var volume: f32 = 10;
    var value2: f32 = 100;

    const scrollUTF: zui.Id = .id("utf8");
    const scrollBtn: zui.Id = .id("btnscroll");
    const scrollRoot: zui.Id = .id("root");
    var search = zui.TextInputState.init(init.gpa);
    defer search.deinit();

    while (!app.quit) {
        app.begin();
        defer app.end();

        app.beginScroll(scrollRoot, .{
            .base = .{
                .width = .init(.grow),
                .height = .init(.grow),
                .padding = .init(16),
                .gap = .init(16),
                .interactive = true,
                .scroll_y = true,
                .bg = .animate(app.palette.surface, .fast),
            },
        });

        defer app.endScroll(scrollRoot);

        app.image(.id("text"), text_id, .{ .width = .init(.fit), .height = .init(.fit) });

        const r = app.textInput(.id("search"), &search, .{ .placeholder = "Search..." });
        if (r.submitted) std.log.info("submetted: {s}", .{search.text()});

        if (app.button(.id("theme"), app.fmt("Theme: {s}", .{if (app.palette.is_dark) "Dark" else "Light"}), .{})) {
            std.log.debug("CLICKED", .{});
            if (app.palette.is_dark) {
                app.palette = .initLight();
            } else app.palette = .initDark();
        }

        if (app.button(.id("toggle"), app.fmt("Current text: {s}", .{search.text()}), .{})) {
            std.log.debug("{s}", .{search.text()});
        }

        if (app.button(.idId("toggle", 1), "Reset", .{})) {
            search.clear();
            std.log.debug("reset", .{});
        }

        app.text(.id("utf8text"), "UTF-8 text rendering:", .{});
        app.beginScroll(scrollUTF, .{
            .base = .{
                .clip = true,
                .padding = .init(12),
                .width = .init(.grow),
                .interactive = true,
                .scroll_y = true,
                .height = .init(.{ .fixed = 160 }),
                .bg = .animate(app.palette.surface_raised, .fast),
            },
        });
        // app.text(.id("l"), @embedFile("assets/test.txt"), .{});
        app.endScroll(scrollUTF);

        if (app.slider(.id("volume"), .{
            .value = &volume,
            .max = 100.0,
        })) {
            std.log.debug("V = {}", .{volume});
        }

        if (app.slider(.id("z"), .{ .value = &value2, .max = 100 })) {
            std.log.debug("V = {}", .{value2});
        }

        app.beginScroll(scrollBtn, .{
            .base = .{
                .clip = true,
                .padding = .init(12),
                .width = .init(.grow),
                .interactive = true,
                .scroll_y = true,
                .gap = .init(12),
                .height = .init(.{ .fixed = 160 }),
                .bg = .animate(app.palette.surface_raised, .fast),
            },
        });
        for (0..10) |i| {
            if (app.button(.idId("btn", @intCast(i)), app.fmt("Button {}", .{i}), .{})) {
                std.log.info("Button {}", .{i});
            }
        }
        app.endScroll(scrollBtn);
    }
}

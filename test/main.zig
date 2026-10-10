const std = @import("std");
const zui = @import("zui");
const Raylib = zui.RaylibBackend;
const App = zui.App;
const hash = zui.hash;
const raylib = zui.raylib;

pub fn main(init: std.process.Init) !void {
    var rl = try Raylib.init(init.gpa, .{ .title = "Saturn", .width = 800, .height = 600, .fps = 2000 });
    defer rl.deinit();
    var app = App.init(init.gpa, rl.to_backend(), .{});
    defer app.deinit();

    var img_bytes: [100 * 100 * 4]u8 = undefined;
    @memset(&img_bytes, 0xFF);
    const TextId = rl.createTexture(.{
        .w = 100,
        .h = 100,
        .rgba = &img_bytes,
    }) orelse return error.InvalidTexture;

    var volume: f32 = 10;
    var value2: f32 = 100;

    const scrollUTF: zui.Id = .id("utf8");
    const scrollBtn: zui.Id = .id("btnscroll");
    var search = zui.TextInputState.init(init.gpa);
    defer search.deinit();
    while (!app.quit) {
        app.begin();
        defer app.end();

        app.open(.id("root"), .{
            .width = .init(.grow),
            .height = .init(.grow),
            .pad = .init(16),
            .gap = .init(16),
            .bg = .init(app.palette.surface),
        });
        defer app.close();
        app.image(.id("text"), TextId, .{ .width = .init(.fit), .height = .init(.fit) });

        const r = zui.textInput(&app, .id("search"), &search, .{ .placeholder = "Search..." });
        if (r.submitted) std.log.info("submetted: {s}", .{search.text()});

        if (zui.button(&app, .id("toggle"), app.fmt("Current text: {s}", .{search.text()}))) {
            std.log.debug("CLICKED", .{});
        }

        if (zui.button(&app, .idId("toggle", 1), "Toggle")) {
            std.log.debug("CLICKED", .{});
        }

        app.text(.id("utf8text"), "UTF-8 text rendering:", .{});
        zui.beginScroll(&app, scrollUTF, .{
            .clip = true,
            .pad = .init(12),
            .width = .init(.grow),
            .interactive = true,
            .scroll_y = true,
            .height = .init(.{ .fixed = 160 }),
            .bg = .{ .value = app.palette.surface_raised },
        });
        app.text(.id("l"), @embedFile("assets/test.txt"), .{});
        zui.endScroll(&app, scrollUTF);

        if (zui.slider(&app, .id("volume"), &volume, 100.0, .grow)) {
            std.log.debug("V = {}", .{volume});
        }

        if (zui.slider(&app, .id("z"), &value2, 100.0, .grow)) {
            std.log.debug("V = {}", .{value2});
        }

        zui.beginScroll(&app, scrollBtn, .{
            .clip = true,
            .pad = .init(12),
            .width = .init(.grow),
            .interactive = true,
            .scroll_y = true,
            .gap = .init(12),
            .height = .init(.{ .fixed = 160 }),
            .bg = .{ .value = app.palette.surface_raised },
        });
        for (0..10) |i| {
            if (zui.button(&app, .idId("btn", @intCast(i)), app.fmt("Button {}", .{i}))) {
                std.log.info("Button {}", .{i});
            }
        }
        zui.endScroll(&app, scrollBtn);
    }
}

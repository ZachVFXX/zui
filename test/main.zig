const std = @import("std");
const zui = @import("zui");
const Raylib = zui.RaylibBackend;
const App = zui.App;
const hash = zui.hash;

pub fn main(init: std.process.Init) !void {
    var rl = try Raylib.init(init.gpa, .{ .title = "Saturn", .width = 800, .height = 600 });
    defer rl.deinit();

    var app = App.init(init.gpa, rl.to_backend(), .{});
    defer app.deinit();
    const id = hash("panel", 0);

    var panel_open = false;
    while (!app.quit) {
        app.begin();
        defer app.end();

        app.open(hash("root", 0), .{
            .width = .init(.grow),
            .height = .init(.grow),
            .pad = .init(16),
            .gap = .init(16),
            .bg = .init(app.palette.surface),
        });
        defer app.close();

        if (zui.button(&app, hash("toggle", 0), "Toggle")) panel_open = !panel_open;
        if (zui.button(&app, hash("toggle", 1), "Toggle")) panel_open = !panel_open;
        if (zui.button(&app, hash("toggle", 2), "Toggle")) panel_open = !panel_open;
        const r = app.response(id);
        app.open(id, .{
            .clip = true,
            .pad = .init(12.0),
            .gap = .animate(if (r.held) 12 else 6, .smooth),
            .width = .init(.grow),
            .interactive = true,
            .height = .{ .value = .{ .fixed = if (panel_open) 160 else 0 }, .motion = .smooth },
            .alpha = .{ .value = if (panel_open) 1 else 0, .motion = .smooth, .enter = 0 },
            .delta_y = .{ .value = if (r.hovered) 0 else 24, .motion = .smooth, .enter = 0 },
            .bg = .{ .value = app.palette.surface_raised },
        });
        defer app.close();
        app.text(hash("l", 0), "First line", .{});
        app.text(hash("l", 1), app.fmt("Second line {d}", .{42}), .{});
    }
}

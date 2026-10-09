const App = @import("../app.zig").App;

pub fn button(ui: *App, id: u32, label: []const u8) bool {
    const r = ui.response(id);
    const p = ui.palette;
    ui.open(id, .{
        .center = true,
        .interactive = true,
        .pad = .init(10),
        .radius = .init(0.3),
        .width = .{ .value = .{ .fixed = if (r.hovered) 144 else 120 }, .motion = .fast },
        .delta_y = .{ .value = if (r.held) 2 else 0, .motion = .fast },
        .bg = .{
            .value = if (r.held) p.primary_active else if (r.hovered) p.primary_hover else p.primary,
            .motion = .fast,
        },
    });
    defer ui.close();
    ui.text(id +% 1, label, .{});
    return r.clicked;
}

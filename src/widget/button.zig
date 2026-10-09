const App = @import("../app.zig").App;

/// Return true en press
pub fn button(ui: *App, id: u32, label: []const u8) bool {
    const r = ui.response(id);
    const p = ui.palette;
    ui.open(id, .{
        .center = true,
        .interactive = true,
        .pad = .init(10),
        .radius = .init(0.3),
        .width = .init(.{ .fixed = 120 }),
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

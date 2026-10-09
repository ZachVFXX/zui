const App = @import("../app.zig").App;
const Id = @import("../root.zig").Id;

/// Return true en press
pub fn button(ui: *App, id_val: Id, label: []const u8) bool {
    const r = ui.response(id_val);
    const p = ui.palette;
    ui.open(id_val, .{
        .center = true,
        .interactive = true,
        .pad = .init(10),
        .width = .init(.fit),
        .delta_y = .{ .value = if (r.held) 2 else 0, .motion = .fast },
        .bg = .{
            .value = if (r.held) p.primary_active else if (r.hovered) p.primary_hover else p.primary,
            .motion = .fast,
        },
    });
    defer ui.close();
    ui.text(.id("run"), label, .{});
    return r.clicked;
}

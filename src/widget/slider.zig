const std = @import("std");
const zui = @import("../root.zig");
const App = zui.App;
const Style = zui.Style;
const hash = zui.hash;

pub fn slider(
    app: *App,
    id_val: zui.Id,
    value: *f32,
    max: f32,
    width: Style.Size,
) bool {
    const id = app.resolveId(id_val);
    var changed = false;
    const r = app.response(id_val);

    // calculate new value based on mouse position
    if (r.held) {
        if (app.rectOf(id_val)) |rect| {
            if (rect.w > 0) {
                const mouse_local_x = app.mouse.x - rect.x;
                const percent = std.math.clamp(mouse_local_x / rect.w, 0.0, 1.0);
                const new_value = percent * max;

                if (value.* != new_value) {
                    value.* = new_value;
                    changed = true;
                }
            }
        }
    }

    // render background track
    app.open(id_val, .{
        .interactive = true,
        .width = .init(width),
        .height = .init(.{ .fixed = 12 }),
        .bg = .init(app.palette.surface_overlay),
        .dir = .x, // Horizontal direction so the fill grows left-to-right
    });

    const container_w = if (app.rectOf(id_val)) |rect| rect.w else 0;
    const percent = if (max > 0) std.math.clamp(value.* / max, 0.0, 1.0) else 0.0;
    const fill_w = percent * container_w;

    const fill_color = if (r.held)
        app.palette.primary_active
    else if (r.hovered)
        app.palette.primary_hover
    else
        app.palette.primary;

    // active fill Bar
    if (fill_w > 0) {
        app.open(.idId("fill", id), .{
            .width = .animate(.{ .fixed = fill_w }, .fast),
            .height = .init(.grow),
            .bg = .init(fill_color),
        });
        app.close();
    }

    app.close();

    return changed;
}

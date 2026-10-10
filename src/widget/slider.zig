const App = @import("../app.zig").App;
const ScrollInfo = @import("../app.zig").ScrollInfo;
const Id = @import("../root.zig").Id;
const Style = @import("../layout/style.zig");
const Motion = @import("../animation/animation.zig").Motion;
const Palette = @import("../palette.zig");
const Backend = @import("../backend.zig");
const std = @import("std");

pub const Config = struct {
    base: Style = .{
        .interactive = true,
        .height = .init(.{ .fixed = 12 }),
        .width = .init(.grow),
    },
    min: f32 = 0,
    value: *f32,
    max: f32,

    slide_motion: Motion = .fast,

    color_motion: Motion = .fast,
    color_track: Palette.Color = .{ .role = .surface_overlay },
    color_normal: Palette.Color = .{ .role = .primary },
    color_hover: Palette.Color = .{ .role = .primary_hover },
    color_active: Palette.Color = .{ .role = .primary_active },
};

pub fn sliderImpl(app: *App, id_val: Id, config: Config) bool {
    const id = app.resolveId(id_val);
    var changed = false;
    const r = app.response(id_val);
    var final_style = config.base;

    final_style.interactive = true;
    final_style.dir = .x; //TODO: Make it in both axys
    final_style.bg = .{
        .value = config.color_track.resolve(app.palette),
        .motion = config.color_motion,
    };
    // calculate new value based on mouse position
    if (r.held) {
        if (app.rectOf(id_val)) |rect| {
            if (rect.w > 0) {
                const mouse_local_x = app.mouse.x - rect.x;
                const percent = std.math.clamp(mouse_local_x / rect.w, 0.0, 1.0);
                const new_value = percent * config.max;

                if (config.value.* != new_value) {
                    config.value.* = new_value;
                    changed = true;
                }
            }
        }
    }

    // render background track
    app.open(id_val, final_style);

    const container_w = if (app.rectOf(id_val)) |rect| rect.w else 0;
    const percent = if (config.max > 0) std.math.clamp(config.value.* / config.max, 0.0, 1.0) else 0.0;
    const fill_w = percent * container_w;

    const fill_color = if (r.held)
        config.color_active.resolve(app.palette)
    else if (r.hovered)
        config.color_hover.resolve(app.palette)
    else
        config.color_normal.resolve(app.palette);

    // active fill Bar
    if (fill_w > 0) {
        app.open(.idId("fill", id), .{
            .width = .animate(.{ .fixed = fill_w }, config.slide_motion),
            .height = .init(.grow),
            .bg = .animate(fill_color, config.color_motion),
        });
        app.close();
    }

    app.close();

    return changed;
}

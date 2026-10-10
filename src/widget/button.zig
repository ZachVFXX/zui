const App = @import("../app.zig").App;
const Id = @import("../root.zig").Id;
const Style = @import("../layout/style.zig");
const Motion = @import("../animation/animation.zig").Motion;
const Palette = @import("../palette.zig");
const Backend = @import("../backend.zig");
const std = @import("std");
const Text = @import("text.zig");

pub const Config = struct {
    base: Style = .{
        .center = true,
        .interactive = true,
        .padding = .init(10),
    },
    text_config: Text.Config = .{},
    press_motion: Motion = .fast,
    press_delta: f32 = 2,

    color_motion: Motion = .fast,
    color_normal: Palette.Color = .{ .role = .primary },
    color_hover: Palette.Color = .{ .role = .primary_hover },
    color_active: Palette.Color = .{ .role = .primary_active },
};

/// Return true when press
pub fn buttonImpl(ui: *App, id_val: Id, label: []const u8, config: Config) bool {
    const r = ui.response(id_val);

    const current_bg = if (r.held)
        config.color_active.resolve(ui.palette)
    else if (r.hovered)
        config.color_hover.resolve(ui.palette)
    else
        config.color_normal.resolve(ui.palette);

    var final_style = config.base;
    final_style.interactive = true;

    final_style.delta_y = .animate(if (r.held) final_style.delta_y.value + config.press_delta else final_style.delta_y.value, config.press_motion);
    final_style.bg = .{
        .value = current_bg,
        .motion = config.color_motion,
    };

    ui.open(id_val, final_style);
    defer ui.close();

    ui.text(.idId("label", ui.resolveId(id_val)), label, config.text_config);
    return r.clicked;
}

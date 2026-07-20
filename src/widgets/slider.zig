const Widget = @import("../app.zig").Widget;
const Color = @import("../color.zig").Color;
const clay = @import("zclay");
const RowWidget = @import("row.zig").RowWidget;
const renderer = @import("../renderer.zig");
const rl = @import("raylib");

pub const SliderWidget = struct {
    widget: Widget = undefined,
    frame: RowWidget = .{ .sizing = .{ .w = .growMinMax(.{ .min = 0, .max = 200 }), .h = .fixed(16) } },
    value: u32,
    step: u32 = 1,
    max: u32 = 100,

    pub fn render(ptr: *anyopaque, w: Widget, _: []const Widget) void {
        const self: *SliderWidget = @ptrCast(@alignCast(ptr));
        const max_v: f32 = @max(1.0, @as(f32, @floatFromInt(self.max)));
        var display_t: f32 = @as(f32, @floatFromInt(self.value)) / max_v;
        var fill_color = w.app.palette.fromRole(.primary);
        const track_data = clay.getElementData(w.id);
        const slider_w: f32 = if (track_data.found) track_data.bounding_box.width else 0;

        if (track_data.found) {
            const ev = w.app.interactImpl(w.id, true);
            switch (ev) {
                .mouse_hovered => fill_color = w.app.palette.fromRole(.primary_hover),
                .mouse_pressed => fill_color = w.app.palette.fromRole(.primary_active),
                else => {},
            }

            if (ev == .mouse_pressed or ev == .mouse_released) {
                const mouse_x = rl.GetMousePosition().x;
                var t = (mouse_x - track_data.bounding_box.x) / slider_w;
                t = @max(0.0, @min(1.0, t));
                display_t = t;

                if (ev == .mouse_released) {
                    var new_val: f32 = t * max_v;
                    if (self.step > 1) {
                        const step_f: f32 = @floatFromInt(self.step);
                        new_val = @round(new_val / step_f) * step_f;
                    }
                    w.app.events.append(w.app.alloc, .{ .slider_changed = .{
                        .id = w.id,
                        .value = @intFromFloat(new_val),
                    } }) catch {};
                }
            }
        }

        clay.UI()(.{
            .id = w.id,
            .layout = .{
                .direction = .left_to_right,
                .sizing = self.frame.sizing,
                .padding = self.frame.padding,
            },
            .background_color = w.app.palette.fromRole(.scrollbar_track),
        })({
            clay.UI()(.{
                .layout = .{ .sizing = .{ .w = .fixed(display_t * slider_w), .h = .grow } },
                .background_color = fill_color,
            })({});
        });
    }

    pub fn changed(self: *SliderWidget) ?u32 {
        for (self.widget.app.events.items) |ev| {
            switch (ev) {
                .slider_changed => |e| if (e.id.id == self.widget.id.id) return e.value,
                else => {},
            }
        }
        return null;
    }
};

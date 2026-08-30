const Widget = @import("../app.zig").Widget;
const Color = @import("../color.zig").Color;
const clay = @import("zclay");
const RowWidget = @import("row.zig").RowWidget;
const renderer = @import("../renderer.zig");
const rl = @import("raylib");
const Event = @import("../app.zig").Event;

pub const SliderWidget = struct {
    widget: Widget = undefined,
    frame: RowWidget = .{ .sizing = .{ .w = .growMinMax(.{ .min = 0, .max = 200 }), .h = .fixed(16) } },
    value: i64,
    step: i64 = 1,
    max: i64 = 100,

    // état calculé une seule fois par frame, dans `changed()`
    last_event: Event = .none,
    drag_t: f32 = 0,

    fn computeDragT(self: *SliderWidget) f32 {
        const track_data = clay.getElementData(self.widget.id);
        const slider_w: f32 = if (track_data.found) track_data.bounding_box.width else 0;
        if (slider_w <= 0) return 0;
        const mouse_x = rl.GetMousePosition().x;
        const t = (mouse_x - track_data.bounding_box.x) / slider_w;
        return @max(0.0, @min(1.0, t));
    }

    pub fn changed(self: *SliderWidget) ?i64 {
        const ev = self.widget.app.interactImpl(self.widget.id, false);
        self.last_event = ev;

        if (ev == .pressed or ev == .released) {
            self.drag_t = self.computeDragT();
        }

        if (ev == .released) {
            const max_v: f32 = @max(1.0, @as(f32, @floatFromInt(self.max)));
            var new_val: f32 = self.drag_t * max_v;
            if (self.step > 1) {
                const step_f: f32 = @floatFromInt(self.step);
                new_val = @round(new_val / step_f) * step_f;
            }
            return @intFromFloat(new_val);
        }
        return null;
    }

    pub fn render(ptr: *anyopaque, w: Widget, _: []const Widget) void {
        const self: *SliderWidget = @ptrCast(@alignCast(ptr));
        const max_v: f32 = @max(1.0, @as(f32, @floatFromInt(self.max)));
        var display_t: f32 = @as(f32, @floatFromInt(self.value)) / max_v;
        var fill_color = w.app.palette.fromRole(.primary);

        // on réutilise ce qui a été calculé dans changed(), pas de 2e interactImpl
        switch (self.last_event) {
            .hovered => fill_color = w.app.palette.fromRole(.primary_hover),
            .pressed, .released => {
                fill_color = w.app.palette.fromRole(.primary_active);
                display_t = self.drag_t; // on affiche la position en cours de drag
            },
            .none => {},
            else => {},
        }

        const track_data = clay.getElementData(w.id);
        const slider_w: f32 = if (track_data.found) track_data.bounding_box.width else 0;

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
};

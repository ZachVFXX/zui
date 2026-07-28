const Widget = @import("../app.zig").Widget;
const clay = @import("zclay");
const RowWidget = @import("row.zig").RowWidget;

pub const ProgressBarWidget = struct {
    widget: Widget = undefined,
    frame: RowWidget = .{
        .sizing = .{
            .w = .growMinMax(.{ .min = 0, .max = 200 }),
            .h = .fixed(16),
        },
    },

    value: u32 = 0,
    max: u32 = 100,

    pub fn render(ptr: *anyopaque, w: Widget, _: []const Widget) void {
        const self: *ProgressBarWidget = @ptrCast(@alignCast(ptr));

        const data = clay.getElementData(w.id);
        const width: f32 = if (data.found) data.bounding_box.width else 0;

        const t = @min(
            1.0,
            @as(f32, @floatFromInt(self.value)) /
                @max(1.0, @as(f32, @floatFromInt(self.max))),
        );

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
                .layout = .{
                    .sizing = .{
                        .w = .fixed(width * t),
                        .h = .grow,
                    },
                },
                .background_color = w.app.palette.fromRole(.primary),
            })({});
        });
    }

    pub fn setValue(self: *ProgressBarWidget, value: u32) void {
        self.value = @min(value, self.max);
    }

    pub fn setFraction(self: *ProgressBarWidget, fraction: f32) void {
        const clamped = @max(0.0, @min(1.0, fraction));
        self.value = @intFromFloat(clamped * @as(f32, @floatFromInt(self.max)));
    }
};

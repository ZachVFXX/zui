const Widget = @import("../app.zig").Widget;
const RowWidget = @import("row.zig").RowWidget;
const Color = @import("../color.zig").Color;
const clay = @import("zclay");
const renderer = @import("../renderer.zig");
const rl = @import("raylib");

pub const ImageWidget = struct {
    frame: RowWidget = .{ .sizing = .fit },
    texture: ?*const rl.Texture2D = null,

    pub fn render(ptr: *anyopaque, w: Widget, _: []const Widget) void {
        const self: *ImageWidget = @ptrCast(@alignCast(ptr));
        const tex = self.texture orelse return;
        clay.UI()(.{
            .id = w.id,
            .image = .{ .image_data = tex },
            .aspect_ratio = .{ .aspect_ratio = self.frame.aspect_ratio },
            .layout = .{
                .direction = self.frame.direction,
                .sizing = self.frame.sizing,
                .child_gap = self.frame.gap,
                .padding = self.frame.padding,
                .child_alignment = self.frame.child_alignment,
            },
            .background_color = self.frame.color.resolve(w.app.palette),
            .corner_radius = .all(self.frame.corner_radius),
        })({});
    }
};

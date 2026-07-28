const Widget = @import("../app.zig").Widget;
const Color = @import("../color.zig").Color;
const clay = @import("zclay");
const std = @import("std");

pub const ColumnWidget = struct {
    color: Color = .{ .role = .transparent },
    gap: u16 = 8,
    padding: clay.Padding = .{},
    corner_radius: f32 = 0,
    sizing: clay.Sizing = .grow,
    child_alignment: clay.ChildAlignment = .{},

    pub fn render(ptr: *anyopaque, w: Widget, children: []const Widget) void {
        const self: *ColumnWidget = @ptrCast(@alignCast(ptr));
        clay.UI()(.{
            .id = w.id,
            .layout = .{
                .direction = .top_to_bottom,
                .sizing = self.sizing,
                .child_gap = self.gap,
                .padding = self.padding,
                .child_alignment = self.child_alignment,
            },
            .background_color = self.color.resolve(w.app.palette),
            .corner_radius = .all(self.corner_radius),
        })({
            for (children) |child| {
                const name = child.id.string_id.chars[0..@intCast(child.id.string_id.length)];
                std.debug.print("child = {s}\n", .{name});
                child.render();
            }
        });
    }
};

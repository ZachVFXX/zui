const Widget = @import("../app.zig").Widget;
const RowWidget = @import("row.zig").RowWidget;
const Color = @import("../color.zig").Color;
const clay = @import("zclay");

pub const ButtonWidget = struct {
    widget: Widget = undefined,
    frame: RowWidget = .{},
    bg_color: Color = .{ .role = .primary },
    hover_color: Color = .{ .role = .primary_hover },
    click_color: Color = .{ .role = .primary_active },

    pub fn render(ptr: *anyopaque, w: Widget, children: []const Widget) void {
        const self: *ButtonWidget = @ptrCast(@alignCast(ptr));
        var frame = self.frame;
        frame.color = self.bg_color;

        const event = w.app.interactImpl(w.id, false);

        switch (event) {
            .pressed => {
                frame.color = self.click_color;
            },
            .hovered => {
                frame.color = self.hover_color;
            },
            .released => {
                frame.color = self.hover_color;
            },
            else => {},
        }

        clay.UI()(.{
            .id = w.id,
            .layout = .{
                .direction = frame.direction,
                .sizing = frame.sizing,
                .child_gap = frame.gap,
                .padding = frame.padding,
                .child_alignment = frame.child_alignment,
            },
            .background_color = frame.color.resolve(w.app.palette),
            .corner_radius = .all(frame.corner_radius),
        })({
            for (children) |child| child.render();
        });
    }

    pub fn clicked(self: *ButtonWidget) bool {
        const event = self.widget.app.interactImpl(self.widget.id, false);
        switch (event) {
            .released => return true,
            else => {},
        }
        return false;
    }

    pub fn hovered(self: *ButtonWidget) bool {
        const event = self.widget.app.interactImpl(self.widget.id, false);
        switch (event) {
            .hovered => return true,
            else => {},
        }
        return false;
    }
};

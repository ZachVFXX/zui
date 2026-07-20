const Widget = @import("../app.zig").Widget;
const clay = @import("zclay");
const Color = @import("../color.zig").Color;
const rl = @import("raylib");
const ScrollWidget = @import("scroll.zig").ScrollWidget;
const std = @import("std");

pub const DropdownWidget = struct {
    widget: Widget = undefined,
    options: []const []const u8,
    selected: usize = 0,
    open: bool = false,

    // Style
    bg_color: Color = .{ .role = .surface },
    hover_color: Color = .{ .role = .primary_hover },
    active_color: Color = .{ .role = .primary_active },
    selected_color: Color = .{ .role = .primary },
    text_color: Color = .{ .role = .text },

    width: f32 = 200,
    item_height: f32 = 36,
    font_id: u16 = 0,
    font_size: u16 = 16,
    padding: clay.Padding = .{ .left = 12, .right = 12, .top = 0, .bottom = 0 },

    pub fn render(ptr: *anyopaque, w: Widget, _: []const Widget) void {
        const self: *DropdownWidget = @ptrCast(@alignCast(ptr));
        const app = w.app;
        const palette = app.palette;

        if (self.open and rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT)) {
            if (!clay.pointerOver(w.id)) {
                var over_any = false;
                for (0..self.options.len) |i| {
                    const item_id = clay.ElementId.IDI("__dd_item", w.id.id +% @as(u32, @intCast(i)));
                    if (clay.pointerOver(item_id)) {
                        over_any = true;
                        break;
                    }
                }
                if (!over_any) self.open = false;
            }
        }

        const trigger_id = clay.ElementId.IDI("__dd_trigger", w.id.id);
        const trigger_ev = app.interactImpl(trigger_id, false);
        if (trigger_ev == .mouse_released) self.open = !self.open;

        const trigger_bg: Color = switch (trigger_ev) {
            .mouse_pressed => self.active_color,
            .mouse_hovered => self.hover_color,
            else => self.bg_color,
        };

        clay.UI()(.{
            .id = w.id,
            .layout = .{
                .sizing = .{ .w = .fixed(self.width) },
                .direction = .top_to_bottom,
            },
        })({
            // Triggerid
            clay.UI()(.{
                .id = trigger_id,
                .layout = .{
                    .sizing = .{ .w = .grow, .h = .fixed(self.item_height) },
                    .padding = self.padding,
                    .child_alignment = .{ .x = .left, .y = .center },
                    .child_gap = 8,
                    .direction = .left_to_right,
                },
                .background_color = trigger_bg.resolve(palette),
            })({
                app.interactive_ids.put(trigger_id.id, {}) catch unreachable;
                // Selected text
                clay.text(
                    (if (self.options.len > 0) self.options[self.selected] else ""),
                    .{ .font_id = self.font_id, .font_size = self.font_size, .color = self.text_color.resolve(palette), .wrap_mode = .none },
                );
                // Spacer for arrow
                clay.UI()(.{
                    .layout = .{ .sizing = .{ .w = .grow } },
                })({});
                // arrow
                clay.text(
                    // TODO: UTF8
                    (if (self.open) "▲" else "▼"),
                    .{ .font_id = self.font_id, .font_size = self.font_size, .color = self.text_color.resolve(palette) },
                );
            });

            // Dropdown
            if (self.open) {
                clay.UI()(.{
                    .layout = .{
                        .sizing = .{ .w = .fit, .h = .fit },
                        .direction = .top_to_bottom,
                    },
                    .floating = .{
                        .offset = .{ .x = 0, .y = self.item_height },
                        .attach_to = .to_parent,
                    },
                })({
                    for (self.options, 0..) |option, i| {
                        const item_id = clay.ElementId.IDI("__dd_item", w.id.id +% @as(u32, @intCast(i)));
                        const item_ev = app.interactImpl(item_id, false);
                        app.interactive_ids.put(item_id.id, {}) catch unreachable;

                        if (item_ev == .mouse_released) {
                            self.selected = i;
                            self.open = false;
                        }

                        const item_bg: Color = switch (item_ev) {
                            .mouse_pressed => self.active_color,
                            .mouse_hovered => self.hover_color,
                            else => if (i == self.selected) self.selected_color else self.bg_color,
                        };

                        clay.UI()(.{
                            .id = item_id,
                            .layout = .{
                                .sizing = .{ .w = .grow, .h = .fixed(self.item_height) },
                                .padding = self.padding,
                                .child_alignment = .{ .y = .center },
                            },
                            .background_color = item_bg.resolve(palette),
                        })({
                            clay.text(
                                option,
                                .{ .font_id = self.font_id, .font_size = self.font_size, .color = self.text_color.resolve(palette), .wrap_mode = .none },
                            );
                        });
                    }
                });
            }
        });
    }

    pub fn value(self: *const DropdownWidget) []const u8 {
        if (self.options.len == 0) return "";
        return self.options[self.selected];
    }

    pub fn value_eq(self: *const DropdownWidget, str: []const u8) bool {
        return std.mem.eql(u8, self.value(), str);
    }
};

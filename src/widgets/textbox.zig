const std = @import("std");
const Widget = @import("../app.zig").Widget;
const RowWidget = @import("row.zig").RowWidget;
const Color = @import("../color.zig").Color;
const clay = @import("zclay");
const renderer = @import("../renderer.zig");
const rl = @import("raylib");
const FontRenderer = @import("../font_renderer.zig").FontRenderer;

pub const TextBoxWidget = struct {
    widget: Widget = undefined,
    frame: RowWidget = .{
        .gap = 0,
        .sizing = .{ .w = .fixed(200), .h = .fixed(32) },
        .padding = .{ .top = 6, .bottom = 6, .left = 8, .right = 8 },
    },
    font_id: u16 = 0,
    font_size: u16 = 16,
    color: Color = .{ .role = .text },
    buf: *std.ArrayListUnmanaged(u8),
    alloc: std.mem.Allocator,
    focused: bool = false,
    cursor: usize = 0,
    sel_anchor: ?usize = null, // null = no selection

    fn prevBoundary(buf: []const u8, pos: usize) usize {
        if (pos == 0) return 0;
        var i = pos - 1;
        while (i > 0 and buf[i] & 0xC0 == 0x80) i -= 1;
        return i;
    }

    fn nextBoundary(buf: []const u8, pos: usize) usize {
        if (pos >= buf.len) return buf.len;
        var i = pos + 1;
        while (i < buf.len and buf[i] & 0xC0 == 0x80) i += 1;
        return i;
    }

    fn selStart(self: *TextBoxWidget) usize {
        return if (self.sel_anchor) |a| @min(a, self.cursor) else self.cursor;
    }

    fn selEnd(self: *TextBoxWidget) usize {
        return if (self.sel_anchor) |a| @max(a, self.cursor) else self.cursor;
    }

    fn hasSelection(self: *TextBoxWidget) bool {
        return self.sel_anchor != null and self.sel_anchor.? != self.cursor;
    }

    fn clearSelection(self: *TextBoxWidget) void {
        self.sel_anchor = null;
    }

    fn deleteSelection(self: *TextBoxWidget) void {
        if (!self.hasSelection()) return;
        const s = self.selStart();
        const e = self.selEnd();
        self.buf.replaceRange(self.alloc, s, e - s, &.{}) catch {};
        self.cursor = s;
        self.sel_anchor = null;
    }

    fn cursorFromMouseX(self: *TextBoxWidget, mouse_x: f32, box_x: f32) usize {
        const text = self.buf.items;
        if (text.len == 0) return 0;

        const rel = mouse_x - box_x - @as(f32, @floatFromInt(self.frame.padding.left));

        var best_pos: usize = 0;
        var best_dist: f32 = std.math.floatMax(f32);

        // Measure each UTF-8 boundary prefix using a null-terminated stack buf
        var tmp: [1024:0]u8 = undefined;
        var i: usize = 0;
        while (i <= text.len) {
            // skip non-boundary bytes
            if (i > 0 and i < text.len and text[i] & 0xC0 == 0x80) {
                i += 1;
                continue;
            }
            const copy_len = @min(i, tmp.len - 1);
            @memcpy(tmp[0..copy_len], text[0..copy_len]);
            tmp[copy_len] = 0;
            var config: clay.TextElementConfig = .{ .font_id = self.font_id, .font_size = self.font_size };
            const w = FontRenderer.measureText(&tmp, &config, &self.widget.app.font_renderer).w;
            const dist = @abs(w - rel);
            if (dist < best_dist) {
                best_dist = dist;
                best_pos = i;
            }
            i += 1;
        }
        return best_pos;
    }

    fn handleInput(self: *TextBoxWidget) void {
        const ctrl = rl.IsKeyDown(rl.KEY_LEFT_CONTROL) or rl.IsKeyDown(rl.KEY_RIGHT_CONTROL);
        const shift = rl.IsKeyDown(rl.KEY_LEFT_SHIFT) or rl.IsKeyDown(rl.KEY_RIGHT_SHIFT);
        const text = self.buf.items;

        // Ctrl+A
        if (ctrl and rl.IsKeyPressed(rl.KEY_Q)) {
            self.sel_anchor = 0;
            self.cursor = text.len;
            return;
        }

        // Ctrl+C
        if (ctrl and rl.IsKeyPressed(rl.KEY_C) and self.hasSelection()) {
            const s = self.selStart();
            const e = self.selEnd();
            const tmp = self.alloc.dupeZ(u8, text[s..e]) catch return;
            defer self.alloc.free(tmp);
            rl.SetClipboardText(tmp.ptr);
            return;
        }

        // Ctrl+X
        if (ctrl and rl.IsKeyPressed(rl.KEY_X) and self.hasSelection()) {
            const s = self.selStart();
            const e = self.selEnd();
            const tmp = self.alloc.dupeZ(u8, text[s..e]) catch return;
            defer self.alloc.free(tmp);
            rl.SetClipboardText(tmp.ptr);
            self.deleteSelection();
            return;
        }

        // Ctrl+V
        if (ctrl and rl.IsKeyPressed(rl.KEY_V)) {
            const clipboard = rl.GetClipboardText();
            if (clipboard != null) {
                if (self.hasSelection()) self.deleteSelection();
                const s = std.mem.sliceTo(clipboard, 0);
                self.buf.insertSlice(self.alloc, self.cursor, s) catch return;
                self.cursor += s.len;
            }
            return;
        }

        const nav_keys = [_]i32{ rl.KEY_LEFT, rl.KEY_RIGHT, rl.KEY_HOME, rl.KEY_END };
        for (nav_keys) |k| {
            if (!rl.IsKeyPressed(k) and !rl.IsKeyPressedRepeat(k)) continue;
            switch (k) {
                rl.KEY_LEFT => {
                    if (shift) {
                        if (self.sel_anchor == null) self.sel_anchor = self.cursor;
                        self.cursor = prevBoundary(text, self.cursor);
                    } else {
                        if (self.hasSelection()) {
                            self.cursor = self.selStart();
                        } else {
                            self.cursor = prevBoundary(text, self.cursor);
                        }
                        self.clearSelection();
                    }
                },
                rl.KEY_RIGHT => {
                    if (shift) {
                        if (self.sel_anchor == null) self.sel_anchor = self.cursor;
                        self.cursor = nextBoundary(text, self.cursor);
                    } else {
                        if (self.hasSelection()) {
                            self.cursor = self.selEnd();
                        } else {
                            self.cursor = nextBoundary(text, self.cursor);
                        }
                        self.clearSelection();
                    }
                },
                rl.KEY_HOME => {
                    if (shift and self.sel_anchor == null) self.sel_anchor = self.cursor;
                    if (!shift) self.clearSelection();
                    self.cursor = 0;
                },
                rl.KEY_END => {
                    if (shift and self.sel_anchor == null) self.sel_anchor = self.cursor;
                    if (!shift) self.clearSelection();
                    self.cursor = text.len;
                },
                else => {},
            }
        }

        const del_keys = [_]i32{ rl.KEY_BACKSPACE, rl.KEY_DELETE };
        for (del_keys) |k| {
            if (!rl.IsKeyPressed(k) and !rl.IsKeyPressedRepeat(k)) continue;
            if (self.hasSelection()) {
                self.deleteSelection();
            } else if (k == rl.KEY_BACKSPACE and self.cursor > 0) {
                const prev = prevBoundary(text, self.cursor);
                self.buf.replaceRange(self.alloc, prev, self.cursor - prev, &.{}) catch {};
                self.cursor = prev;
            } else if (k == rl.KEY_DELETE and self.cursor < text.len) {
                const next = nextBoundary(text, self.cursor);
                self.buf.replaceRange(self.alloc, self.cursor, next - self.cursor, &.{}) catch {};
            }
        }

        var char = rl.GetCharPressed();
        while (char != 0) : (char = rl.GetCharPressed()) {
            if (self.hasSelection()) self.deleteSelection();
            var seq: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(@intCast(char), &seq) catch continue;
            self.buf.insertSlice(self.alloc, self.cursor, seq[0..len]) catch {};
            self.cursor += len;
        }
    }

    pub fn render(ptr: *anyopaque, w: Widget, _: []const Widget) void {
        const self: *TextBoxWidget = @ptrCast(@alignCast(ptr));

        const ev = w.app.interactImpl(w.id, false);

        if (ev == .mouse_released) {
            const data = clay.getElementData(w.id);
            if (data.found) {
                self.cursor = self.cursorFromMouseX(
                    rl.GetMousePosition().x,
                    data.bounding_box.x,
                );
            }
            self.clearSelection();
            self.focused = true;
        }

        if (rl.IsMouseButtonReleased(rl.MOUSE_LEFT_BUTTON) and ev != .mouse_released) {
            self.focused = false;
        }

        if (self.focused) self.handleInput();

        self.cursor = @min(self.cursor, self.buf.items.len);

        const border_color = if (self.focused)
            w.app.palette.fromRole(.primary)
        else
            w.app.palette.fromRole(.surface_overlay);

        var frame = self.frame;
        frame.color = .{ .rgba = w.app.palette.fromRole(.surface_raised) };

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
            .border = .{ .color = border_color, .width = .outside(2) },
        })({
            const text = self.buf.items;
            const blink = self.focused and (@as(u64, @intFromFloat(rl.GetTime() * 2)) % 2) == 0;

            if (text.len == 0) {
                if (self.focused) {
                    if (blink) clay.text("|", .{ .font_id = self.font_id, .font_size = self.font_size, .color = w.app.palette.fromRole(.primary), .wrap_mode = .none });
                } else {
                    clay.text("Type here...", .{ .font_id = self.font_id, .font_size = self.font_size, .color = w.app.palette.fromRole(.text_disabled), .wrap_mode = .none });
                }
            } else if (self.focused and self.hasSelection()) {
                const s = self.selStart();
                const e = self.selEnd();
                // before selection
                if (s > 0) clay.text(text[0..s], .{ .font_id = self.font_id, .font_size = self.font_size, .color = self.color.resolve(w.app.palette), .wrap_mode = .none });
                // selected text (highlighted color)
                clay.text(text[s..e], .{ .font_id = self.font_id, .font_size = self.font_size, .color = w.app.palette.fromRole(.primary_active), .wrap_mode = .none });
                // after selection
                if (e < text.len) clay.text(text[e..], .{ .font_id = self.font_id, .font_size = self.font_size, .color = self.color.resolve(w.app.palette), .wrap_mode = .none });
            } else if (self.focused) {
                // before cursor
                if (self.cursor > 0) clay.text(text[0..self.cursor], .{ .font_id = self.font_id, .font_size = self.font_size, .color = self.color.resolve(w.app.palette), .wrap_mode = .none });
                // blinking cursor
                if (blink) clay.text("|", .{ .font_id = self.font_id, .font_size = self.font_size, .color = w.app.palette.fromRole(.primary), .wrap_mode = .none });
                // after cursor
                if (self.cursor < text.len) clay.text(text[self.cursor..], .{ .font_id = self.font_id, .font_size = self.font_size, .color = self.color.resolve(w.app.palette), .wrap_mode = .none });
            } else {
                clay.text(text, .{ .font_id = self.font_id, .font_size = self.font_size, .color = self.color.resolve(w.app.palette), .wrap_mode = .none });
            }
        });
    }

    pub fn getText(self: *TextBoxWidget) []const u8 {
        return self.buf.items;
    }
    pub fn clear(self: *TextBoxWidget) void {
        self.buf.clearRetainingCapacity();
        self.cursor = 0;
        self.sel_anchor = null;
    }
    pub fn isFocused(self: *TextBoxWidget) bool {
        return self.focused;
    }
};

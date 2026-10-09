const std = @import("std");
const zui = @import("../root.zig");
const App = zui.App;
const Style = zui.Style;
const Backend = zui.Backend;
const hash = zui.hash;

const wheel_speed: f32 = 28.0;

pub fn beginScroll(app: *App, id_val: zui.Id, style: Style) void {
    const id = app.resolveId(id_val);
    var s = style;
    s.clip = true;
    s.interactive = true;

    const entry = app.scroll_offsets.getOrPut(id) catch @panic("OOM");
    if (!entry.found_existing) entry.value_ptr.* = .{ .x = 0, .y = 0 };
    const off = entry.value_ptr;

    // Last frame info
    const info = app.scroll_info.get(id) orelse zui.ScrollInfo{};

    if (s.scroll_y and info.contains(app.mouse)) off.y -= app.scroll_delta.y * wheel_speed;

    const thumb = app.response(.idId("thumb", id));
    if (thumb.held and info.rect.h > 0)
        off.y += app.mouse_delta.y * (info.content_h / info.rect.h);

    off.y = std.math.clamp(off.y, 0, info.maxY());
    s.scroll_offset = off.*;

    app.open(id_val, s);
}

pub fn endScroll(app: *App, id_val: zui.Id) void {
    const id = app.resolveId(id_val);
    const info = app.scroll_info.get(id) orelse zui.ScrollInfo{};
    const off = app.scroll_offsets.get(id) orelse Backend.Vec2{ .x = 0, .y = 0 };

    if (info.rect.h > 0 and info.content_h > info.rect.h) {
        const vh = info.rect.h;
        const thumb_h = @max(20.0, vh * vh / info.content_h);
        const t = off.y / info.maxY();
        const thumb_id: zui.Id = .idId("thumb", id);
        const r = app.response(thumb_id);

        app.open(thumb_id, .{
            .interactive = true,
            .floating = true,
            .width = .{ .value = .{ .fixed = 6 } },
            .height = .{ .value = .{ .fixed = thumb_h } },
            .delta_x = .{ .value = info.rect.w - 10 },
            .delta_y = .{ .value = (vh - thumb_h) * t },
            .bg = .{
                .value = if (r.held or r.hovered) app.palette.scrollbar_hover else app.palette.scrollbar_thumb,
                .motion = .fast,
            },
        });
        app.close();
    }
    app.close();
}

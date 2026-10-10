const App = @import("../app.zig").App;
const ScrollInfo = @import("../app.zig").ScrollInfo;
const Id = @import("../root.zig").Id;
const Style = @import("../layout/style.zig");
const Motion = @import("../animation/animation.zig").Motion;
const Palette = @import("../palette.zig");
const Backend = @import("../backend.zig");
const std = @import("std");

pub const Config = struct {
    base: Style = .{
        .clip = true,
        .padding = .init(12),
        .width = .init(.grow),
        .interactive = true,
        .scroll_y = true,
        .height = .init(.{ .fixed = 160 }),
    },
    wheel_speed: f32 = 28.0,
};

pub fn beginScrollImpl(app: *App, id_val: Id, config: Config) void {
    const id = app.resolveId(id_val);

    var final_style = config.base;

    final_style.clip = true;
    final_style.interactive = true;

    const entry = app.scroll_offsets.getOrPut(id) catch @panic("OOM");
    if (!entry.found_existing) entry.value_ptr.* = Backend.Vec2{};
    const off = entry.value_ptr;

    const info = app.scroll_info.get(id) orelse ScrollInfo{};

    if (final_style.scroll_y and info.contains(app.mouse)) off.y -= app.scroll_delta.y * config.wheel_speed;

    const thumb = app.response(.idId("thumb", id));
    if (thumb.held and info.rect.h > 0)
        off.y += app.mouse_delta.y * (info.content_h / info.rect.h);

    off.y = std.math.clamp(off.y, 0, info.maxY());
    final_style.scroll_offset = off.*;

    app.open(id_val, final_style);
}

pub fn endScrollImpl(app: *App, id_val: Id) void {
    const id = app.resolveId(id_val);
    const info = app.scroll_info.get(id) orelse ScrollInfo{};
    const off = app.scroll_offsets.get(id) orelse Backend.Vec2{};

    if (info.rect.h > 0 and info.content_h > info.rect.h) {
        const vh = info.rect.h;
        const thumb_h = @max(20.0, vh * vh / info.content_h);
        const t = off.y / info.maxY();
        const thumb_id: Id = .idId("thumb", id);
        const r = app.response(thumb_id);

        app.open(thumb_id, .{
            .interactive = true,
            .floating = true,
            .width = .init(.{ .fixed = 6 }),
            .height = .init(.{ .fixed = thumb_h }),
            .delta_x = .init(info.rect.w - 10),
            .delta_y = .init((vh - thumb_h) * t),
            .bg = .init(if (r.held or r.hovered) app.palette.scrollbar_hover else app.palette.scrollbar_thumb),
        });
        app.close();
    }
    app.close();
}

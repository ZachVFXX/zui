const std = @import("std");
const zui = @import("../root.zig");
const App = zui.App;
const Id = zui.Id;
const Style = zui.Style;
const Backend = zui.Backend;

pub const TextInputState = struct {
    alloc: std.mem.Allocator,
    buf: std.ArrayList(u8) = .empty,
    /// Byte index always on a character boundary
    cursor: usize = 0,
    scroll_x: f32 = 0,
    last_edit: f64 = 0,

    pub fn init(alloc: std.mem.Allocator) TextInputState {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *TextInputState) void {
        self.buf.deinit(self.alloc);
    }

    /// Valid until the next edit
    pub fn text(self: *const TextInputState) []const u8 {
        return self.buf.items;
    }

    pub fn setText(self: *TextInputState, s: []const u8) void {
        self.buf.clearRetainingCapacity();
        self.buf.appendSlice(self.alloc, s) catch {};
        self.cursor = self.buf.items.len;
    }

    pub fn clear(self: *TextInputState) void {
        self.buf.clearRetainingCapacity();
        self.cursor = 0;
        self.scroll_x = 0;
    }
};

pub const Config = struct {
    placeholder: []const u8 = "",
    width: Style.Size = .grow,
    height: f32 = 34,
    font_size: u32 = 16,
    font_id: Backend.FontId = 0,
};

pub const Result = struct {
    changed: bool = false,
    submitted: bool = false,
};

const padding: f32 = 8;

fn prevBoundary(s: []const u8, i: usize) usize {
    var k = i;
    if (k == 0) return 0;
    k -= 1;
    while (k > 0 and (s[k] & 0xC0) == 0x80) k -= 1; // skip continuation bytes
    return k;
}

fn nextBoundary(s: []const u8, i: usize) usize {
    if (i >= s.len) return s.len;
    const n = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
    return @min(s.len, i + n);
}

fn width(app: *App, s: []const u8, config: Config) f32 {
    if (s.len == 0) return 0;
    return app.backend.measureText(s, config.font_id, config.font_size, null).x;
}

/// Byte index whose left edge is closest to `x` (x relative to the start of the text).
fn indexAt(app: *App, s: []const u8, config: Config, x: f32) usize {
    var best: usize = 0;
    var best_d: f32 = @abs(x);
    var i: usize = 0;
    while (i < s.len) {
        i = nextBoundary(s, i);
        const d = @abs(width(app, s[0..i], config) - x);
        if (d < best_d) {
            best_d = d;
            best = i;
        }
    }
    return best;
}

fn child(id: Id, name: []const u8) Id {
    return .{ .hash = zui.hash(name, id.hash) };
}

fn insertCodepoint(st: *TextInputState, cp: u21) bool {
    var tmp: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &tmp) catch return false;
    st.buf.insertSlice(st.alloc, st.cursor, tmp[0..n]) catch return false;
    st.cursor += n;
    return true;
}

fn removeRange(st: *TextInputState, start: usize, end: usize) void {
    st.buf.replaceRange(st.alloc, start, end - start, &[_]u8{}) catch {};
}

fn handleInput(app: *App, st: *TextInputState, res: *Result) void {
    for (app.events.items) |ev| switch (ev) {
        .text => |cp| {
            if (cp >= 32 and cp != 127 and insertCodepoint(st, cp)) res.changed = true;
        },
        .key => |k| {
            if (!k.down) continue;
            switch (k.code) {
                .backspace => if (st.cursor > 0) {
                    const p = prevBoundary(st.buf.items, st.cursor);
                    removeRange(st, p, st.cursor);
                    st.cursor = p;
                    res.changed = true;
                },
                .delete => if (st.cursor < st.buf.items.len) {
                    removeRange(st, st.cursor, nextBoundary(st.buf.items, st.cursor));
                    res.changed = true;
                },
                .left => st.cursor = prevBoundary(st.buf.items, st.cursor),
                .right => st.cursor = nextBoundary(st.buf.items, st.cursor),
                .home => st.cursor = 0,
                .end => st.cursor = st.buf.items.len,
                .enter, .kp_enter => res.submitted = true,
                .escape => app.focus = 0,
                else => continue,
            }
            st.last_edit = app.last_time; // restart the blink so the caret is visible
        },
        else => {},
    };
    st.cursor = @min(st.cursor, st.buf.items.len);
}

pub fn textInputImpl(app: *App, id: Id, st: *TextInputState, config: Config) Result {
    var res: Result = .{};
    const r = app.response(id);
    const focused = app.focus == id.hash;
    const rect = app.rectOf(id) orelse Backend.BoundingBox{ .x = 0, .y = 0, .w = 0, .h = 0 };

    if (focused) {
        app.wants_text = true;
        handleInput(app, st, &res);
    }

    // place the cursor under the mouse
    if (app.pressed and r.hovered) {
        const local_x = app.mouse.x - rect.x - padding + st.scroll_x;
        st.cursor = indexAt(app, st.buf.items, config, local_x);
        st.last_edit = app.last_time;
    }

    // keep the cursor visible inside the box
    const cursor_x = width(app, st.buf.items[0..st.cursor], config);
    const inner_w = @max(0, rect.w - 2 * padding);
    if (rect.w > 0) {
        if (width(app, st.buf.items, config) <= inner_w) {
            st.scroll_x = 0;
        } else {
            if (cursor_x - st.scroll_x > inner_w) st.scroll_x = cursor_x - inner_w;
            if (cursor_x < st.scroll_x) st.scroll_x = cursor_x;
        }
    }

    app.open(id, .{
        .dir = .x,
        .center = true, // vertical centering
        .clip = true,
        .interactive = true,
        .width = .init(config.width),
        .height = .init(.{ .fixed = config.height }),
        .padding = .init(padding),
        .bg = .animate(if (focused) app.palette.surface_overlay else app.palette.surface_raised, .fast),
        .scroll_offset = .{ .x = st.scroll_x, .y = 0 },
    });
    defer app.close();

    if (st.buf.items.len > 0) {
        app.text(child(id, "text"), st.buf.items, .{ .font_size = config.font_size, .font_id = config.font_id });
    } else if (config.placeholder.len > 0) {
        app.text(child(id, "hint"), config.placeholder, .{
            .font_size = config.font_size,
            .font_id = config.font_id,
            .font_color = .init(.{ .role = .text_dim }),
        });
    }

    // blinking caret
    const blink = @mod(app.last_time - st.last_edit, 1.0) < 0.6;
    if (focused and blink) {
        const caret_h = @as(f32, @floatFromInt(config.font_size)) * 1.2;
        app.open(child(id, "caret"), .{
            .floating = true,
            .width = .init(.{ .fixed = 1.5 }),
            .height = .init(.{ .fixed = caret_h }),
            .delta_x = .init(padding + cursor_x - st.scroll_x),
            .delta_y = .init((config.height - caret_h) / 2),
            .bg = .init(app.palette.text),
        });
        app.close();
    }

    return res;
}

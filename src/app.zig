const std = @import("std");
const Backend = @import("backend.zig");
const Style = @import("layout/style.zig");
const Node = @import("layout/node.zig");
const layout = @import("layout/layout.zig");
const emit = @import("layout/emit.zig");
const Animator = @import("animation/animator.zig").Animator;

const Palette = @import("palette.zig");
const Motion = Style.Motion;
const Axis = Style.Axis;
const Size = Style.Size;
const Prop = Style.Prop;

const none = Node.none;

pub const Response = struct { hovered: bool = false, held: bool = false, clicked: bool = false };

pub fn hash(s: []const u8, i: u32) u32 {
    return @truncate(std.hash.Wyhash.hash(i, s));
}

pub const App = struct {
    alloc: std.mem.Allocator,
    backend: Backend,

    nodes: std.ArrayList(Node) = .empty,
    stack: std.ArrayList(u32) = .empty,
    cmds: std.ArrayList(Backend.DrawCmd) = .empty,
    events: std.ArrayList(Backend.InputEvent) = .empty,

    /// Formatted strings live here until the frame is rendered
    arena: std.heap.ArenaAllocator,

    // input state
    mouse: Backend.Vec2 = .{ .x = 0, .y = 0 },
    pressed: bool = false,
    released: bool = false,
    down: bool = false,

    // Mouse wheel delta for the current frame
    scroll_delta: Backend.Vec2 = .{ .x = 0, .y = 0 },
    // Map container node IDs to their current scroll positions
    scroll_offsets: std.AutoHashMap(u32, Backend.Vec2),

    /// topmost interactive node under the mouse from last frame
    hot: u32 = 0,
    /// node that received the press
    active: u32 = 0,

    // time and animation
    delta_time: f32 = 0,
    last_time: f64 = 0,
    animator: Animator(Style) = .{},

    /// True if anything has not settled yet, valid after `end()`
    animating: bool = false,

    // window
    window_size: Backend.Vec2,
    resized: bool = false,

    palette: Palette = .{},
    quit: bool = false,

    pub fn init(alloc: std.mem.Allocator, backend: Backend, palette: Palette) App {
        return .{
            .alloc = alloc,
            .backend = backend,
            .arena = .init(alloc),
            .scroll_offsets = .init(alloc),
            .window_size = backend.size(),
            .palette = palette,
        };
    }

    pub fn deinit(self: *App) void {
        self.scroll_offsets.deinit(); // TODO: deinit key value
        self.nodes.deinit(self.alloc);
        self.stack.deinit(self.alloc);
        self.cmds.deinit(self.alloc);
        self.events.deinit(self.alloc);
        self.animator.deinit(self.alloc);
        self.arena.deinit();
    }

    pub fn begin(self: *App) void {
        _ = self.arena.reset(.retain_capacity);
        self.nodes.clearRetainingCapacity();
        self.stack.clearRetainingCapacity();
        self.cmds.clearRetainingCapacity();
        self.events.clearRetainingCapacity();
        self.pressed = false;
        self.released = false;
        self.resized = false;
        self.animator.beginFrame(self.alloc);

        const t = self.backend.now();
        self.delta_time = @floatCast(@min(t - self.last_time, 0.1));
        self.last_time = t;
        self.scroll_delta = .{ .x = 0, .y = 0 };

        self.backend.pollEvents(self.alloc, &self.events);
        for (self.events.items) |ev| switch (ev) {
            .mouse_move => |p| self.mouse = p,
            .mouse_button => |m| if (m.button == .left) {
                if (m.down) {
                    self.pressed = true;
                    self.down = true;
                } else {
                    self.released = true;
                    self.down = false;
                }
            },
            .resize => |size| {
                self.window_size = .{ .x = size.x, .y = size.y };
                self.resized = true;
            },
            .wheel => |wheel| {
                self.scroll_delta.x += wheel.x;
                self.scroll_delta.y += wheel.y;
            },
            .quit => self.quit = true,
            else => {},
        };
    }

    pub fn end(self: *App) void {
        if (self.nodes.items.len > 0) {
            layout.run(self.nodes.items, self.window_size);
            self.hitTest();
            emit.run(self.nodes.items, self.backend, self.alloc, &self.cmds);
        }
        self.animating = self.animator.any_running;
        if (self.released) self.active = 0;
        self.backend.render(self.cmds.items);
    }

    /// Uses last frame hit-test so its valid before you open the node.
    pub fn response(self: *App, id: u32) Response {
        const hovered = self.hot == id;
        if (hovered and self.pressed) self.active = id;
        return .{
            .hovered = hovered,
            .held = self.active == id and self.down,
            .clicked = self.released and self.active == id and hovered,
        };
    }

    /// Final rectangle of a node, Valid after `end()` until the next `begin()`.
    pub fn rectOf(self: *App, id: u32) ?Backend.BoundingBox {
        for (self.nodes.items) |n| if (n.id == id) return n.rect;
        return null;
    }

    fn hitTest(self: *App) void {
        self.hot = 0;
        const n = self.nodes.items;
        var i: usize = n.len;
        while (i > 0) {
            i -= 1;
            const r = n[i].rect;
            if (n[i].style.interactive and
                self.mouse.x >= r.x and self.mouse.x < r.x + r.w and
                self.mouse.y >= r.y and self.mouse.y < r.y + r.h)
            {
                self.hot = n[i].id;
                break;
            }
        }
    }

    pub fn open(self: *App, id: u32, style: Style) void {
        const idx: u32 = @intCast(self.nodes.items.len);
        const resolved = self.animator.resolve(self.alloc, id, style, self.delta_time, self.resized);
        self.link(.{ .id = id, .style = resolved, .end = idx + 1 });
        self.stack.append(self.alloc, idx) catch @panic("OOM");
    }

    pub fn close(self: *App) void {
        const idx = self.stack.pop().?;
        self.nodes.items[idx].end = @intCast(self.nodes.items.len);
    }

    pub fn text(
        self: *App,
        id: u32,
        str: []const u8,
        config: struct {
            font_size: u32 = 12,
            font_id: Backend.FontId = 0,
            font_color: Palette.Color = .{ .role = .text },
        },
    ) void {
        const resolved_color = config.font_color.resolve(self.palette);
        var n = Node{
            .id = id,
            .style = .{},
            .text = str,
            .font_id = config.font_id,
            .font_size = config.font_size,
            .color = resolved_color,
        };
        n.size = self.backend.measureText(str, config.font_id, config.font_size, null);
        n.end = @intCast(self.nodes.items.len + 1);
        self.link(n);
    }

    pub fn image(self: *App, id: u32, tex: Backend.TextureId, style: Style) void {
        const resolved = self.animator.resolve(self.alloc, id, style, self.delta_time, self.resized);
        var n = Node{ .id = id, .style = resolved, .tex = tex };

        n.size = self.backend.textureSize(tex);

        n.end = @intCast(self.nodes.items.len + 1);
        self.link(n);
    }

    /// Store the result string for one frame in the arena
    pub fn fmt(self: *App, comptime f: []const u8, args: anytype) []const u8 {
        return std.fmt.allocPrint(self.arena.allocator(), f, args) catch "?";
    }

    pub fn beginScroll(self: *App, id: u32, style: Style) void {
        var s = style;
        s.clip = true;
        s.interactive = true; // detect mouse hovering

        // get scroll offset for this container ID
        const entry = self.scroll_offsets.getOrPut(id) catch @panic("OOM");
        if (!entry.found_existing) {
            entry.value_ptr.* = .{ .x = 0, .y = 0 };
        }

        // if hovered apply mouse wheel scroll
        if (self.hot == id) {
            const scroll_speed: f32 = 24.0;
            if (s.scroll_y) {
                entry.value_ptr.y -= self.scroll_delta.y * scroll_speed;
            }
            if (s.scroll_x) {
                entry.value_ptr.x -= self.scroll_delta.x * scroll_speed;
            }
        }

        // Clamp scroll to >= 0
        entry.value_ptr.x = @max(0.0, entry.value_ptr.x);
        entry.value_ptr.y = @max(0.0, entry.value_ptr.y);
        s.scroll_offset = entry.value_ptr.*;
        self.open(id, s);
    }

    pub fn endScroll(self: *App) void {
        self.close();
    }

    fn link(self: *App, node: Node) void {
        const idx: u32 = @intCast(self.nodes.items.len);
        var n = node;
        n.parent = if (self.stack.items.len > 0) self.stack.getLast() else none;
        self.nodes.append(self.alloc, n) catch @panic("OOM");
        if (n.parent != none) {
            const p = &self.nodes.items[n.parent];
            if (p.last == none) p.first = idx else self.nodes.items[p.last].next = idx;
            p.last = idx;
        }
    }
};

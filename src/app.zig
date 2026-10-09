const std = @import("std");
const Backend = @import("backend.zig");
const Style = @import("layout/style.zig");
const Node = @import("layout/node.zig");
const layout = @import("layout/layout.zig");
const emit = @import("layout/emit.zig");
const Animator = @import("animation/animator.zig").Animator;
const Id = @import("root.zig").Id;

const Palette = @import("palette.zig");
const Motion = Style.Motion;
const Axis = Style.Axis;
const Size = Style.Size;
const Prop = Style.Prop;
const none = Node.none;

pub const Response = struct { hovered: bool = false, held: bool = false, clicked: bool = false };

pub const ScrollInfo = struct {
    rect: Backend.BoundingBox = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    content_w: f32 = 0,
    content_h: f32 = 0,

    pub fn contains(self: ScrollInfo, p: Backend.Vec2) bool {
        return p.x >= self.rect.x and p.x < self.rect.x + self.rect.w and
            p.y >= self.rect.y and p.y < self.rect.y + self.rect.h;
    }
    pub fn maxY(self: ScrollInfo) f32 {
        return @max(0, self.content_h - self.rect.h);
    }
};

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
    mouse_delta: Backend.Vec2 = .{ .x = 0, .y = 0 },
    pressed: bool = false,
    released: bool = false,
    down: bool = false,

    // Mouse wheel delta for the current frame
    scroll_delta: Backend.Vec2 = .{ .x = 0, .y = 0 },
    // Map container node IDs to their current scroll state
    scroll_offsets: std.AutoHashMap(u32, Backend.Vec2),
    scroll_info: std.AutoHashMap(u32, ScrollInfo),

    prev_rects: std.AutoHashMap(u32, Backend.BoundingBox),

    id_stack: std.ArrayList(u32) = .empty,

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
            .scroll_info = .init(alloc),
            .window_size = backend.size(),
            .prev_rects = .init(alloc),
            .palette = palette,
        };
    }

    pub fn deinit(self: *App) void {
        self.prev_rects.deinit();
        self.scroll_offsets.deinit();
        self.scroll_info.deinit(); // TODO: deinit key value
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
        self.mouse_delta = .{ .x = 0, .y = 0 };

        self.backend.pollEvents(self.alloc, &self.events);
        for (self.events.items) |ev| switch (ev) {
            .mouse_move => |p| {
                self.mouse_delta = .{ .x = p.x - self.mouse.x, .y = p.y - self.mouse.y };
                self.mouse = p;
            },
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

    pub fn resolveId(_: *App, id_val: Id) u32 {
        return id_val.hash;
    }

    fn measureScrolls(self: *App) void {
        const n = self.nodes.items;
        for (n) |nd| {
            if (!nd.style.scroll_x and !nd.style.scroll_y) continue;
            var cw: f32 = 0;
            var ch: f32 = 0;
            var c = nd.first;
            while (c != none) : (c = n[c].next) {
                const k = n[c];
                if (k.style.floating) continue;
                ch = @max(ch, k.rect.y + nd.style.scroll_offset.y + k.rect.h - nd.rect.y + nd.style.pad.value);
                cw = @max(cw, k.rect.x + nd.style.scroll_offset.x + k.rect.w - nd.rect.x + nd.style.pad.value);
            }
            self.scroll_info.put(nd.id, .{ .rect = nd.rect, .content_w = cw, .content_h = ch }) catch {};
        }
    }

    pub fn end(self: *App) void {
        if (self.nodes.items.len > 0) {
            layout.run(self.nodes.items, self.window_size);

            self.prev_rects.clearRetainingCapacity();
            for (self.nodes.items) |n| {
                self.prev_rects.put(n.id, n.rect) catch {};
            }

            self.hitTest();
            self.measureScrolls();
            emit.run(self.nodes.items, self.backend, self.alloc, &self.cmds);
        }
        self.animating = self.animator.any_running;
        if (self.released) self.active = 0;
        self.backend.render(self.cmds.items);
    }

    /// Uses last frame hit-test so its valid before you open the node
    pub fn response(self: *App, id_val: Id) Response {
        const id = self.resolveId(id_val);
        const hovered = self.hot == id;
        if (hovered and self.pressed) self.active = id;
        return .{
            .hovered = hovered,
            .held = self.active == id and self.down,
            .clicked = self.released and self.active == id and hovered,
        };
    }

    /// Final rectangle of a node from the previous frame
    pub fn rectOf(self: *App, id_val: Id) ?Backend.BoundingBox {
        const id = self.resolveId(id_val);
        return self.prev_rects.get(id);
    }

    fn visibleAt(self: *App, i: usize, p: Backend.Vec2) bool {
        const n = self.nodes.items;
        var a = n[i].parent;
        while (a != none) : (a = n[a].parent) {
            if (!n[a].style.clip) continue;
            const r = n[a].rect;
            if (p.x < r.x or p.x >= r.x + r.w or p.y < r.y or p.y >= r.y + r.h) return false;
        }
        return true;
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
                self.mouse.y >= r.y and self.mouse.y < r.y + r.h and
                self.visibleAt(i, self.mouse))
            {
                self.hot = n[i].id;
                break;
            }
        }
    }

    pub fn open(self: *App, id_val: Id, style: Style) void {
        const id = self.resolveId(id_val);
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
        id_val: Id,
        str: []const u8,
        config: struct {
            font_size: u32 = 16,
            font_id: Backend.FontId = 0,
            font_color: Palette.Color = .{ .role = .text },
        },
    ) void {
        const id = self.resolveId(id_val);
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

    pub fn image(self: *App, id_val: Id, tex: Backend.TextureId, style: Style) void {
        const id = self.resolveId(id_val);
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

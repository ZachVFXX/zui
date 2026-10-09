const Backend = @import("../backend.zig");
const Node = @import("node.zig");
const none = Node.none;
const Axis = @import("style.zig").Axis;

fn get(vec: Backend.Vec2, axis: Axis) f32 {
    return if (axis == .x) vec.x else vec.y;
}
fn set(vec: *Backend.Vec2, axis: Axis, f: f32) void {
    if (axis == .x) vec.x = f else vec.y = f;
}
fn other(axis: Axis) Axis {
    return if (axis == .x) .y else .x;
}

/// Three passes over nodes stored in creation (pre-)order:
///   fit      children before parents (reverse order)
///   grow     parents before children
///   position parents before children
pub fn run(nodes: []Node, win: Backend.Vec2) void {
    if (nodes.len == 0) return;

    var i: usize = nodes.len;
    while (i > 0) {
        i -= 1;
        fit(nodes, @intCast(i));
    }

    // The root fills the window
    nodes[0].size = win;
    nodes[0].rect = .{ .x = 0, .y = 0, .w = win.x, .h = win.y };
    nodes[0].alpha = nodes[0].style.alpha.value;

    for (0..nodes.len) |k| {
        grow(nodes, @intCast(k));
        position(nodes, @intCast(k));
    }
}

fn fit(nodes: []Node, i: u32) void {
    const node = &nodes[i];
    const style = node.style;
    if (node.text == null and node.tex == null) {
        const dir = style.dir;
        const other_dir = other(dir);
        var main: f32 = 0;
        var cross: f32 = 0;
        var count: f32 = 0;
        var child_id = node.first;
        while (child_id != none) : (child_id = nodes[child_id].next) {
            if (nodes[child_id].style.floating) continue;
            main += get(nodes[child_id].size, dir);
            cross = @max(cross, get(nodes[child_id].size, other_dir));
            count += 1;
        }
        if (count > 1) main += style.gap.value * (count - 1);
        set(&node.size, dir, main + 2 * style.pad.value);
        set(&node.size, other_dir, cross + 2 * style.pad.value);
    }
    if (style.width.value.fixedValue()) |f| node.size.x = f;
    if (style.height.value.fixedValue()) |f| node.size.y = f;
}

fn grow(nodes: []Node, i: u32) void {
    const node = &nodes[i];
    const style = node.style;
    const dir = style.dir;
    const other_dir = other(dir);
    var free = get(node.size, dir) - 2 * style.pad.value;
    var grow_n: f32 = 0;
    var count: f32 = 0;

    var child_id = node.first;
    while (child_id != none) : (child_id = nodes[child_id].next) {
        if (nodes[child_id].style.floating) continue;
        count += 1;
        if (nodes[child_id].style.sizeOn(dir).isGrow()) grow_n += 1 else free -= get(nodes[child_id].size, dir);
    }
    if (count > 1) free -= style.gap.value * (count - 1);

    const inner_cross = get(node.size, other_dir) - 2 * style.pad.value;
    child_id = node.first;
    while (child_id != none) : (child_id = nodes[child_id].next) {
        if (nodes[child_id].style.floating) continue;
        if (nodes[child_id].style.sizeOn(dir).isGrow()) set(&nodes[child_id].size, dir, @max(0, free) / grow_n);
        if (nodes[child_id].style.sizeOn(other_dir).isGrow()) set(&nodes[child_id].size, other_dir, @max(0, inner_cross));
    }
}

fn position(nodes: []Node, i: u32) void {
    const node = &nodes[i];
    const style = node.style;
    const dir = style.dir;
    const other_dir = other(dir);
    var cursor: f32 = style.pad.value;

    var float_id = node.first;
    while (float_id != none) : (float_id = nodes[float_id].next) {
        const k = &nodes[float_id];
        if (!k.style.floating) continue;
        k.rect = .{
            .x = node.rect.x + k.style.delta_x.value,
            .y = node.rect.y + k.style.delta_y.value,
            .w = k.size.x,
            .h = k.size.y,
        };
        k.alpha = node.alpha * k.style.alpha.value;
    }

    var child_id = node.first;
    while (child_id != none) : (child_id = nodes[child_id].next) {
        if (nodes[child_id].style.floating) continue;
        const k = &nodes[child_id];
        const free_cross = get(node.size, other_dir) - 2 * style.pad.value - get(k.size, other_dir);
        const off_cross = style.pad.value + (if (style.center) free_cross / 2 else 0);
        const ox = if (dir == .x) cursor else off_cross;
        const oy = if (dir == .x) off_cross else cursor;
        k.rect = .{
            .x = node.rect.x + ox + k.style.delta_x.value - node.style.scroll_offset.x,
            .y = node.rect.y + oy + k.style.delta_y.value - node.style.scroll_offset.y,
            .w = k.size.x,
            .h = k.size.y,
        };
        k.alpha = node.alpha * k.style.alpha.value;
        cursor += get(k.size, dir) + style.gap.value;
    }
}

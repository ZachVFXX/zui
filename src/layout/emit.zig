const std = @import("std");
const Backend = @import("../backend.zig");
const Node = @import("node.zig");

fn withAlpha(color: Backend.Rgba, alpha: f32) Backend.Rgba {
    var output = color;
    output.a = @intFromFloat(@as(f32, @floatFromInt(color.a)) * std.math.clamp(alpha, 0, 1));
    return output;
}

fn push(alloc: std.mem.Allocator, cmds: *std.ArrayList(Backend.DrawCmd), cmd: Backend.DrawCmd) void {
    cmds.append(alloc, cmd) catch @panic("OOM");
}

/// Nodes in creation order are also paint in order
pub fn run(
    n: []const Node,
    _: Backend,
    alloc: std.mem.Allocator,
    cmds: *std.ArrayList(Backend.DrawCmd),
) void {
    var clip_ends: [16]u32 = undefined;
    var depth: usize = 0;

    for (n, 0..) |nd, i| {
        while (depth > 0 and clip_ends[depth - 1] <= i) {
            depth -= 1;
            push(alloc, cmds, .clip_pop);
        }

        if (nd.style.bg.value.a > 0) push(alloc, cmds, .{ .rectangle = .{
            .bounding_box = nd.rect,
            .color = withAlpha(nd.style.bg.value, nd.alpha),
            .radius = nd.style.radius.value,
        } });

        if (nd.text) |str| push(alloc, cmds, .{ .text = .{
            .pos = .{ .x = nd.rect.x, .y = nd.rect.y },
            .str = str,
            .font_id = nd.font_id,
            .font_size = nd.font_size,
            .color = withAlpha(nd.color, nd.alpha),
        } });

        if (nd.tex) |t| push(alloc, cmds, .{ .image = .{
            .bounding_box = nd.rect,
            .tex = t,
            .tint = withAlpha(.{}, nd.alpha),
        } });

        if (nd.style.clip and depth < clip_ends.len) {
            push(alloc, cmds, .{ .clip_push = nd.rect });
            clip_ends[depth] = nd.end;
            depth += 1;
        }
    }
    while (depth > 0) : (depth -= 1) push(alloc, cmds, .clip_pop);
}

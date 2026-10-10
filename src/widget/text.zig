const App = @import("../app.zig").App;
const Id = @import("../root.zig").Id;
const Style = @import("../layout/style.zig");
const Node = @import("../layout/node.zig");
const Palette = @import("../palette.zig");
const Backend = @import("../backend.zig");
const Motion = @import("../animation/animation.zig").Motion;

const std = @import("std");

pub const Config = struct {
    font_id: Backend.FontId = 0,
    font_size: u32 = 16,
    font_color: Style.Animate(Palette.Color) = .init(.{ .role = .text }),
};

pub fn textImpl(self: *App, id_val: Id, str: []const u8, config: Config) Node {
    const id = self.resolveId(id_val);

    var final_style = Style{};

    final_style.font_color = .{
        .value = config.font_color.value.resolve(self.palette),
        .motion = config.font_color.motion,
    };

    const resolved_style = self.animator.resolve(self.alloc, id, final_style, self.delta_time, self.resized);
    var n = Node{
        .id = id,
        .style = resolved_style,
        .text = str,
        .font_id = config.font_id,
        .font_size = config.font_size,
        .color = resolved_style.font_color.value,
    };

    n.size = self.backend.measureText(str, config.font_id, config.font_size, null);
    n.end = @intCast(self.nodes.items.len + 1);

    return n;
}

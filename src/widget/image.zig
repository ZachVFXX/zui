const App = @import("../app.zig").App;
const Id = @import("../root.zig").Id;
const Style = @import("../layout/style.zig");
const Node = @import("../layout/node.zig");
const Palette = @import("../palette.zig");
const Backend = @import("../backend.zig");
const Motion = @import("../animation/animation.zig").Motion;

const std = @import("std");

pub fn imgImp(self: *App, id_val: Id, tex: Backend.TextureId, style: Style) Node {
    const id = self.resolveId(id_val);
    const resolved = self.animator.resolve(self.alloc, id, style, self.delta_time, self.resized);
    var n = Node{ .id = id, .style = resolved, .tex = tex };

    n.size = self.backend.textureSize(tex);

    n.end = @intCast(self.nodes.items.len + 1);
    return n;
}

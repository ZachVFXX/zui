const std = @import("std");

pub const App = @import("app.zig").App;
pub const Backend = @import("backend.zig");
pub const RaylibBackend = @import("backend/raylib.zig");
pub const raylib = @import("raylib");
pub const Style = @import("layout/style.zig");
pub const TextInputState = @import("widget/text_input.zig").TextInputState;
pub const hash = @import("app.zig").hash;
pub const none = @import("layout/node.zig").none;

pub const Id = struct {
    hash: u32,
    pub fn id(s: []const u8) Id {
        return .{ .hash = hash(s, 0) };
    }
    pub fn idId(s: []const u8, i: u32) Id {
        return .{ .hash = hash(s, i) };
    }
};

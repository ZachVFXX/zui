const std = @import("std");

pub const App = @import("app.zig").App;
pub const Backend = @import("backend.zig");
pub const RaylibBackend = @import("backend/raylib.zig");
pub const raylib = @import("raylib");
pub const Style = @import("layout/style.zig");
pub const ScrollInfo = @import("app.zig").ScrollInfo;

pub const button = @import("widget/button.zig").button;
pub const beginScroll = @import("widget/scroll.zig").beginScroll;
pub const endScroll = @import("widget/scroll.zig").endScroll;
pub const slider = @import("widget/slider.zig").slider;
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

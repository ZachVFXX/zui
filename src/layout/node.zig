const std = @import("std");
const Backend = @import("../backend.zig");
const Style = @import("style.zig");

pub const none = std.math.maxInt(u32);

id: u32,
style: Style,
parent: u32 = none,
first: u32 = none,
last: u32 = none,
next: u32 = none,
/// one past the last descendant for clipping
end: u32 = 0,
text: ?[]const u8 = null,
tex: ?Backend.TextureId = null,
font_id: Backend.FontId = 0,
font_size: u32 = 12,
color: Backend.Rgba = .{},
size: Backend.Vec2 = .{ .x = 0, .y = 0 },
rect: Backend.BoundingBox = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
/// effective alpha multiplied down from parents
alpha: f32 = 1,

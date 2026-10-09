const std = @import("std");
const Backend = @import("../backend.zig");
const anim = @import("../animation/animation.zig");

pub const Motion = anim.Motion;

pub const Axis = enum { x, y };

pub const Size = union(enum) {
    fit,
    grow,
    fixed: f32,

    // Interpolation hooks
    pub const lane_count = 1;

    pub fn toLanes(self: Size, out: []f32) void {
        out[0] = switch (self) {
            .fixed => |x| x,
            else => 0,
        };
    }

    pub fn fromLanes(in: []const f32, target: Size) Size {
        return switch (target) {
            .fixed => .{ .fixed = in[0] },
            else => target,
        };
    }

    /// fit -> fixed has no start value to ease from, so the tween snaps.
    pub fn kind(self: Size) u8 {
        return @intFromEnum(std.meta.activeTag(self));
    }

    pub fn isGrow(self: Size) bool {
        return switch (self) {
            .grow => true,
            else => false,
        };
    }

    pub fn fixedValue(self: Size) ?f32 {
        return switch (self) {
            .fixed => |f| f,
            else => null,
        };
    }
};

/// A style `value` with type `T` and a `motion`
pub fn Animate(comptime T: type) type {
    return struct {
        pub const is_prop = true;
        pub const Value = T;
        value: T,
        motion: Motion = .none,
        /// First value when apperead. null = start at `value` (no animation)
        enter: ?T = null,

        pub fn init(value: Value) @This() {
            return .{ .value = value };
        }

        pub fn animate(value: Value, motion: Motion) @This() {
            return .{ .value = value, .motion = motion };
        }
    };
}

const Self = @This();
dir: Axis = .y,
center: bool = false,
clip: bool = false,
interactive: bool = false,

width: Animate(Size) = .init(.fit),

height: Animate(Size) = .init(.fit),
pad: Animate(f32) = .init(0),
gap: Animate(f32) = .init(0),
bg: Animate(Backend.Rgba) = .init(.{ .r = 0, .g = 0, .b = 0, .a = 0 }),
radius: Animate(f32) = .init(0),

scroll_x: bool = false,
scroll_y: bool = false,
scroll_offset: Backend.Vec2 = .{ .x = 0, .y = 0 },

delta_x: Animate(f32) = .init(0),
delta_y: Animate(f32) = .init(0),
alpha: Animate(f32) = .init(1),

pub fn sizeOn(self: Self, axis: Axis) Size {
    return if (axis == .x) self.width.value else self.height.value;
}

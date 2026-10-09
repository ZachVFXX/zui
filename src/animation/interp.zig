const std = @import("std");
const anim = @import("animation.zig");

/// A type may define:
///   pub const lane_count: usize
///   pub fn toLanes(self: T, out: []f32) void
///   pub fn fromLanes(in: []const f32, target: T) T
///   pub fn kind(self: T) u8        // when this changes, the tween snaps
pub fn lanes(comptime T: type) usize {
    if (@typeInfo(T) == .@"struct" or @typeInfo(T) == .@"union")
        if (@hasDecl(T, "lane_count")) return T.lane_count;
    return switch (@typeInfo(T)) {
        .float, .int => 1,
        .@"struct" => |s| blk: {
            var n: usize = 0;
            for (s.fields) |f| n += lanes(f.type);
            break :blk n;
        },
        else => 0,
    };
}

pub fn kindOf(comptime T: type, v: T) u8 {
    if (comptime (@typeInfo(T) == .@"struct" or @typeInfo(T) == .@"union") and @hasDecl(T, "kind"))
        return v.kind();
    return 0;
}

/// Convert a type to multiple f32 to be animated
pub fn pack(comptime T: type, v: T, out: []f32) void {
    if (comptime (@typeInfo(T) == .@"struct" or @typeInfo(T) == .@"union") and @hasDecl(T, "toLanes"))
        return v.toLanes(out);
    switch (@typeInfo(T)) {
        .float => out[0] = @floatCast(v),
        .int => out[0] = @floatFromInt(v),
        .@"struct" => |s| {
            comptime var o: usize = 0;
            inline for (s.fields) |f| {
                pack(f.type, @field(v, f.name), out[o..]);
                o += comptime lanes(f.type);
            }
        },
        else => {},
    }
}

/// Convert multiple f32 to the base type
pub fn unpack(comptime T: type, in: []const f32, target: T) T {
    if (comptime (@typeInfo(T) == .@"struct" or @typeInfo(T) == .@"union") and @hasDecl(T, "fromLanes"))
        return T.fromLanes(in, target);
    switch (@typeInfo(T)) {
        .float => return @floatCast(in[0]),
        .int => {
            const lo: f32 = @floatFromInt(std.math.minInt(T));
            const hi: f32 = @floatFromInt(std.math.maxInt(T));
            return @intFromFloat(std.math.clamp(@round(in[0]), lo, hi));
        },
        .@"struct" => |s| {
            var r = target;
            comptime var o: usize = 0;
            inline for (s.fields) |f| {
                @field(r, f.name) = unpack(f.type, in[o..], @field(target, f.name));
                o += comptime lanes(f.type);
            }
            return r;
        },
        else => return target,
    }
}

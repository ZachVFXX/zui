const std = @import("std");

pub const Easing = enum { linear, out_cubic, in_out_cubic, out_back };

pub fn ease(e: Easing, t: f32) f32 {
    const x = std.math.clamp(t, 0, 1);
    return switch (e) {
        .linear => x,
        .out_cubic => blk: {
            const u = 1 - x;
            break :blk 1 - u * u * u;
        },
        .in_out_cubic => blk: {
            if (x < 0.5) break :blk 4 * x * x * x;
            const v = -2 * x + 2;
            break :blk 1 - v * v * v / 2;
        },
        .out_back => blk: {
            const c1: f32 = 1.70158;
            const u = x - 1;
            break :blk 1 + (c1 + 1) * u * u * u + c1 * u * u;
        },
    };
}

pub const Motion = struct {
    duration: f32 = 0, // seconds; 0 = instant
    easing: Easing = .out_cubic,

    pub const none: Motion = .{};
    pub const fast: Motion = .{ .duration = 0.12 };
    pub const smooth: Motion = .{ .duration = 0.25, .easing = .in_out_cubic };
    pub const slow: Motion = .{ .duration = 0.5, .easing = .in_out_cubic };
    pub const bounce: Motion = .{ .duration = 0.35, .easing = .out_back };
};

pub const Tween = struct {
    from: f32,
    to: f32,
    value: f32,
    time: f32 = 1,
    duration: f32 = 0,
    easing: Easing = .linear,

    pub fn init(value: f32) Tween {
        return .{ .from = value, .to = value, .value = value };
    }

    pub fn set(self: *Tween, target: f32, motion: Motion) void {
        if (target == self.to) return;
        self.from = self.value;
        self.to = target;
        self.duration = motion.duration;
        self.easing = motion.easing;
        if (motion.duration <= 0) {
            self.value = target;
            self.time = 1;
        } else self.time = 0;
    }

    pub fn running(self: Tween) bool {
        return self.time < 1;
    }

    pub fn step(self: *Tween, dt: f32) void {
        if (self.time >= 1) return;
        self.time += dt / self.duration;
        if (self.time >= 1) {
            self.time = 1;
            self.value = self.to;
        } else self.value = self.from + (self.to - self.from) * ease(self.easing, self.time);
    }
};

const std = @import("std");
const anim = @import("animation.zig");
const interp = @import("interp.zig");

const Motion = anim.Motion;

fn isProp(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "is_prop");
}

fn countProps(comptime S: type) usize {
    comptime var i: usize = 0;
    inline for (std.meta.fields(S)) |field| {
        if (comptime isProp(field.type)) i += 1;
    }
    return i;
}

fn countLanes(comptime S: type) usize {
    comptime var i: usize = 0;
    inline for (std.meta.fields(S)) |field| {
        if (comptime isProp(field.type)) i += interp.lanes(field.type.Value);
    }
    return i;
}

/// Keeps one tween per animatable lane of `S` keyed by node id
/// `S` is any struct whose animatable fields are `Animate(T)`
pub fn Animator(comptime S: type) type {
    const prop_total = countProps(S);
    const lane_total = countLanes(S);

    return struct {
        const Self = @This();

        const Entry = struct {
            twin: [lane_total]anim.Tween,
            kind: [prop_total]u8,
            seen: u64,
        };

        map: std.AutoHashMapUnmanaged(u32, Entry) = .empty,
        frame: u64 = 0,
        /// True if any tween was still moving during the last frame
        any_running: bool = false,

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            self.map.deinit(alloc);
        }

        /// Call once per frame, before any resolve()
        pub fn beginFrame(self: *Self, alloc: std.mem.Allocator) void {
            self.frame += 1;
            self.any_running = false;

            // Drop state of ids that did not appear last frame
            var dead: std.ArrayList(u32) = .empty;
            defer dead.deinit(alloc);
            var it = self.map.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.seen + 1 < self.frame) dead.append(alloc, entry.key_ptr.*) catch {};
            }
            for (dead.items) |k| _ = self.map.remove(k);
        }

        /// Returns `S` with every Props `.value` replaced by this frame animated value
        /// `snap` makes everything jump to its target (used during window resize)
        pub fn resolve(self: *Self, alloc: std.mem.Allocator, id: u32, s: S, dt: f32, snap: bool) S {
            const gop = self.map.getOrPut(alloc, id) catch return s;
            const a = gop.value_ptr;
            const fresh = !gop.found_existing;
            if (fresh) a.* = .{ .twin = undefined, .kind = undefined, .seen = 0 };
            a.seen = self.frame;

            var out = s;
            comptime var lane_offset: usize = 0; // lane offset
            comptime var prop_index: usize = 0; // prop index

            inline for (std.meta.fields(S)) |field| {
                if (comptime isProp(field.type)) {
                    const T = field.type.Value;
                    const n_lanes = comptime interp.lanes(T);
                    const ptr = @field(s, field.name);
                    const kind = interp.kindOf(T, ptr.value);
                    const motion = if (snap) Motion.none else ptr.motion;

                    var target: [n_lanes]f32 = undefined;
                    interp.pack(T, ptr.value, &target);

                    if (fresh) {
                        var start: [n_lanes]f32 = undefined;
                        interp.pack(T, ptr.enter orelse ptr.value, &start);
                        for (0..n_lanes) |k| a.twin[lane_offset + k] = .init(start[k]);
                    } else if (a.kind[prop_index] != kind) {
                        for (0..n_lanes) |k| a.twin[lane_offset + k] = .init(target[k]); // kind changed: snap
                    }
                    a.kind[prop_index] = kind;

                    var cur: [n_lanes]f32 = undefined;
                    for (0..n_lanes) |k| {
                        const tw = &a.twin[lane_offset + k];
                        tw.set(target[k], motion);
                        tw.step(dt);
                        if (tw.running()) self.any_running = true;
                        cur[k] = tw.value;
                    }
                    @field(out, field.name).value = interp.unpack(T, &cur, ptr.value);

                    lane_offset += n_lanes;
                    prop_index += 1;
                }
            }
            return out;
        }
    };
}

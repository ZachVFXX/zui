const Backend = @import("backend.zig");
const Rgba = Backend.Rgba;

pub const ColorRole = enum {
    transparent,
    surface,
    surface_raised,
    surface_overlay,
    primary,
    primary_hover,
    primary_active,
    text,
    text_dim,
    text_disabled,
    scrollbar_track,
    scrollbar_thumb,
    scrollbar_hover,
};

pub const Color = union(enum) {
    rgba: Rgba,
    role: ColorRole,

    pub fn resolve(self: Color, palette: Self) Rgba {
        return switch (self) {
            .rgba => |c| c,
            .role => |r| palette.fromRole(r),
        };
    }
};

const Self = @This();
surface: Rgba = .{ .r = 20, .g = 20, .b = 20 },
surface_raised: Rgba = .{ .r = 30, .g = 30, .b = 30 },
surface_overlay: Rgba = .{ .r = 40, .g = 40, .b = 40 },

// Interactive
primary: Rgba = .{ .r = 100, .g = 149, .b = 237 },
primary_hover: Rgba = .{ .r = 120, .g = 169, .b = 255 },
primary_active: Rgba = .{ .r = 70, .g = 110, .b = 200 },

// Text
text: Rgba = .{ .r = 255, .g = 255, .b = 255 },
text_dim: Rgba = .{ .r = 180, .g = 180, .b = 180 },
text_disabled: Rgba = .{ .r = 100, .g = 100, .b = 100 },

// Scrollbar
scrollbar_track: Rgba = .{ .r = 40, .g = 40, .b = 40 },
scrollbar_thumb: Rgba = .{ .r = 140, .g = 140, .b = 140 },
scrollbar_hover: Rgba = .{ .r = 180, .g = 180, .b = 180 },

pub fn fromRole(self: Self, role: ColorRole) Rgba {
    return switch (role) {
        .transparent => .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .surface => self.surface,
        .surface_raised => self.surface_raised,
        .surface_overlay => self.surface_overlay,
        .primary => self.primary,
        .primary_hover => self.primary_hover,
        .primary_active => self.primary_active,
        .text => self.text,
        .text_dim => self.text_dim,
        .text_disabled => self.text_disabled,
        .scrollbar_track => self.scrollbar_track,
        .scrollbar_thumb => self.scrollbar_thumb,
        .scrollbar_hover => self.scrollbar_hover,
    };
}

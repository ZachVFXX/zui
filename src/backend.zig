const std = @import("std");

pub const MouseButton = enum(u8) {
    left,
    right,
    middle,
};

pub const InputEvent = union(enum) {
    mouse_move: Vec2,
    mouse_button: struct { button: MouseButton, down: bool },
    wheel: Vec2,
    key: struct { code: Key, down: bool, is_repeat: bool },
    text: u21, // typed character, for text boxes
    resize: Vec2,
    quit: void,
};

pub const DrawCmd = union(enum) {
    rectangle: struct {
        bounding_box: BoundingBox,
        color: Rgba,
        radius: f32 = 0,
        border: f32 = 0,
        border_color: Rgba = .{},
    },
    text: struct {
        pos: Vec2,
        str: []const u8,
        font_id: FontId,
        font_size: u32,
        color: Rgba,
    },
    image: struct {
        bounding_box: BoundingBox,
        tex: TextureId,
        tint: Rgba = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    },
    clip_push: BoundingBox,
    clip_pop: void,
};

pub const ImageData = struct { w: u32, h: u32, rgba: []const u8 };

pub const Vec2 = struct { x: f32 = 0, y: f32 = 0 };

pub const BoundingBox = struct { x: f32 = 0, y: f32 = 0, w: f32 = 0, h: f32 = 0 };

pub const Rgba = struct { r: u8 = 255, g: u8 = 255, b: u8 = 255, a: u8 = 255 };

pub const FontId = u64;
pub const TextureId = u64;
pub const Events = std.ArrayList(InputEvent);

const Self = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    deinit: *const fn (ptr: *anyopaque) void,
    pollEvents: *const fn (ptr: *anyopaque, alloc: std.mem.Allocator, events: *std.ArrayList(InputEvent)) void,
    size: *const fn (ptr: *anyopaque) Vec2,
    now: *const fn (ptr: *anyopaque) f64,
    measureText: *const fn (ptr: *anyopaque, text: []const u8, font_id: FontId, font_size: u32, max_w: ?f32) Vec2,
    render: *const fn (ptr: *anyopaque, cmds: []const DrawCmd) void,

    createTexture: *const fn (ptr: *anyopaque, img: ImageData) ?TextureId,
    destroyTexture: *const fn (ptr: *anyopaque, id: TextureId) void,
    textureSize: *const fn (ptr: *anyopaque, id: TextureId) Vec2,
};

pub fn deinit(self: Self) void {
    self.vtable.deinit(self.ptr);
}

pub fn pollEvents(self: Self, alloc: std.mem.Allocator, events: *Events) void {
    self.vtable.pollEvents(self.ptr, alloc, events);
}

/// The window width and height
pub fn size(self: Self) Vec2 {
    return self.vtable.size(self.ptr);
}

pub fn now(self: Self) f64 {
    return self.vtable.now(self.ptr);
}

pub fn measureText(self: Self, text: []const u8, font_id: FontId, font_size: u32, max_w: ?f32) Vec2 {
    return self.vtable.measureText(self.ptr, text, font_id, font_size, max_w);
}

pub fn render(self: Self, cmds: []const DrawCmd) void {
    self.vtable.render(self.ptr, cmds);
}

pub fn createTexture(self: Self, img: ImageData) ?TextureId {
    return self.vtable.createTexture(self.ptr, img);
}
pub fn destroyTexture(self: Self, id: TextureId) void {
    self.vtable.destroyTexture(self.ptr, id);
}
pub fn textureSize(self: Self, id: TextureId) Vec2 {
    return self.vtable.textureSize(self.ptr, id);
}

pub fn to_backend(obj: anytype) Self {
    const Ptr = @TypeOf(obj);
    const ptr_info = @typeInfo(Ptr);

    // Ensure we are passing a pointer
    std.debug.assert(ptr_info == .pointer);
    std.debug.assert(ptr_info.pointer.size == .one);

    const gen = struct {
        const vtable = VTable{
            .deinit = deinitWrap,
            .pollEvents = pollEventsWrap,
            .size = sizeWrap,
            .now = nowWrap,
            .measureText = measureTextWrap,
            .render = renderWrap,
            .createTexture = createTextureWrap,
            .destroyTexture = destroyTextureWrap,
            .textureSize = textureSizeWrap,
        };

        fn deinitWrap(ptr: *anyopaque) void {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            self.deinit();
        }

        fn pollEventsWrap(ptr: *anyopaque, alloc: std.mem.Allocator, events: *std.ArrayList(InputEvent)) void {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            self.pollEvents(alloc, events);
        }

        fn sizeWrap(ptr: *anyopaque) Vec2 {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            return self.size();
        }

        fn nowWrap(ptr: *anyopaque) f64 {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            return self.now();
        }

        fn measureTextWrap(ptr: *anyopaque, text: []const u8, font_id: FontId, font_size: u32, max_w: ?f32) Vec2 {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            return self.measureText(text, font_id, font_size, max_w);
        }

        fn renderWrap(ptr: *anyopaque, cmds: []const DrawCmd) void {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            self.render(cmds);
        }

        fn createTextureWrap(ptr: *anyopaque, img: ImageData) ?TextureId {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            return self.createTexture(img);
        }
        fn destroyTextureWrap(ptr: *anyopaque, id: TextureId) void {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            self.destroyTexture(id);
        }
        fn textureSizeWrap(ptr: *anyopaque, id: TextureId) Vec2 {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            return self.textureSize(id);
        }
    };

    return .{
        .ptr = obj,
        .vtable = &gen.vtable,
    };
}

const Key = enum(u32) {
    apostrophe = 39,
    comma = 44,
    minus = 45,
    period = 46,
    slash = 47,
    zero = 48,
    one = 49,
    two = 50,
    three = 51,
    four = 52,
    five = 53,
    six = 54,
    seven = 55,
    eight = 56,
    nine = 57,
    semicolon = 59,
    equal = 61,
    a = 65,
    b = 66,
    c = 67,
    d = 68,
    e = 69,
    f = 70,
    g = 71,
    h = 72,
    i = 73,
    j = 74,
    k = 75,
    l = 76,
    m = 77,
    n = 78,
    o = 79,
    p = 80,
    q = 81,
    r = 82,
    s = 83,
    t = 84,
    u = 85,
    v = 86,
    w = 87,
    x = 88,
    y = 89,
    z = 90,
    left_bracket = 91,
    backslash = 92,
    right_bracket = 93,
    grave = 96,
    space = 32,
    escape = 256,
    enter = 257,
    tab = 258,
    backspace = 259,
    insert = 260,
    delete = 261,
    right = 262,
    left = 263,
    down = 264,
    up = 265,
    page_up = 266,
    page_down = 267,
    home = 268,
    end = 269,
    caps_lock = 280,
    scroll_lock = 281,
    num_lock = 282,
    print_screen = 283,
    pause = 284,
    f1 = 290,
    f2 = 291,
    f3 = 292,
    f4 = 293,
    f5 = 294,
    f6 = 295,
    f7 = 296,
    f8 = 297,
    f9 = 298,
    f10 = 299,
    f11 = 300,
    f12 = 301,
    left_shift = 340,
    left_control = 341,
    left_alt = 342,
    left_super = 343,
    right_shift = 344,
    right_control = 345,
    right_alt = 346,
    right_super = 347,
    kb_menu = 348,
    kp_0 = 320,
    kp_1 = 321,
    kp_2 = 322,
    kp_3 = 323,
    kp_4 = 324,
    kp_5 = 325,
    kp_6 = 326,
    kp_7 = 327,
    kp_8 = 328,
    kp_9 = 329,
    kp_decimal = 330,
    kp_divide = 331,
    kp_multiply = 332,
    kp_subtract = 333,
    kp_add = 334,
    kp_enter = 335,
    kp_equal = 336,
    back = 4,
    menu = 5,
    volume_up = 24,
    volume_down = 25,
};

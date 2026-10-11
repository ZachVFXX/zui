const std = @import("std");
const sdl3 = @import("sdl3");
const Backend = @import("../backend.zig");
const FontRenderer = @import("sdl_font_renderer.zig").FontRenderer;

const Self = @This();

alloc: std.mem.Allocator,
window: sdl3.video.Window,
renderer: sdl3.render.Renderer,
textures: std.AutoHashMap(Backend.TextureId, sdl3.render.Texture),
next_id: Backend.TextureId = 1,
font_renderer: FontRenderer,
clips: [256]sdl3.rect.IRect = undefined,
clip_depth: usize = 0,

const log = std.log.scoped(.sdl3);

pub const Options = struct {
    title: [:0]const u8 = "Default",
    width: u32 = 800,
    height: u32 = 600,
    app_name: ?[:0]const u8 = null,
    app_version: ?[:0]const u8 = null,
    app_identifier: ?[:0]const u8 = null,
    resizable: bool = true,
};

pub fn init(alloc: std.mem.Allocator, options: Options) !Self {
    sdl3.setAppMetadata(options.app_name, options.app_version, options.app_identifier) catch {
        log.warn("Failed to set application metadata: {?s}.", .{sdl3.errors.get()});
    };
    sdl3.init(.everything) catch {
        log.err("Failed to initialise sdl3 subsystem: {?s}.", .{sdl3.errors.get()});
        std.process.exit(0);
    };
    log.info("sdl3 subsystem initialized successfully.", .{});
    errdefer sdl3.quit(.everything);
    errdefer sdl3.shutdown();

    const window = try sdl3.video.Window.init(
        options.title,
        options.width,
        options.height,
        .{ .resizable = options.resizable },
    );
    errdefer window.deinit();

    for (0..sdl3.render.getNumDrivers()) |i| {
        log.debug("Driver `{?s}` available.", .{sdl3.render.getDriverName(i)});
    }

    const renderer = sdl3.render.Renderer.init(window, "vulkan") catch {
        log.err("Failed to initialise `{?s}` renderer.", .{sdl3.errors.get()});
        std.process.exit(0);
    };
    errdefer renderer.deinit();
    log.info("Initialised `{s}` renderer successfully.", .{renderer.getName() catch unreachable});

    renderer.setVSync(.{ .on_each_num_refresh = 1 }) catch {
        log.warn("Failed to set VSYNC to this renderer ({s}): {?s}.", .{ try renderer.getName(), sdl3.errors.get() });
    };

    renderer.setDrawBlendMode(.blend) catch {
        log.warn("Blend mode is not supported for this renderer ({s}): {?s}.", .{ try renderer.getName(), sdl3.errors.get() });
    };

    sdl3.keyboard.startTextInput(window) catch {
        log.warn("Failed to start text input for this window {}: {?s}.", .{ window.getId() catch unreachable, sdl3.errors.get() });
    };

    _ = try window.createPopup(100, 100, 200, 200, .{ .popup_menu = true });

    return .{
        .alloc = alloc,
        .window = window,
        .renderer = renderer,
        .textures = .init(alloc),
        .font_renderer = .init(alloc),
    };
}

pub fn deinit(self: *Self) void {
    var it = self.textures.valueIterator();
    while (it.next()) |t| t.deinit();

    self.textures.deinit();
    self.font_renderer.deinit();

    if (sdl3.keyboard.textInputActive(self.window)) {
        sdl3.keyboard.stopTextInput(self.window) catch {
            log.warn("Failed to stop text input for this window {} : {?s}.", .{ self.window.getId() catch unreachable, sdl3.errors.get() });
        };
    }

    self.renderer.deinit();
    self.window.deinit();

    sdl3.quit(.everything);
    sdl3.shutdown();
    log.info("sdl3 shutdown successfully.", .{});
}

fn mapKey(raw: u32) ?Backend.Key {
    const ext: u32 = 1 << 30;
    return switch (raw) {
        8 => .backspace,
        9 => .tab,
        13 => .enter,
        27 => .escape,
        32 => .space,
        127 => .delete,
        'a'...'z' => std.enums.fromInt(Backend.Key, raw - 32), // convert a to A
        '0'...'9' => std.enums.fromInt(Backend.Key, raw),
        ext | 0x49 => .insert,
        ext | 0x4A => .home,
        ext | 0x4B => .page_up,
        ext | 0x4D => .end,
        ext | 0x4E => .page_down,
        ext | 0x4F => .right,
        ext | 0x50 => .left,
        ext | 0x51 => .down,
        ext | 0x52 => .up,
        ext | 0x58 => .kp_enter,
        else => null,
    };
}

pub fn pollEvents(self: *Self, alloc: std.mem.Allocator, events: *std.ArrayList(Backend.InputEvent)) void {
    while (sdl3.events.poll()) |event| {
        switch (event) {
            .quit, .terminating, .window_close_requested => events.append(alloc, .quit) catch @panic("OOM"),

            .window_resized, .window_pixel_size_changed => {
                events.append(alloc, .{ .resize = self.size() }) catch @panic("OOM");
            },

            .mouse_motion => |m| {
                events.append(alloc, .{ .mouse_move = .{ .x = m.x, .y = m.y } }) catch @panic("OOM");
            },
            .window_focus_lost => {
                self.window.flash(.until_focused) catch @panic("OOM");
            },

            .mouse_button_down, .mouse_button_up => |m| {
                const btn: Backend.MouseButton = switch (m.button) {
                    .left => .left,
                    .right => .right,
                    .middle => .middle,
                    else => continue,
                };
                events.append(alloc, .{ .mouse_button = .{ .button = btn, .down = m.down } }) catch @panic("OOM");
            },

            .mouse_wheel => |w| {
                events.append(alloc, .{ .wheel = .{ .x = w.scroll_x, .y = w.scroll_y } }) catch @panic("OOM");
            },

            .key_down, .key_up => |k| {
                const keycode = k.key orelse continue;
                const code = mapKey(@intFromEnum(keycode)) orelse continue;
                events.append(alloc, .{ .key = .{ .code = code, .down = k.down, .is_repeat = k.repeat } }) catch @panic("OOM");
            },

            .text_input => |t| {
                // A UTF-8 string, possibly several codepoints.
                const view = std.unicode.Utf8View.init(t.text) catch continue;
                var it = view.iterator();
                while (it.nextCodepoint()) |cp| {
                    events.append(alloc, .{ .text = cp }) catch @panic("OOM");
                }
            },

            else => |k| {
                log.debug("EVENT: {}", .{k});
            },
        }
    }
}

pub fn size(self: *Self) Backend.Vec2 {
    const s = self.window.getSize() catch return .{ .x = 800, .y = 600 };
    return .{ .x = @floatFromInt(s[0]), .y = @floatFromInt(s[1]) };
}

pub fn now(_: *Self) f64 {
    return @as(f64, @floatFromInt(sdl3.timer.getMillisecondsSinceInit())) / 1000.0;
}

pub fn measureText(self: *Self, text: []const u8, font_id: Backend.FontId, font_size: u32, max_w: ?f32) Backend.Vec2 {
    _ = max_w; // TODO wrapping
    return self.font_renderer.measureText(text, font_size, font_id);
}

fn fcolor(color: Backend.Rgba) sdl3.pixels.FColor {
    const k: f32 = 1.0 / 255.0;
    return .{
        .r = @as(f32, @floatFromInt(color.r)) * k,
        .g = @as(f32, @floatFromInt(color.g)) * k,
        .b = @as(f32, @floatFromInt(color.b)) * k,
        .a = @as(f32, @floatFromInt(color.a)) * k,
    };
}

fn setColor(self: *Self, color: Backend.Rgba) void {
    self.renderer.setDrawColor(.{
        .r = color.r,
        .g = color.g,
        .b = color.b,
        .a = color.a,
    }) catch {};
}

/// `roundness` follows raylib: 0..1 of half the shorter side. SDL has no rounded rect,
/// so this draws a triangle fan around the center.
fn fillRounded(self: *Self, bb: Backend.BoundingBox, roundness: f32, color: Backend.Rgba) void {
    const r = std.math.clamp(roundness, 0, 1) * @min(bb.w, bb.h) / 2;
    if (r < 0.5) {
        self.setColor(color);
        self.renderer.renderFillRect(.{ .x = bb.x, .y = bb.y, .w = bb.w, .h = bb.h }) catch {};
        return;
    }

    const seg = 6;
    const pts_n = 4 * (seg + 1);
    const col = fcolor(color);
    const zero = sdl3.rect.FPoint{ .x = 0, .y = 0 };

    const corners = [4][3]f32{
        .{ bb.x + bb.w - r, bb.y + r, -std.math.pi / 2.0 }, // top right
        .{ bb.x + bb.w - r, bb.y + bb.h - r, 0 }, // bottom right
        .{ bb.x + r, bb.y + bb.h - r, std.math.pi / 2.0 }, // bottom left
        .{ bb.x + r, bb.y + r, std.math.pi }, // top left
    };

    var pts: [pts_n]sdl3.render.Vertex = undefined;
    var n: usize = 0;
    for (corners) |cn| {
        for (0..seg + 1) |i| {
            const a = cn[2] + (std.math.pi / 2.0) * @as(f32, @floatFromInt(i)) / seg;
            pts[n] = .{ .position = .{ .x = cn[0] + @cos(a) * r, .y = cn[1] + @sin(a) * r }, .color = col, .tex_coord = zero };
            n += 1;
        }
    }

    const center = sdl3.render.Vertex{
        .position = .{ .x = bb.x + bb.w / 2, .y = bb.y + bb.h / 2 },
        .color = col,
        .tex_coord = zero,
    };
    var tris: [pts_n * 3]sdl3.render.Vertex = undefined;
    for (0..pts_n) |i| {
        tris[i * 3] = center;
        tris[i * 3 + 1] = pts[i];
        tris[i * 3 + 2] = pts[(i + 1) % pts_n];
    }
    self.renderer.renderGeometry(null, &tris, null) catch {};
}

fn intersect(a: sdl3.rect.IRect, b: sdl3.rect.IRect) sdl3.rect.IRect {
    const x0 = @max(a.x, b.x);
    const y0 = @max(a.y, b.y);
    const x1 = @min(a.x + a.w, b.x + b.w);
    const y1 = @min(a.y + a.h, b.y + b.h);
    return .{ .x = x0, .y = y0, .w = @max(0, x1 - x0), .h = @max(0, y1 - y0) };
}

pub fn render(self: *Self, cmds: []const Backend.DrawCmd) void {
    self.setColor(.{ .r = 20, .g = 20, .b = 20, .a = 255 });
    self.renderer.clear() catch {};
    self.clip_depth = 0;
    self.renderer.setClipRect(null) catch {};

    for (cmds) |cmd| switch (cmd) {
        .rectangle => |rect| {
            self.fillRounded(rect.bounding_box, rect.radius, rect.color);
            if (rect.border > 0) {
                const bb = rect.bounding_box;
                self.setColor(rect.border_color);
                self.renderer.renderRect(.{ .x = bb.x, .y = bb.y, .w = bb.w, .h = bb.h }) catch {};
            }
        },

        .text => |t| {
            self.font_renderer.drawText(self.renderer, t.str, t.font_size, t.font_id, t.color, t.pos.x, t.pos.y) catch {};
        },

        .image => |img| {
            const texture = self.textures.get(img.tex) orelse continue;
            texture.setColorMod(img.tint.r, img.tint.g, img.tint.b) catch {};
            texture.setAlphaMod(img.tint.a) catch {};
            const dst = sdl3.rect.FRect{ .x = img.bounding_box.x, .y = img.bounding_box.y, .w = img.bounding_box.w, .h = img.bounding_box.h };
            self.renderer.renderTexture(texture, null, dst) catch {};
        },

        .clip_push => |c| {
            var r = sdl3.rect.IRect{
                .x = @intFromFloat(c.x),
                .y = @intFromFloat(c.y),
                .w = @intFromFloat(c.w),
                .h = @intFromFloat(c.h),
            };
            if (self.clip_depth > 0) r = intersect(r, self.clips[self.clip_depth - 1]); // nested clips
            if (self.clip_depth < self.clips.len) {
                self.clips[self.clip_depth] = r;
                self.clip_depth += 1;
            }
            self.renderer.setClipRect(r) catch {};
        },

        .clip_pop => {
            if (self.clip_depth > 0) self.clip_depth -= 1;
            if (self.clip_depth > 0) {
                self.renderer.setClipRect(self.clips[self.clip_depth - 1]) catch {};
            } else {
                self.renderer.setClipRect(null) catch {};
            }
        },
    };

    self.renderer.present() catch {};
    self.font_renderer.garbageCollect();
}

pub fn createTexture(self: *Self, img: Backend.ImageData) ?Backend.TextureId {
    // R,G,B,A byte order in memory, on any endianness.
    const surface = sdl3.surface.Surface.initFrom(img.w, img.h, .array_rgba_32, @constCast(img.rgba)) catch return null;
    defer surface.deinit();

    const tex = self.renderer.createTextureFromSurface(surface) catch return null;
    tex.setScaleMode(.linear) catch {};

    const id = self.next_id;
    self.textures.put(id, tex) catch {
        tex.deinit();
        return null;
    };
    self.next_id += 1;
    return id;
}

pub fn destroyTexture(self: *Self, id: Backend.TextureId) void {
    if (self.textures.fetchRemove(id)) |kv| kv.value.deinit();
}

pub fn textureSize(self: *Self, id: Backend.TextureId) Backend.Vec2 {
    const t = self.textures.get(id) orelse return .{};
    const s = t.getSize() catch return .{};
    return .{ .x = s[0], .y = s[1] };
}

pub fn to_backend(self: *Self) Backend {
    return Backend.to_backend(self);
}

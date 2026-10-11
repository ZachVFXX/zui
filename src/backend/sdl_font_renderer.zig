const std = @import("std");
const sdl3 = @import("sdl3");
const Backend = @import("../backend.zig");

const pango = @import("pango");
const pangocairo = @import("pangocairo");
const cairo = @import("cairo");
const gobject = @import("gobject");
const glib = @import("glib");

const TextKey = struct { text: []const u8, font_size: u32, font_id: u64 };

const TextKeyContext = struct {
    pub fn hash(_: @This(), key: TextKey) u64 {
        var h = std.hash.Wyhash.init(0);
        h.update(key.text);
        h.update(std.mem.asBytes(&key.font_size));
        h.update(std.mem.asBytes(&key.font_id));
        return h.final();
    }
    pub fn eql(_: @This(), a: TextKey, b: TextKey) bool {
        return a.font_size == b.font_size and a.font_id == b.font_id and std.mem.eql(u8, a.text, b.text);
    }
};

const CachedTexture = struct { texture: sdl3.render.Texture, w: f32, h: f32, last_used_frame: u64 };
const CachedMeasurement = struct { dims: Backend.Vec2, last_used_frame: u64 };

const TextureCache = std.HashMap(TextKey, CachedTexture, TextKeyContext, std.hash_map.default_max_load_percentage);
const MeasurementCache = std.HashMap(TextKey, CachedMeasurement, TextKeyContext, std.hash_map.default_max_load_percentage);

pub const FontRenderer = struct {
    alloc: std.mem.Allocator,
    pango_context: *pango.Context,
    textures: TextureCache,
    measurements: MeasurementCache,
    id_to_font: std.AutoHashMap(u64, [*:0]const u8),
    current_frame: u64 = 0,
    keys_to_remove: std.ArrayList(TextKey) = .empty,

    pub fn init(alloc: std.mem.Allocator) FontRenderer {
        const font_map = pangocairo.FontMap.getDefault();
        const context = font_map.createContext();
        context.setRoundGlyphPositions(0);
        return .{
            .alloc = alloc,
            .pango_context = context,
            .textures = .init(alloc),
            .measurements = .init(alloc),
            .id_to_font = .init(alloc),
        };
    }

    pub fn deinit(self: *FontRenderer) void {
        var it = self.textures.iterator();
        while (it.next()) |e| {
            e.value_ptr.texture.deinit();
            self.alloc.free(e.key_ptr.text);
        }
        var mit = self.measurements.iterator();
        while (mit.next()) |e| self.alloc.free(e.key_ptr.text);

        self.id_to_font.deinit();
        self.textures.deinit();
        self.measurements.deinit();
        self.keys_to_remove.deinit(self.alloc);
        gobject.Object.unref(self.pango_context.as(gobject.Object));
    }

    pub fn addFont(self: *FontRenderer, font_name: [*:0]const u8, font_id: u64) !void {
        const r = try self.id_to_font.getOrPut(font_id);
        if (r.found_existing) {
            std.log.err("FontId {} already exists ({s})", .{ font_id, r.value_ptr.* });
        } else {
            r.value_ptr.* = font_name;
        }
    }

    pub fn addFontFile(self: *FontRenderer, font_file: [*:0]const u8, family_name: [*:0]const u8, font_id: u64) !void {
        var err: ?*glib.Error = null;
        const ok = self.pango_context.getFontMap().?.addFontFile(font_file, &err);
        if (ok == 0) {
            if (err) |e| {
                const msg = if (e.f_message) |m| std.mem.span(m) else "no message";
                std.log.err("Failed to load {s}: {s}", .{ font_file, msg });
            }
            return error.LoadingFontFile;
        }
        try self.addFont(family_name, font_id);
    }

    fn createLayout(self: *FontRenderer, text: []const u8, font_size: u32, font_id: u64) !*pango.Layout {
        const layout = pango.Layout.new(self.pango_context);
        errdefer gobject.Object.unref(layout.as(gobject.Object));

        const text_z = try self.alloc.dupeZ(u8, text);
        defer self.alloc.free(text_z);
        layout.setText(text_z.ptr, @intCast(text.len));

        const description = pango.FontDescription.new();
        defer description.free();
        description.setFamily(if (self.id_to_font.get(font_id)) |f| f else "Noto Sans");
        description.setSize(@intCast(font_size * pango.SCALE));
        layout.setFontDescription(description);
        return layout;
    }

    pub fn measureText(self: *FontRenderer, text: []const u8, font_size: u32, font_id: u64) Backend.Vec2 {
        if (text.len == 0 or font_size == 0) return .{};

        const key = TextKey{ .text = text, .font_size = font_size, .font_id = font_id };
        if (self.measurements.getPtr(key)) |c| {
            c.last_used_frame = self.current_frame;
            return c.dims;
        }

        const layout = self.createLayout(text, font_size, font_id) catch return .{};
        defer gobject.Object.unref(layout.as(gobject.Object));

        var w: c_int = 0;
        var h: c_int = 0;
        layout.getPixelSize(&w, &h);
        const dims = Backend.Vec2{ .x = @floatFromInt(w), .y = @floatFromInt(h) };

        const owned = self.alloc.dupe(u8, text) catch return dims;
        self.measurements.put(
            .{ .text = owned, .font_size = font_size, .font_id = font_id },
            .{ .dims = dims, .last_used_frame = self.current_frame },
        ) catch self.alloc.free(owned);
        return dims;
    }

    pub fn drawText(
        self: *FontRenderer,
        renderer: sdl3.render.Renderer,
        text: []const u8,
        font_size: u32,
        font_id: u64,
        color: Backend.Rgba,
        x: f32,
        y: f32,
    ) !void {
        if (text.len == 0 or font_size == 0) return;

        const key = TextKey{ .text = text, .font_size = font_size, .font_id = font_id };
        if (self.textures.getPtr(key)) |c| {
            c.last_used_frame = self.current_frame;
            blit(c.*, color, x, y);
            return;
        }

        const entry = try self.rasterize(renderer, text, font_size, font_id) orelse return;
        const owned = try self.alloc.dupe(u8, text);
        errdefer self.alloc.free(owned);
        try self.textures.put(
            .{ .text = owned, .font_size = font_size, .font_id = font_id },
            entry,
        );
        blit(entry, color, x, y);
    }

    fn blit(c: CachedTexture, color: Backend.Rgba, x: f32, y: f32) void {
        c.texture.setColorMod(color.r, color.g, color.b) catch {};
        c.texture.setAlphaMod(color.a) catch {};
        // renderer is bound to the texture, so the call goes through it
        const render = c.texture.getRenderer() catch unreachable;
        render.renderTexture(c.texture, null, .{ .x = x, .y = y, .w = c.w, .h = c.h }) catch {};
    }

    /// Shapes the text with Pango, draws it white with Cairo, uploads it as a texture.
    fn rasterize(
        self: *FontRenderer,
        renderer: sdl3.render.Renderer,
        text: []const u8,
        font_size: u32,
        font_id: u64,
    ) !?CachedTexture {
        const layout = try self.createLayout(text, font_size, font_id);
        defer gobject.Object.unref(layout.as(gobject.Object));

        var width: c_int = 0;
        var height: c_int = 0;
        layout.getPixelSize(&width, &height);
        if (width <= 0 or height <= 0) return null;

        const sw = width + 1;
        const sh = height + 1;

        const surface = cairo.Surface.imageCreate(.argb32, sw, sh);
        defer surface.destroy();
        if (surface.status() != .success) return error.CairoSurfaceFailed;

        const cr = cairo.Context.create(surface);
        defer cr.destroy();
        cr.setOperator(.clear);
        cr.paint();
        cr.setOperator(.over);
        cr.setSourceRgba(1.0, 1.0, 1.0, 1.0);
        pangocairo.showLayout(cr, layout);
        surface.flush();

        const data = surface.imageGetData() orelse return error.CairoDataFailed;
        const stride: usize = @intCast(surface.imageGetStride());
        const w: usize = @intCast(sw);
        const h: usize = @intCast(sh);

        // Cairo ARGB32 is premultiplied BGRA on little endian. The text is white,
        // so only alpha matters: write straight white pixels with that alpha.
        const pixels = try self.alloc.alloc(u8, w * h * 4);
        defer self.alloc.free(pixels);
        for (0..h) |yy| {
            const row = data + yy * stride;
            for (0..w) |xx| {
                const a = row[xx * 4 + 3];
                const dst = pixels[(yy * w + xx) * 4 ..][0..4];
                dst[0] = 255;
                dst[1] = 255;
                dst[2] = 255;
                dst[3] = a;
            }
        }

        const sdl_surface = try sdl3.surface.Surface.initFrom(@intCast(w), @intCast(h), .array_rgba_32, pixels);
        defer sdl_surface.deinit();

        const texture = try renderer.createTextureFromSurface(sdl_surface);
        try texture.setScaleMode(.linear);
        try texture.setBlendMode(.blend);

        return .{
            .texture = texture,
            .w = @floatFromInt(sw),
            .h = @floatFromInt(sh),
            .last_used_frame = self.current_frame,
        };
    }

    pub fn garbageCollect(self: *FontRenderer) void {
        self.current_frame +%= 1;
        if (self.current_frame % 600 != 0) return; // every ~10 s at 60 fps

        const ttl: u64 = 60 * 5;

        var tit = self.textures.iterator();
        while (tit.next()) |e| {
            if (self.current_frame - e.value_ptr.last_used_frame > ttl)
                self.keys_to_remove.append(self.alloc, e.key_ptr.*) catch return;
        }
        for (self.keys_to_remove.items) |k| {
            if (self.textures.fetchRemove(k)) |kv| {
                kv.value.texture.deinit();
                self.alloc.free(kv.key.text);
            }
        }
        self.keys_to_remove.clearRetainingCapacity();

        var mit = self.measurements.iterator();
        while (mit.next()) |e| {
            if (self.current_frame - e.value_ptr.last_used_frame > ttl)
                self.keys_to_remove.append(self.alloc, e.key_ptr.*) catch return;
        }
        for (self.keys_to_remove.items) |k| {
            if (self.measurements.fetchRemove(k)) |kv| self.alloc.free(kv.key.text);
        }
        self.keys_to_remove.clearRetainingCapacity();
    }
};

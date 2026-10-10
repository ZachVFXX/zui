const std = @import("std");
const rl = @import("raylib");
const cl = @import("zclay");

const pango = @import("pango");
const pangocairo = @import("pangocairo");
const cairo = @import("cairo");
const gobject = @import("gobject");
const glib = @import("glib");

const TextKey = struct {
    text: []const u8,
    font_size: u32,
    font_id: u64,
};

const TextKeyContext = struct {
    pub fn hash(_: @This(), key: TextKey) u64 {
        var h = std.hash.Wyhash.init(0);

        h.update(key.text);
        h.update(std.mem.asBytes(&key.font_size));
        h.update(std.mem.asBytes(&key.font_id));

        return h.final();
    }

    pub fn eql(_: @This(), a: TextKey, b: TextKey) bool {
        return a.font_size == b.font_size and
            a.font_id == b.font_id and
            std.mem.eql(u8, a.text, b.text);
    }
};

const TextureCache = std.HashMap(
    TextKey,
    rl.Texture,
    TextKeyContext,
    std.hash_map.default_max_load_percentage,
);

const MeasurementCache = std.HashMap(
    TextKey,
    cl.Dimensions,
    TextKeyContext,
    std.hash_map.default_max_load_percentage,
);

pub const FontRenderer = struct {
    alloc: std.mem.Allocator,
    pango_context: *pango.Context,
    textures: TextureCache,
    measurements: MeasurementCache,
    id_to_font: std.AutoHashMap(u64, [*:0]const u8),

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

    pub fn addFont(self: *FontRenderer, font_name: [*:0]const u8, font_id: u64) !void {
        const result = try self.id_to_font.getOrPut(font_id, font_name);
        if (result.found_existing) {
            std.log.err("FontId {} already exist in map with name {s}", .{ font_id, result.value_ptr });
        } else {
            result.key_ptr = font_id;
            result.value_ptr = font_name;
        }
    }

    pub fn addFontFile(self: *FontRenderer, font_file: [*:0]const u8, family_name: [*:0]const u8, font_id: u64) !void {
        var err: ?*glib.Error = null;
        const r = self.pango_context.getFontMap().?.addFontFile(
            font_file,
            &err,
        );

        if (r == 0) {
            if (err) |e| {
                const msg = if (e.f_message) |m| std.mem.span(m) else "no message";
                std.log.err("Failed to load {s}: {s}", .{ font_file, msg });
            }
            return error.LoadingFontFile;
        }

        try self.addFont(family_name, font_id);
    }

    fn setLayoutText(
        self: *FontRenderer,
        layout: *pango.Layout,
        text: []const u8,
    ) !void {
        const text_z = try self.alloc.dupeZ(u8, text);
        defer self.alloc.free(text_z);

        layout.setText(
            text_z.ptr,
            @intCast(text.len),
        );
    }

    pub fn deinit(self: *FontRenderer) void {
        var it = self.textures.iterator();

        while (it.next()) |entry| {
            if (entry.value_ptr.IsTextureValid())
                entry.value_ptr.UnloadTexture();
            self.alloc.free(entry.key_ptr.text);
        }

        var measure_it = self.measurements.iterator();
        while (measure_it.next()) |entry| {
            self.alloc.free(entry.key_ptr.text);
        }

        self.id_to_font.deinit();
        self.textures.deinit();
        self.measurements.deinit();
        gobject.Object.unref(self.pango_context.as(gobject.Object));
    }

    fn createLayout(
        self: *FontRenderer,
        text: []const u8,
        font_size: u32,
        font_id: u64,
    ) !*pango.Layout {
        const layout = pango.Layout.new(self.pango_context);

        errdefer gobject.Object.unref(layout.as(gobject.Object));

        try self.setLayoutText(layout, text);

        const description = pango.FontDescription.new();
        defer description.free();

        if (self.id_to_font.get(font_id)) |family_name| {
            description.setFamily(family_name);
        } else {
            description.setFamily("Noto Sans");
        }

        description.setSize(
            @intCast(font_size * pango.SCALE),
        );

        layout.setFontDescription(description);
        return layout;
    }

    pub fn getFontList(self: *FontRenderer) []*pango.FontFamily {
        var families_ptr: [*]*pango.FontFamily = undefined;
        var count: c_int = undefined;
        self.pango_context.listFamilies(&families_ptr, &count);
        const families = families_ptr[0..@intCast(count)];
        return families;
    }

    pub fn drawText(
        self: *FontRenderer,
        text: []const u8,
        font_size: u32,
        font_id: u64,
        color: rl.Color,
        position: rl.Vector2,
    ) !void {
        if (text.len == 0)
            return;

        if (font_size <= 0)
            return;

        const key = TextKey{
            .text = text,
            .font_size = font_size,
            .font_id = font_id,
        };

        if (self.textures.get(key)) |texture| {
            rl.DrawTextureV(
                texture,
                position,
                color,
            );

            return;
        }

        const layout = try self.createLayout(
            text,
            font_size,
            font_id,
        );

        defer gobject.Object.unref(layout.as(gobject.Object));

        var width: c_int = 0;
        var height: c_int = 0;

        layout.getPixelSize(
            &width,
            &height,
        );

        if (width <= 0 or height <= 0)
            return;

        const surface_width = width + 1;
        const surface_height = height + 1;

        const surface =
            cairo.Surface.imageCreate(
                .argb32,
                surface_width,
                surface_height,
            );
        defer surface.destroy();

        if (surface.status() != .success)
            return error.CairoSurfaceFailed;

        const cr =
            cairo.Context.create(surface);

        defer cr.destroy();

        cr.setOperator(.clear);
        cr.paint();

        cr.setOperator(.over);

        cr.setSourceRgba(1.0, 1.0, 1.0, 1.0);

        pangocairo.showLayout(
            cr,
            layout,
        );

        surface.flush();

        const cairo_data_opt = surface.imageGetData();

        const cairo_data = cairo_data_opt orelse
            return error.CairoDataFailed;

        const stride: usize =
            @intCast(surface.imageGetStride());

        const w: usize =
            @intCast(surface_width);

        const h: usize =
            @intCast(surface_height);

        const pixels =
            try self.alloc.alloc(
                u8,
                w * h * 4,
            );

        defer self.alloc.free(pixels);

        for (0..h) |y| {
            const row =
                cairo_data + y * stride;

            for (0..w) |x| {
                const src =
                    row + x * 4;

                const dst =
                    pixels[(y * w + x) * 4 ..][0..4];

                const b = src[0];
                const g = src[1];
                const r = src[2];
                const a = src[3];

                if (a == 0) {
                    dst[0] = 0;
                    dst[1] = 0;
                    dst[2] = 0;
                    dst[3] = 0;
                } else {
                    dst[0] = unpremultiply(r, a);
                    dst[1] = unpremultiply(g, a);
                    dst[2] = unpremultiply(b, a);
                    dst[3] = a;
                }
            }
        }

        const image = rl.Image{
            .data = pixels.ptr,
            .width = surface_width,
            .height = surface_height,
            .mipmaps = 1,
            .format = rl.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
        };

        const texture =
            rl.LoadTextureFromImage(image);

        if (texture.id == 0)
            return error.TextureCreationFailed;

        rl.SetTextureFilter(
            texture,
            rl.TEXTURE_FILTER_BILINEAR,
        );

        const owned_text =
            try self.alloc.dupe(u8, text);

        errdefer {
            self.alloc.free(owned_text);
            rl.UnloadTexture(texture);
        }

        try self.textures.put(
            .{
                .text = owned_text,
                .font_size = font_size,
                .font_id = font_id,
            },
            texture,
        );

        rl.DrawTextureV(
            texture,
            position,
            color,
        );
    }

    pub fn measureText(
        self: *FontRenderer,
        text: []const u8,
        font_size: u32,
        font_id: u64,
    ) cl.Dimensions {
        if (text.len == 0 or font_size <= 0) return .{ .w = 0, .h = 0 };

        const key = TextKey{
            .text = text,
            .font_size = font_size,
            .font_id = font_id,
        };

        if (self.measurements.get(key)) |dims| {
            return dims;
        }

        const layout =
            self.createLayout(
                text,
                font_size,
                font_id,
            ) catch return .{
                .w = 0,
                .h = 0,
            };

        defer gobject.Object.unref(layout.as(gobject.Object));

        var width: c_int = 0;
        var height: c_int = 0;

        layout.getPixelSize(
            &width,
            &height,
        );

        const dims = cl.Dimensions{
            .w = @floatFromInt(width),
            .h = @floatFromInt(height),
        };

        const owned_text = self.alloc.dupe(u8, text) catch return dims;
        self.measurements.put(.{
            .text = owned_text,
            .font_size = font_size,
            .font_id = font_id,
        }, dims) catch {};

        return dims;
    }

    fn unpremultiply(
        value: u8,
        alpha: u8,
    ) u8 {
        if (alpha == 0)
            return 0;

        const v: u32 = value;
        const a: u32 = alpha;

        const result =
            (v * 255 + a / 2) / a;

        return @intCast(@min(result, 255));
    }
};

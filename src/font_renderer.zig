const std = @import("std");
const rl = @import("raylib");
const cl = @import("zclay");

const pango = @import("pango");
const pangocairo = @import("pangocairo");
const cairo = @import("cairo");
const gobject = @import("gobject");

const TextKey = struct {
    text: []const u8,
    font_size: i32,
    font_id: u16,
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

const TextureCache =
    std.HashMap(
        TextKey,
        rl.Texture,
        TextKeyContext,
        std.hash_map.default_max_load_percentage,
    );

pub const FontRenderer = struct {
    alloc: std.mem.Allocator,
    pango_context: *pango.Context,
    textures: TextureCache,
    id_to_font: std.ArrayList([*:0]const u8) = .empty,

    pub fn init(alloc: std.mem.Allocator) !FontRenderer {
        const font_map = pangocairo.FontMap.getDefault();

        const context = font_map.createContext();

        context.setRoundGlyphPositions(1);

        return .{
            .alloc = alloc,
            .pango_context = context,
            .textures = .init(alloc),
        };
    }

    pub fn addFont(self: *FontRenderer, font_name: [*:0]const u8, font_id: u16) !void {
        try self.id_to_font.insert(self.alloc, font_id, font_name);
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
        self.id_to_font.deinit(self.alloc);

        var it = self.textures.iterator();

        while (it.next()) |entry| {
            rl.UnloadTexture(entry.value_ptr.*);
            self.alloc.free(entry.key_ptr.text);
        }

        self.textures.deinit();

        gobject.Object.unref(self.pango_context.as(gobject.Object));
    }

    fn createLayout(
        self: *FontRenderer,
        text: []const u8,
        font_size: i32,
        font_id: u16,
    ) !*pango.Layout {
        const layout =
            pango.Layout.new(self.pango_context);

        errdefer gobject.Object.unref(layout.as(gobject.Object));

        try self.setLayoutText(layout, text);

        const description = pango.FontDescription.fromString(self.id_to_font.items[font_id]);
        defer description.free();

        description.setSize(
            font_size * pango.SCALE,
        );

        layout.setFontDescription(description);
        return layout;
    }

    pub fn drawText(
        self: *FontRenderer,
        text: []const u8,
        font_size: i32,
        font_id: u16,
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
        text: []const u8,
        textCfg: *cl.TextElementConfig,
        self: *FontRenderer,
    ) cl.Dimensions {
        if (text.len == 0 or textCfg.font_size <= 0)
            return .{
                .w = 0,
                .h = 0,
            };

        const layout =
            self.createLayout(
                text,
                textCfg.font_size,
                textCfg.font_id,
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

        return .{
            .w = @floatFromInt(width),
            .h = @floatFromInt(height),
        };
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

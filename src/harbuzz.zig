const hb = @import("harfbuzz");
const std = @import("std");
const rl = @import("raylib");
const cl = @import("zclay");

const SUBPIXEL_BITS: i32 = 6;
const SUBPIXEL_SCALE: i32 = 1 << SUBPIXEL_BITS; // 64

pub const HbFontSlot = struct {
    font: *hb.c.hb_font_t,
    /// true if the face has color glyphs (COLR/CPAL/CBDT/sbix/SVG) use
    /// hb_raster_paint, otherwise use hb_raster_draw (outline coverage).
    has_color: bool,
};

var hb_font_slots: std.AutoHashMapUnmanaged(i32, HbFontSlot) = .empty;
var font_textures: std.StringHashMapUnmanaged(rl.Texture) = .empty;

pub fn loadFont(alloc: std.mem.Allocator, font_id: i32, file_data: []const u8) !void {
    const blob = hb.c.hb_blob_create(
        file_data.ptr,
        @intCast(file_data.len),
        hb.c.HB_MEMORY_MODE_READONLY,
        null,
        null,
    ) orelse return error.FontLoadFailed;

    const face = hb.c.hb_face_create(blob, 0) orelse return error.FontLoadFailed;

    const font = hb.c.hb_font_create(face) orelse return error.FontLoadFailed;

    const is_color = hb.c.hb_ot_color_has_paint(face) != 0 or
        hb.c.hb_ot_color_has_layers(face) != 0 or
        hb.c.hb_ot_color_has_png(face) != 0;

    try hb_font_slots.put(alloc, font_id, .{ .font = font, .has_color = is_color });
}

pub fn uninit(alloc: std.mem.Allocator) void {
    var it = hb_font_slots.iterator();
    while (it.next()) |entry| {
        hb.c.hb_font_destroy(entry.value_ptr.font);
    }
    hb_font_slots.deinit(alloc);

    var tex_it = font_textures.iterator();
    while (tex_it.next()) |entry| {
        rl.UnloadTexture(entry.value_ptr.*);
    }
    font_textures.deinit(alloc);
}

pub fn draw_text(alloc: std.mem.Allocator, text: []const u8, font_id: u16, font_size: i32, text_color: rl.Color, bounding_box: cl.BoundingBox) !void {
    if (font_textures.contains(text)) {
        rl.DrawTextureV(font_textures.get(text).?, .{ .x = bounding_box.x, .y = bounding_box.y }, text_color);
    } else {
        const slot = hb_font_slots.get(font_id) orelse return;

        hb.c.hb_font_set_scale(
            slot.font,
            font_size * SUBPIXEL_SCALE,
            font_size * SUBPIXEL_SCALE,
        );

        //------------------------
        // Shape
        //------------------------

        const buf = hb.c.hb_buffer_create();
        defer hb.c.hb_buffer_destroy(buf);

        hb.c.hb_buffer_add_utf8(
            buf,
            text.ptr,
            @intCast(text.len),
            0,
            @intCast(text.len),
        );

        hb.c.hb_buffer_guess_segment_properties(buf);

        hb.c.hb_shape(slot.font, buf, null, 0);

        const len = hb.c.hb_buffer_get_length(buf);

        if (len == 0) return;

        const info = hb.c.hb_buffer_get_glyph_infos(buf, null);

        const pos = hb.c.hb_buffer_get_glyph_positions(buf, null);

        //---------------------------------
        // Compute text extents
        //---------------------------------

        var width: f32 = 0;

        for (0..len) |i| {
            width += @as(f32, @floatFromInt(pos[i].x_advance));
        }

        var h_ext: hb.c.hb_font_extents_t = undefined;

        _ = hb.c.hb_font_get_h_extents(slot.font, &h_ext);

        const ascender: i32 = @divFloor(h_ext.ascender, SUBPIXEL_SCALE);
        const descender: i32 = @divFloor(h_ext.descender, SUBPIXEL_SCALE);

        const height = @as(f32, @floatFromInt(ascender - descender));

        var ext: hb.c.hb_raster_extents_t = .{
            .x_origin = 0,
            .y_origin = descender,
            .width = @intFromFloat(@ceil(width / SUBPIXEL_SCALE)),
            .height = @intFromFloat(@ceil(height)),
            .stride = @intFromFloat(@ceil(width / SUBPIXEL_SCALE)),
        };

        //---------------------------------
        // Rasterizer
        //---------------------------------

        const img = blk: {
            if (slot.has_color) {
                const p =
                    hb.c.hb_raster_paint_create_or_fail() orelse return;

                defer hb.c.hb_raster_paint_destroy(p);

                var pen_x: f32 = 0;
                var pen_y: f32 = 0;

                for (0..len) |i| {
                    const gx = (pen_x + @as(f32, @floatFromInt(pos[i].x_offset))) / SUBPIXEL_SCALE;
                    const gy = (pen_y + @as(f32, @floatFromInt(pos[i].y_offset))) / SUBPIXEL_SCALE;
                    hb.c.hb_raster_paint_set_extents(p, &ext);

                    hb.c.hb_raster_paint_set_scale_factor(p, SUBPIXEL_SCALE, SUBPIXEL_SCALE);
                    hb.c.hb_raster_paint_set_transform(p, 1, 0, 0, 1, gx, gy);

                    hb.c.hb_raster_paint_glyph(p, slot.font, info[i].codepoint);

                    pen_x += @as(f32, @floatFromInt(pos[i].x_advance));

                    pen_y += @as(f32, @floatFromInt(pos[i].y_advance));
                }
                break :blk hb.c.hb_raster_paint_render(p);
            } else {
                const d = hb.c.hb_raster_draw_create_or_fail() orelse return;
                defer hb.c.hb_raster_draw_destroy(d);

                var pen_x: f32 = 0;
                var pen_y: f32 = 0;

                for (0..len) |i| {
                    const gx = pen_x + @as(f32, @floatFromInt(pos[i].x_offset));

                    const gy = pen_y + @as(f32, @floatFromInt(pos[i].y_offset));

                    hb.c.hb_raster_draw_set_extents(d, &ext);

                    hb.c.hb_raster_draw_set_scale_factor(d, SUBPIXEL_SCALE, SUBPIXEL_SCALE);

                    hb.c.hb_raster_draw_set_transform(d, 1, 0, 0, 1, gx, gy);

                    hb.c.hb_raster_draw_glyph(d, slot.font, info[i].codepoint);

                    pen_x += @as(f32, @floatFromInt(pos[i].x_advance));

                    pen_y += @as(f32, @floatFromInt(pos[i].y_advance));
                }

                break :blk hb.c.hb_raster_draw_render(d);
            }
        };

        const raster = img orelse return;
        defer hb.c.hb_raster_image_destroy(raster);
        //---------------------------------
        // Raylib
        //---------------------------------

        const src = hb.c.hb_raster_image_get_buffer(raster) orelse return;

        const format = hb.c.hb_raster_image_get_format(raster);

        hb.c.hb_raster_image_get_extents(raster, &ext);

        // std.debug.print("width={} height={} stride={}\n", .{ ext.width, ext.height, ext.stride });

        const w: usize = @intCast(ext.width);
        const h: usize = @intCast(ext.height);
        const stride: usize = @intCast(ext.stride);

        const copy = try alloc.alloc(u8, w * h * 4);
        defer alloc.free(copy);

        if (format == hb.c.HB_RASTER_FORMAT_A8) {
            for (0..h) |y| {
                for (0..w) |x| {
                    const a = src[y * stride + x];
                    const dst_i = (y * w + x) * 4;
                    copy[dst_i + 0] = 255;
                    copy[dst_i + 1] = 255;
                    copy[dst_i + 2] = 255;
                    copy[dst_i + 3] = a;
                }
            }
        } else {
            for (0..h) |y| {
                for (0..w) |x| {
                    const src_i = y * stride + x * 4;
                    const dst_i = (y * w + x) * 4;
                    copy[dst_i + 0] = src[src_i + 2];
                    copy[dst_i + 1] = src[src_i + 1];
                    copy[dst_i + 2] = src[src_i + 0];
                    copy[dst_i + 3] = src[src_i + 3];
                }
            }
        }

        const row_size = w * 4;

        var tmp = try alloc.alloc(u8, copy.len);
        defer alloc.free(tmp);

        for (0..h) |y| {
            const src_y = h - 1 - y;
            @memcpy(tmp[y * row_size .. (y + 1) * row_size], copy[src_y * row_size .. (src_y + 1) * row_size]);
        }

        @memcpy(copy, tmp);

        const img_ray = rl.Image{
            .data = copy.ptr,
            .width = @intCast(w),
            .height = @intCast(h),
            .mipmaps = 1,
            .format = rl.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
        };

        const tex = rl.LoadTextureFromImage(img_ray);
        try font_textures.put(alloc, text, tex);
        rl.DrawTextureV(
            tex,
            .{
                .x = bounding_box.x,
                .y = bounding_box.y,
            },
            text_color,
        );
    }
}

pub fn measureText(clay_text: []const u8, config: *cl.TextElementConfig, _: void) cl.Dimensions {
    const font_size: i32 = @intCast(config.font_size);

    const slot = hb_font_slots.get(config.font_id).?;

    // IMPORTANT:
    // use the same scale as rendering
    hb.c.hb_font_set_scale(
        slot.font,
        font_size * SUBPIXEL_SCALE,
        font_size * SUBPIXEL_SCALE,
    );

    var max_width: f32 = 0;
    var line_count: usize = 0;

    var lines = std.mem.splitScalar(
        u8,
        clay_text,
        '\n',
    );

    while (lines.next()) |line| {
        line_count += 1;

        const buf = hb.c.hb_buffer_create();
        defer hb.c.hb_buffer_destroy(buf);

        hb.c.hb_buffer_add_utf8(
            buf,
            line.ptr,
            @intCast(line.len),
            0,
            @intCast(line.len),
        );

        hb.c.hb_buffer_guess_segment_properties(buf);

        hb.c.hb_shape(
            slot.font,
            buf,
            null,
            0,
        );

        const len = hb.c.hb_buffer_get_length(buf);

        if (len == 0)
            continue;

        const pos = hb.c.hb_buffer_get_glyph_positions(
            buf,
            null,
        );

        var width: f32 = 0;

        for (0..len) |i| {
            width += @as(f32, @floatFromInt(pos[i].x_advance)) / SUBPIXEL_SCALE;
        }

        if (width > max_width) max_width = width;
    }

    if (line_count == 0) line_count = 1;

    var h_ext: hb.c.hb_font_extents_t = undefined;
    _ = hb.c.hb_font_get_h_extents(slot.font, &h_ext);

    const ascender: f32 = @floatFromInt(@divFloor(h_ext.ascender, SUBPIXEL_SCALE));
    const descender: f32 = @floatFromInt(@divFloor(h_ext.descender, SUBPIXEL_SCALE));
    const font_line_height = ascender - descender;

    const line_height =
        if (config.line_height > 0) @as(f32, @floatFromInt(config.line_height)) else font_line_height;

    return .{
        .w = max_width,
        .h = line_height * @as(f32, @floatFromInt(line_count)),
    };
}

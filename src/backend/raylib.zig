const std = @import("std");
const raylib = @import("raylib");
const Backend = @import("../backend.zig");
const FontRender = @import("font_renderer.zig").FontRenderer;

const Self = @This();
alloc: std.mem.Allocator,
textures: std.AutoHashMap(Backend.TextureId, raylib.Texture2D),
next_id: Backend.TextureId = 1,
font_renderer: FontRender,
pub const Options = struct { title: [:0]const u8 = "Default", width: u32 = 800, height: u32 = 600, fps: u32 = 60 };

pub fn init(alloc: std.mem.Allocator, opts: Options) !Self {
    raylib.SetConfigFlags(raylib.FLAG_WINDOW_RESIZABLE | raylib.FLAG_MSAA_4X_HINT);
    raylib.InitWindow(@intCast(opts.width), @intCast(opts.height), opts.title);
    raylib.SetTargetFPS(@intCast(opts.fps));
    return .{ .alloc = alloc, .textures = .init(alloc), .font_renderer = .init(alloc) };
}

pub fn deinit(self: *Self) void {
    var tex_it = self.textures.valueIterator();
    while (tex_it.next()) |t| raylib.UnloadTexture(t.*);
    self.textures.deinit();
    self.font_renderer.deinit();
    raylib.CloseWindow();
}

pub fn pollEvents(self: *Self, alloc: std.mem.Allocator, events: *std.ArrayList(Backend.InputEvent)) void {
    pollMouseMovementEvents(alloc, events);
    pollMouseButtonEvents(alloc, events);
    pollMouseScrollEvents(alloc, events);
    pollKeyPressEvent(alloc, events);
    pollKeyReleaseOrRepeatEvent(alloc, events);

    if (raylib.WindowShouldClose()) events.append(alloc, .quit) catch @panic("OOM");

    if (raylib.IsWindowResized()) events.append(alloc, .{ .resize = self.size() }) catch @panic("OOM");
}

fn pollMouseMovementEvents(alloc: std.mem.Allocator, events: *std.ArrayList(Backend.InputEvent)) void {
    const mouse_pos = raylib.GetMousePosition();
    const delta = raylib.GetMouseDelta();
    if (delta.x != 0 or delta.y != 0) {
        events.append(alloc, .{ .mouse_move = .{ .x = mouse_pos.x, .y = mouse_pos.y } }) catch @panic("OOM");
    }
}

fn pollMouseButtonEvents(alloc: std.mem.Allocator, events: *std.ArrayList(Backend.InputEvent)) void {
    // Mouse Buttons (0=Left, 1=Right, 2=Middle)
    const buttons = [_]u8{ raylib.MOUSE_LEFT_BUTTON, raylib.MOUSE_RIGHT_BUTTON, raylib.MOUSE_BUTTON_MIDDLE };
    for (buttons) |btn| {
        if (raylib.IsMouseButtonPressed(btn)) {
            events.append(alloc, .{ .mouse_button = .{ .button = @enumFromInt(btn), .down = true } }) catch @panic("OOM");
        }
        if (raylib.IsMouseButtonReleased(btn)) {
            events.append(alloc, .{ .mouse_button = .{ .button = @enumFromInt(btn), .down = false } }) catch @panic("OOM");
        }
    }
}

fn pollMouseScrollEvents(alloc: std.mem.Allocator, events: *std.ArrayList(Backend.InputEvent)) void {
    const wheel = raylib.GetMouseWheelMoveV();
    if (wheel.x != 0 or wheel.y != 0) {
        events.append(alloc, .{ .wheel = .{ .x = wheel.x, .y = wheel.y } }) catch @panic("OOM");
    }
}

fn pollKeyPressEvent(alloc: std.mem.Allocator, events: *std.ArrayList(Backend.InputEvent)) void {
    var key_pressed = raylib.GetKeyPressed();
    while (key_pressed > 0) : (key_pressed = raylib.GetKeyPressed()) {
        events.append(alloc, .{ .key = .{ .code = key_pressed, .down = true, .is_repeat = false } }) catch @panic("OOM");
    }
}

fn pollKeyReleaseOrRepeatEvent(alloc: std.mem.Allocator, events: *std.ArrayList(Backend.InputEvent)) void {
    for (raylib.KEY_NULL..raylib.KEY_KB_MENU) |k_usize| {
        const k: c_int = @intCast(k_usize);

        // !IsKeyPressed for ONLY the auto-repeats
        if (raylib.IsKeyPressedRepeat(k) and !raylib.IsKeyPressed(k)) {
            events.append(alloc, .{ .key = .{ .code = k, .down = true, .is_repeat = true } }) catch @panic("OOM");
        }

        // Key releases
        if (raylib.IsKeyReleased(k)) {
            events.append(alloc, .{ .key = .{ .code = k, .down = false, .is_repeat = false } }) catch @panic("OOM");
        }
    }
}

pub fn size(self: *Self) Backend.Vec2 {
    _ = self;
    return .{
        .x = @floatFromInt(raylib.GetScreenWidth()),
        .y = @floatFromInt(raylib.GetScreenHeight()),
    };
}

pub fn now(self: *Self) f64 {
    _ = self;
    return raylib.GetTime();
}

pub fn measureText(self: *Self, text: []const u8, font_id: Backend.FontId, font_size: u32, max_w: ?f32) Backend.Vec2 {
    _ = max_w; // TODO custom line wrapper

    const vec = self.font_renderer.measureText(text, font_size, font_id);
    return .{ .x = vec.w, .y = vec.h };
}

pub fn render(self: *Self, cmds: []const Backend.DrawCmd) void {
    raylib.BeginDrawing();
    defer raylib.EndDrawing();

    raylib.ClearBackground(raylib.RAYWHITE);

    for (cmds) |cmd| {
        switch (cmd) {
            .rectangle => |rect| {
                const rec = raylib.Rectangle{ .x = rect.bounding_box.x, .y = rect.bounding_box.y, .width = rect.bounding_box.w, .height = rect.bounding_box.h };
                const color = raylib.Color{ .r = rect.color.r, .g = rect.color.g, .b = rect.color.b, .a = rect.color.a };

                if (rect.radius > 0) {
                    raylib.DrawRectangleRounded(rec, rect.radius, 16, color);
                } else {
                    raylib.DrawRectangleRec(rec, color);
                }

                if (rect.border > 0) {
                    const border_color = raylib.Color{ .r = rect.border_color.r, .g = rect.border_color.g, .b = rect.border_color.b, .a = rect.border_color.a };
                    if (rect.radius > 0) {
                        raylib.DrawRectangleRoundedLinesEx(rec, rect.radius, 16, rect.border, border_color);
                    } else {
                        raylib.DrawRectangleLinesEx(rec, rect.border, border_color);
                    }
                }
            },
            .text => |t| {
                const color = raylib.Color{ .r = t.color.r, .g = t.color.g, .b = t.color.b, .a = t.color.a };
                const pos = raylib.Vector2{ .x = t.pos.x, .y = t.pos.y };
                self.font_renderer.drawText(t.str, t.font_size, t.font_id, color, pos) catch {};
            },
            .image => |img| {
                const texture = self.textures.get(img.tex) orelse continue;
                const color = raylib.Color{ .r = img.tint.r, .g = img.tint.g, .b = img.tint.b, .a = img.tint.a };

                raylib.DrawTextureEx(
                    texture,
                    raylib.Vector2{ .x = img.bounding_box.x, .y = img.bounding_box.y },
                    0,
                    img.bounding_box.w / @as(f32, @floatFromInt(texture.width)),
                    color,
                );
            },
            .clip_push => |c| {
                raylib.BeginScissorMode(@intFromFloat(c.x), @intFromFloat(c.y), @intFromFloat(c.w), @intFromFloat(c.h));
            },
            .clip_pop => {
                raylib.EndScissorMode();
            },
        }
    }
    raylib.DrawFPS(0, 0);
}

pub fn createTexture(self: *Self, img: Backend.ImageData) ?Backend.TextureId {
    const rimg = raylib.Image{
        .data = @constCast(img.rgba.ptr),
        .width = @intCast(img.w),
        .height = @intCast(img.h),
        .mipmaps = 1,
        .format = raylib.PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
    };
    const tex = raylib.LoadTextureFromImage(rimg); // copies pixels to the GPU
    if (!raylib.IsTextureValid(tex)) return null;
    raylib.SetTextureFilter(tex, raylib.TEXTURE_FILTER_BILINEAR);
    const id = self.next_id;
    self.textures.put(id, tex) catch {
        raylib.UnloadTexture(tex);
        return null;
    };
    self.next_id += 1;
    return id;
}

pub fn destroyTexture(self: *Self, id: Backend.TextureId) void {
    if (self.textures.fetchRemove(id)) |kv| raylib.UnloadTexture(kv.value);
}

pub fn textureSize(self: *Self, id: Backend.TextureId) Backend.Vec2 {
    const t = self.textures.get(id) orelse return .{ .x = 0, .y = 0 };
    return .{ .x = @floatFromInt(t.width), .y = @floatFromInt(t.height) };
}

pub fn to_backend(self: *Self) Backend {
    return Backend.to_backend(self);
}

const std = @import("std");
const zui = @import("zui");
const Raylib = zui.RaylibBackend;
const App = zui.App;
const hash = zui.hash;
const raylib = zui.raylib;

pub fn main(init: std.process.Init) !void {
    var rl = try Raylib.init(init.gpa, .{ .title = "Saturn", .width = 800, .height = 600 });
    defer rl.deinit();

    var app = App.init(init.gpa, rl.to_backend(), .{});
    defer app.deinit();
    const id = hash("panel", 0);
    var panel_open = false;

    const data = @embedFile("assets/test.png");
    const img = raylib.LoadImageFromMemory(".png", @ptrCast(data.ptr), @intCast(data.len));
    defer raylib.UnloadImage(img); // Pense à libérer la mémoire CPU après création

    // 1. Calcul du nombre total d'octets de l'image (RGBA = 4 octets par pixel)
    const bytes_per_pixel: usize = 4; // Ou adapte selon le format si dynamique
    const total_bytes: usize = @as(usize, @intCast(img.width)) * @as(usize, @intCast(img.height)) * bytes_per_pixel;

    // 2. Tranchage du pointeur nulo-capable (*anyopaque -> [*]u8 -> []u8)
    const raw_ptr: [*]u8 = @ptrCast(img.data orelse return error.NullImageData);
    const img_bytes: []u8 = raw_ptr[0..total_bytes];

    // 3. Création de la texture
    const TextId = rl.createTexture(.{
        .w = @intCast(img.width),
        .h = @intCast(img.height),
        .rgba = img_bytes,
    }) orelse return error.InvalidTexture;

    while (!app.quit) {
        app.begin();
        defer app.end();

        app.beginScroll(hash("root", 0), .{
            .scroll_y = true,
            .width = .init(.grow),
            .height = .init(.grow),
            .pad = .init(16),
            .gap = .init(16),
            .bg = .init(app.palette.surface),
        });
        defer app.endScroll();

        if (zui.button(&app, hash("toggle", 0), "Toggle")) panel_open = !panel_open;

        const r = app.response(id);
        app.beginScroll(id, .{
            .pad = .init(12.0),
            .gap = .animate(if (r.held) 12 else 6, .smooth),
            .width = .init(.grow),
            .scroll_y = true,
            .height = .{ .value = .{ .fixed = if (panel_open) 160 else 0 }, .motion = .smooth },
            .alpha = .{ .value = if (panel_open) 1 else 0, .motion = .smooth, .enter = 0 },
            .delta_y = .{ .value = if (r.hovered) 0 else 24, .motion = .smooth, .enter = 0 },
            .bg = .{ .value = app.palette.surface_raised },
        });
        app.text(hash("l", 0), @embedFile("assets/test.txt"), .{});
        app.endScroll();
        app.image(hash("zerze", 1), TextId, .{ .width = .init(.grow), .height = .init(.grow) });
    }
}

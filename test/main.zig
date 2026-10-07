const std = @import("std");
const ui = @import("zui");

pub fn main(init: std.process.Init) !void {
    var app = try ui.App.init(init.gpa, "Dropdown Demo", 600, 400, .{});
    defer app.deinit();

    try app.addFont("NotoSans Regular", 0);
    try app.addFont("NotoSans Bold", 1);

    while (!app.is_closing()) {
        app.update();
        app.beginLayout();
        const root = app.Column(.ID("Root"), .{ .sizing = .{ .w = .grow, .h = .grow }, .padding = .{ .left = 40, .top = 40, .right = 40, .bottom = 40 }, .gap = 20, .color = .{ .role = .surface } }, .{
            app.Text(.ID("Label"), .{
                .text = "tetststs",
                .font_size = 16,
                .font_id = 0,
                .color = .{ .role = .text },
            }),
            app.Text(.ID("dd"), .{
                .text = "sdgsdgsdfgdssgdfgdsg",
                .font_id = 1,
                .font_size = 8,
                .color = .{ .role = .text },
            }),
        });

        app.endLayout(root);
        try app.render();
    }
}

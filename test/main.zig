const std = @import("std");
const ui = @import("zui");

const clay = ui.clay;

const State = struct {
    language: ui.DropdownWidget = .{
        .options = &.{ "Zig", "C", "Rust", "Go" },
    },
};

pub fn main(init: std.process.Init) !void {
    var app = try ui.App.init(init.gpa, "Dropdown Demo", 600, 400, .{});
    defer app.deinit();

    try app.loadFont(@embedFile("assets/NotoColorEmoji-Regular.ttf"), 1);
    try app.loadFont(@embedFile("assets/NotoSans-Regular.ttf"), 0);

    //var state: State = .{};

    var textbox: *ui.TextBoxWidget = try .init(init.gpa);
    defer textbox.deinit();

    while (!app.is_closing()) {
        app.update();
        app.beginLayout();
        const pr = app.Progress(.ID("PROGRESS"), .{ .value = 0 }, .{});
        const slider = app.Slider(.ID("slider"), .{ .value = 0 });
        const root = app.Column(.ID("Root"), .{ .sizing = .{ .w = .grow, .h = .grow }, .padding = .{ .left = 40, .top = 40, .right = 40, .bottom = 40 }, .gap = 20, .color = .{ .role = .surface } }, .{
            app.Text(.ID("Label"), .{
                .text = "Choisis un langage :",
                .font_size = 16,
                .font_id = 0,
                .color = .{ .role = .text },
            }),
            pr,
            slider,
            app.TextBox(.ID("string: []const u8"), textbox, .{}),
        });

        app.endLayout(root);
        try app.render();
    }
}

const std = @import("std");
const ui = @import("zui");

const clay = ui.clay;

// État persistant entre les frames
const State = struct {
    language: ui.DropdownWidget = .{
        .options = &.{ "Zig", "C", "Rust", "Go" },
    },
};

pub fn main(init: std.process.Init) !void {
    var app = try ui.App.init(init.gpa, "Dropdown Demo", 600, 400, .{});
    defer app.uninit();

    try app.loadFont(@embedFile("assets/NotoColorEmoji-Regular.ttf"), 1, 16);
    try app.loadFont(@embedFile("assets/NotoSans-Regular.ttf"), 0, 16);

    var state: State = .{};

    while (!app.is_closing()) {
        app.update();
        app.beginLayout();

        const root = app.Column(.ID("Root"), .{ .sizing = .{ .w = .grow, .h = .grow }, .padding = .{ .left = 40, .top = 40, .right = 40, .bottom = 40 }, .gap = 20, .color = .{ .role = .surface } }, .{
            app.Text(.ID("Label"), .{
                .text = "Choisis un langage :",
                .font_size = 16,
                .color = .{ .role = .text },
            }),
            app.Dropdown(.ID("LangSelect"), &state.language),
            app.Text(.ID("Result"), .{
                .text = state.language.value(),
                .font_size = 24,
                .color = .{ .role = .primary },
            }),
            app.Button(.ID("test"), .{ .frame = .{ .sizing = .fit, .padding = .all(32) } }, .{
                app.Button(.ID("other"), .{ .frame = .{ .sizing = .fit, .padding = .all(32) } }, .{
                    app.Text(.ID("suuu"), .{ .text = "suuuu" }),
                }),
            }),
            app.Scroll(.ID("TESTTT"), .{}, .{app.Text(.ID("UTF8"), .{ .text = "✅😃🙂‍↕️", .font_id = 1 })}),
        });

        app.endLayout(root);
        try app.render();
    }
}

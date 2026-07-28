const std = @import("std");
pub const clay = @import("zclay");
const renderer = @import("renderer.zig");
const rl = @import("raylib");
const Color = @import("color.zig").Color;
const Palette = @import("color.zig").Palette;
const builtin = @import("builtin");
const Harffbuzz = @import("harbuzz.zig");
const RowWidget = @import("widgets/row.zig").RowWidget;
const ColumnWidget = @import("widgets/column.zig").ColumnWidget;
const ScrollWidget = @import("widgets/scroll.zig").ScrollWidget;
const ButtonWidget = @import("widgets/button.zig").ButtonWidget;
const ImageWidget = @import("widgets/image.zig").ImageWidget;
const TextWidget = @import("widgets/text.zig").TextWidget;
const SliderWidget = @import("widgets/slider.zig").SliderWidget;
const TextBoxWidget = @import("widgets/textbox.zig").TextBoxWidget;
const DropdownWidget = @import("widgets/dropdown.zig").DropdownWidget;
const ProgressBarWidget = @import("widgets/progress.zig").ProgressBarWidget;

pub const Widget = struct {
    id: clay.ElementId,
    children: []const Widget = &.{},
    app: *App,
    data: *anyopaque,
    renderFn: *const fn (*anyopaque, Widget, []const Widget) void,

    pub fn render(self: Widget) void {
        self.renderFn(self.data, self, self.children);
    }
};

pub const Event = union(enum) {
    hovered: clay.ElementId,
    pressed: clay.ElementId,
    released: clay.ElementId,
    slider_changed: struct { id: clay.ElementId, value: u32 },
    key_pressed: i32,
    key_released: i32,
};

const Interaction = struct {
    hot: ?clay.ElementId = null,
    active: ?clay.ElementId = null,
    top_hovered: ?clay.ElementId = null,
};

export fn logClayError(errors: clay.ErrorData) void {
    const err_msg = errors.error_text.chars[0..@intCast(errors.error_text.length)];
    const typed = errors.error_type;
    std.log.err("CLAY ERROR {d}: {s}\n", .{ typed, err_msg });
    std.process.exit(1);
}

pub extern "c" fn vsnprintf(
    buffer: [*]u8,
    size: usize,
    format: [*c]const u8,
    args: [*c]rl.struct___va_list_tag_1,
) c_int;

export fn logRaylib(
    level: c_int,
    format: [*c]const u8,
    args: [*c]rl.struct___va_list_tag_1,
) callconv(.c) void {
    var buf: [4096]u8 = undefined;

    const len = vsnprintf(
        &buf,
        buf.len,
        format,
        args,
    );

    if (len < 0) return;

    const msg = buf[0..@min(@as(usize, @intCast(len)), buf.len - 1)];

    switch (level) {
        rl.LOG_INFO => std.log.info("{s}", .{msg}),
        rl.LOG_WARNING => std.log.warn("{s}", .{msg}),
        rl.LOG_ERROR, rl.LOG_FATAL => std.log.err("{s}", .{msg}),
        else => std.log.debug("{d}: {s}", .{ level, msg }),
    }
}

pub const App = struct {
    title: [:0]const u8,
    width: i32,
    height: i32,
    alloc: std.mem.Allocator,
    frame_arena: std.heap.ArenaAllocator,
    memory: []u8,
    render_commands: ?[]clay.RenderCommand,
    interaction: Interaction,
    palette: Palette,
    events: std.ArrayListUnmanaged(Event),
    interactive_ids: std.AutoHashMap(u32, void),

    pub fn init(alloc: std.mem.Allocator, title: []const u8, default_width: i32, default_height: i32, palette: Palette) !App {
        const c_path = try alloc.dupeSentinel(u8, title, 0);
        const width = if (builtin.abi.isAndroid()) rl.GetScreenWidth() else default_width;
        const height = if (builtin.abi.isAndroid()) rl.GetScreenHeight() else default_height;
        rl.SetTraceLogCallback(logRaylib);

        if (builtin.abi.isAndroid()) {
            rl.SetConfigFlags(rl.FLAG_WINDOW_HIGHDPI);
        } else {
            rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE);
        }

        rl.InitWindow(width, height, c_path);
        rl.InitAudioDevice();
        rl.SetTargetFPS(rl.GetMonitorRefreshRate(rl.GetCurrentMonitor()));

        const memory = try alloc.alloc(u8, clay.minMemorySize());
        _ = clay.initialize(.init(memory), .{ .h = @floatFromInt(rl.GetScreenHeight()), .w = @floatFromInt(rl.GetScreenWidth()) }, .{ .error_handler_function = logClayError, .user_data = null });
        clay.setMeasureTextFunction(void, {}, renderer.measureText);
        return .{
            .title = c_path,
            .width = rl.GetScreenWidth(),
            .height = rl.GetScreenHeight(),
            .alloc = alloc,
            .memory = memory,
            .render_commands = null,
            .frame_arena = .init(alloc),
            .interaction = .{},
            .palette = palette,
            .events = .empty,
            .interactive_ids = .init(alloc),
        };
    }

    pub fn loadFont(self: *App, file_data: []const u8, font_id: u16) !void {
        try renderer.loadFont(self.alloc, font_id, file_data);
    }

    pub fn interactImpl(self: *App, id: clay.ElementId, release_anywhere: bool) enum { mouse_hovered, mouse_pressed, mouse_released, none } {
        const is_hovered =
            self.interaction.top_hovered != null and
            self.interaction.top_hovered.?.id == id.id;

        const pressed = rl.IsMouseButtonPressed(rl.MOUSE_LEFT_BUTTON);
        const down = rl.IsMouseButtonDown(rl.MOUSE_LEFT_BUTTON);
        const released = rl.IsMouseButtonReleased(rl.MOUSE_LEFT_BUTTON);

        if (is_hovered) {
            self.interaction.hot = id;
            self.events.append(self.alloc, .{ .hovered = id }) catch {};
        }

        if (pressed and is_hovered and self.interaction.active == null) {
            self.interaction.active = id;
            self.events.append(self.alloc, .{ .pressed = id }) catch {};
            return .mouse_pressed;
        }

        if (self.interaction.active) |active_id| {
            if (active_id.id == id.id) {
                if (down) {
                    self.events.append(self.alloc, .{ .pressed = id }) catch {};
                    return .mouse_pressed;
                }
                if (released) {
                    self.interaction.active = null;
                    if (release_anywhere or is_hovered) {
                        self.events.append(self.alloc, .{ .released = id }) catch {};
                        return .mouse_released;
                    }
                    return .none;
                }
            }
        }

        if (is_hovered) return .mouse_hovered;
        return .none;
    }

    pub fn keyPressed(self: *App, key: anytype) bool {
        const keycode: i32 = switch (@TypeOf(key)) {
            u8, comptime_int => @intCast(key),
            i32 => key,
            c_int => @intCast(key),
            else => @compileError("key must be a char or i32"),
        };
        for (self.events.items) |ev| {
            switch (ev) {
                .key_pressed => |k| if (k == keycode) return true,
                else => {},
            }
        }
        return false;
    }

    pub fn is_closing(_: *App) bool {
        return rl.WindowShouldClose();
    }

    pub fn update(self: *App) void {
        self.width = rl.GetRenderWidth();
        self.height = rl.GetRenderHeight();
        clay.setLayoutDimensions(.{ .w = @floatFromInt(self.width), .h = @floatFromInt(self.height) });
        clay.setPointerState(.{ .x = rl.GetMousePosition().x, .y = rl.GetMousePosition().y }, rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT));
        const touch_scroll = builtin.abi.isAndroid();
        clay.updateScrollContainers(touch_scroll, .{ .x = rl.GetMouseWheelMoveV().x * 2, .y = rl.GetMouseWheelMoveV().y * 2 }, rl.GetFrameTime());

        if (comptime builtin.mode == .Debug) {
            if (rl.IsKeyPressed(rl.KEY_H))
                clay.setDebugModeEnabled(!clay.isDebugModeEnabled());
        }
    }

    pub fn beginLayout(self: *App) void {
        _ = self.frame_arena.reset(.retain_capacity);
        self.events.clearRetainingCapacity();
        self.interaction.hot = null;

        const ids = clay.getPointerOverIds();

        var top_interactive: ?clay.ElementId = null;

        var i = ids.len;
        while (i > 0) {
            i -= 1;

            if (self.interactive_ids.contains(ids[i].id)) {
                top_interactive = ids[i];
                break;
            }
        }

        self.interaction.top_hovered = top_interactive;

        // key events
        var key = rl.GetKeyPressed();
        while (key != 0) : (key = rl.GetKeyPressed()) {
            self.events.append(self.alloc, .{ .key_pressed = key }) catch {};
        }

        clay.beginLayout();
    }

    pub fn endLayout(self: *App, root: anytype) void {
        toWidget(root).render();
        self.render_commands = clay.endLayout();
    }

    pub fn render(self: *App) !void {
        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(rl.WHITE);
        if (self.render_commands) |cmds| try renderer.clayRaylibRender(cmds, self.alloc);
        if (comptime builtin.mode == .Debug) rl.DrawFPS(0, 0);
    }

    fn alloc_widget(self: *App, comptime T: type, cfg: T) *T {
        const data = self.frame_arena.allocator().create(T) catch @panic("OOM");
        data.* = cfg;
        return data;
    }

    fn toWidget(child: anytype) Widget {
        const T = @TypeOf(child);

        if (T == Widget) return child;

        switch (@typeInfo(T)) {
            .pointer => {
                const Child = @typeInfo(T).pointer.child;

                if (@hasField(Child, "widget")) {
                    return child.widget;
                }
            },

            .@"struct", .@"union", .@"enum" => {
                if (@hasField(T, "widget")) {
                    return child.widget;
                }
            },

            else => {},
        }

        @compileError(
            "expected Widget or a type with a .widget field, got " ++ @typeName(T),
        );
    }

    fn appendChildren(alloc: std.mem.Allocator, list: *std.ArrayList(Widget), child: anytype) void {
        const T = @TypeOf(child);

        if (T == Widget) {
            list.append(alloc, child) catch unreachable;
            return;
        }

        switch (@typeInfo(T)) {
            .pointer => |p| {
                if (p.size == .slice) {
                    for (child) |elem| {
                        appendChildren(alloc, list, elem);
                    }
                    return;
                }

                const Child = p.child;
                if (@typeInfo(Child) == .@"struct" and
                    @hasField(Child, "widget"))
                {
                    list.append(alloc, child.widget) catch unreachable;
                    return;
                }
            },

            .@"struct" => {
                if (@hasField(T, "widget")) {
                    list.append(alloc, child.widget) catch unreachable;
                    return;
                }

                const fields = std.meta.fields(T);

                inline for (fields, 0..) |_, i| {
                    appendChildren(alloc, list, child[i]);
                }
                return;
            },

            else => {},
        }

        @compileError("unsupported child type: " ++ @typeName(T));
    }

    fn dupe(self: *App, children: anytype) []const Widget {
        var list = std.ArrayList(Widget).initCapacity(
            self.frame_arena.allocator(),
            32,
        ) catch @panic("OOM");

        appendChildren(
            self.frame_arena.allocator(),
            &list,
            children,
        );

        return list.toOwnedSlice(self.frame_arena.allocator()) catch @panic("OOM");
    }

    pub fn Row(self: *App, id: clay.ElementId, cfg: RowWidget, children: anytype) Widget {
        const data = self.alloc_widget(RowWidget, cfg);
        return .{ .id = id, .app = self, .data = data, .renderFn = RowWidget.render, .children = self.dupe(children) };
    }

    pub fn Column(self: *App, id: clay.ElementId, cfg: ColumnWidget, children: anytype) Widget {
        const data = self.alloc_widget(ColumnWidget, cfg);
        return .{ .id = id, .app = self, .data = data, .renderFn = ColumnWidget.render, .children = self.dupe(children) };
    }

    pub fn Text(self: *App, id: clay.ElementId, cfg: TextWidget) Widget {
        const data = self.alloc_widget(TextWidget, cfg);
        return .{ .id = id, .app = self, .data = data, .renderFn = TextWidget.render };
    }

    pub fn Image(self: *App, id: clay.ElementId, cfg: ImageWidget) Widget {
        const data = self.alloc_widget(ImageWidget, cfg);
        return .{ .id = id, .app = self, .data = data, .renderFn = ImageWidget.render };
    }

    pub fn Button(self: *App, id: clay.ElementId, cfg: ButtonWidget, children: anytype) *ButtonWidget {
        const data = self.alloc_widget(ButtonWidget, cfg);
        data.widget = .{ .id = id, .app = self, .data = data, .renderFn = ButtonWidget.render, .children = self.dupe(children) };
        self.interactive_ids.put(id.id, {}) catch unreachable;
        return data;
    }

    pub fn Slider(self: *App, id: clay.ElementId, cfg: SliderWidget) *SliderWidget {
        const data = self.alloc_widget(SliderWidget, cfg);
        data.widget = .{ .id = id, .app = self, .data = data, .renderFn = SliderWidget.render };
        self.interactive_ids.put(id.id, {}) catch unreachable;
        return data;
    }

    pub fn Scroll(self: *App, id: clay.ElementId, cfg: ScrollWidget, children: anytype) *ScrollWidget {
        const data = self.alloc_widget(ScrollWidget, cfg);
        data.widget = .{ .id = id, .app = self, .data = data, .renderFn = ScrollWidget.render, .children = self.dupe(children) };
        self.interactive_ids.put(id.id, {}) catch unreachable;
        return data;
    }

    pub fn TextBox(self: *App, id: clay.ElementId, cfg: *TextBoxWidget, children: anytype) *TextBoxWidget {
        cfg.widget = .{ .id = id, .app = self, .data = cfg, .renderFn = TextBoxWidget.render, .children = self.dupe(children) };
        self.interactive_ids.put(id.id, {}) catch unreachable;
        return cfg;
    }

    pub fn Dropdown(self: *App, id: clay.ElementId, cfg: *DropdownWidget) *DropdownWidget {
        cfg.widget = .{ .id = id, .app = self, .data = cfg, .renderFn = DropdownWidget.render };
        self.interactive_ids.put(id.id, {}) catch unreachable;
        return cfg;
    }

    pub fn Progress(self: *App, id: clay.ElementId, cfg: ProgressBarWidget) *ProgressBarWidget {
        const data = self.alloc_widget(ProgressBarWidget, cfg);
        data.widget = .{ .id = id, .app = self, .data = data, .renderFn = ProgressBarWidget.render };
        return data;
    }

    pub fn uninit(self: *App) void {
        Harffbuzz.uninit(self.alloc);
        self.alloc.free(self.title);
        self.frame_arena.deinit();
        self.events.deinit(self.alloc);
        self.interactive_ids.clearAndFree();
        self.alloc.free(self.memory);
        rl.CloseWindow();
        rl.CloseAudioDevice();
    }
};

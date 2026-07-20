const std = @import("std");
pub const clay = @import("zclay");
const renderer = @import("renderer.zig");
const rl = @import("raylib");
const Color = @import("color.zig").Color;
const Palette = @import("color.zig").Palette;
const builtin = @import("builtin");

const RowWidget = @import("widgets/row.zig").RowWidget;
const ColumnWidget = @import("widgets/column.zig").ColumnWidget;
const ScrollWidget = @import("widgets/scroll.zig").ScrollWidget;
const ButtonWidget = @import("widgets/button.zig").ButtonWidget;
const ImageWidget = @import("widgets/image.zig").ImageWidget;
const TextWidget = @import("widgets/text.zig").TextWidget;
const SliderWidget = @import("widgets/slider.zig").SliderWidget;
const TextBoxWidget = @import("widgets/textbox.zig").TextBoxWidget;
const DropdownWidget = @import("widgets/dropdown.zig").DropdownWidget;

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

export fn logRaylib(level: rl.callba, [*c]const u8) void {
    switch (level) {
        .
    }
    std.process.exit(1);
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
        const width = if (builtin.abi.isAndroid()) ray.GetScreenWidth() else default_width;
        const height = if (builtin.abi.isAndroid()) ray.GetScreenHeight() else default_height;
        ray.SetTraceLogCallback(callback: ?*const fn (c_int, [*c]const u8, [*c]struct___va_list_tag_1) void)
        if (builtin.abi.isAndroid()) {
            ray.SetConfigFlags(ray.FLAG_WINDOW_HIGHDPI);
        } else {
            ray.SetConfigFlags(ray.FLAG_WINDOW_RESIZABLE);
        }

        ray.InitWindow(width, height, c_path);
        ray.InitAudioDevice();
        ray.SetTargetFPS(ray.GetMonitorRefreshRate(ray.GetCurrentMonitor()));

        const memory = try alloc.alloc(u8, clay.minMemorySize());
        _ = clay.initialize(.init(memory), .{ .h = @floatFromInt(ray.GetScreenHeight()), .w = @floatFromInt(ray.GetScreenWidth()) }, .{ .error_handler_function = logClayError, .user_data = null });
        clay.setMeasureTextFunction(void, {}, renderer.measureText);
        return .{
            .title = c_path,
            .width = ray.GetScreenWidth(),
            .height = ray.GetScreenHeight(),
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

    pub fn loadFont(self: *App, file_data: []const u8, font_id: u16, font_size: i32) !void {
        try renderer.loadFont(self.alloc, font_id, file_data, font_size);
    }

    pub fn interactImpl(self: *App, id: clay.ElementId, release_anywhere: bool) enum { mouse_hovered, mouse_pressed, mouse_released, none } {
        const is_hovered =
            self.interaction.top_hovered != null and
            self.interaction.top_hovered.?.id == id.id;

        const pressed = ray.IsMouseButtonPressed(ray.MOUSE_LEFT_BUTTON);
        const down = ray.IsMouseButtonDown(ray.MOUSE_LEFT_BUTTON);
        const released = ray.IsMouseButtonReleased(ray.MOUSE_LEFT_BUTTON);

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
        return ray.WindowShouldClose();
    }

    pub fn update(self: *App) void {
        self.width = ray.GetRenderWidth();
        self.height = ray.GetRenderHeight();
        clay.setLayoutDimensions(.{ .w = @floatFromInt(self.width), .h = @floatFromInt(self.height) });
        clay.setPointerState(.{ .x = ray.GetMousePosition().x, .y = ray.GetMousePosition().y }, ray.IsMouseButtonDown(ray.MOUSE_BUTTON_LEFT));
        const touch_scroll = builtin.abi.isAndroid();
        clay.updateScrollContainers(touch_scroll, .{ .x = ray.GetMouseWheelMoveV().x * 2, .y = ray.GetMouseWheelMoveV().y * 2 }, ray.GetFrameTime());

        if (comptime builtin.mode == .Debug) {
            if (ray.IsKeyPressed(ray.KEY_H))
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
        var key = ray.GetKeyPressed();
        while (key != 0) : (key = ray.GetKeyPressed()) {
            self.events.append(self.alloc, .{ .key_pressed = key }) catch {};
        }

        clay.beginLayout();
    }

    pub fn endLayout(self: *App, root: anytype) void {
        toWidget(root).render();
        self.render_commands = clay.endLayout();
    }

    pub fn render(self: *App) !void {
        ray.BeginDrawing();
        defer ray.EndDrawing();
        ray.ClearBackground(ray.WHITE);
        if (self.render_commands) |cmds| try renderer.clayRaylibRender(cmds, self.alloc);
        if (comptime builtin.mode == .Debug) ray.DrawFPS(0, 0);
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

    pub fn uninit(self: *App) void {
        self.alloc.free(self.title);
        self.frame_arena.deinit();
        self.events.deinit(self.alloc);
        self.interactive_ids.clearAndFree();
        self.alloc.free(self.memory);
        ray.CloseWindow();
        ray.CloseAudioDevice();
    }
};

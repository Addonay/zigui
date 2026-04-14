const std = @import("std");
const common = @import("../../common.zig");
const keyboard = @import("../keyboard.zig");
const types = @import("../types.zig");
const ui_input = @import("../../../input.zig");
const clipboard = @import("clipboard.zig");
const display = @import("display.zig");
const event = @import("event.zig");
const xim_handler = @import("xim_handler.zig");
const window = @import("window.zig");
const xdg_desktop_portal = @import("../xdg_desktop_portal.zig");

pub const X11Backend = struct {
    allocator: std.mem.Allocator,
    display: display.X11Display,
    windows: std.ArrayListUnmanaged(window.X11Window) = .empty,
    events: ui_input.EventQueue = .{},
    clipboard: clipboard.ClipboardState = .{},
    xim: xim_handler.XimState = .{},
    active_window: ?display.c.Window = null,
    appearance: types.LinuxWindowAppearance = .light,
    button_layout: types.LinuxWindowButtonLayout = .{},

    pub fn init(allocator: std.mem.Allocator, options: common.WindowOptions) !X11Backend {
        const display_name = std.c.getenv("DISPLAY") orelse return error.DisplayUnavailable;
        var x11_display = try display.X11Display.open(display_name);
        errdefer x11_display.close();

        const x11_window = try window.X11Window.create(allocator, &x11_display, options);
        errdefer {
            var owned_window = x11_window;
            owned_window.destroy(&x11_display);
        }

        var backend = X11Backend{
            .allocator = allocator,
            .display = x11_display,
            .windows = .empty,
            .xim = detectXimState(
                getenvSlice("LC_CTYPE") orelse getenvSlice("LANG") orelse "C",
                getenvSlice("XMODIFIERS"),
            ),
            .active_window = x11_window.handle,
        };
        const visual_settings = xdg_desktop_portal.currentVisualSettings(allocator);
        backend.appearance = visual_settings.appearance;
        backend.button_layout = visual_settings.button_layout;
        errdefer backend.windows.deinit(allocator);
        try backend.windows.append(allocator, x11_window);
        return backend;
    }

    pub fn deinit(self: *X11Backend) void {
        for (self.windows.items) |*owned_window| owned_window.destroy(&self.display);
        self.windows.deinit(self.allocator);
        self.events.deinit(self.allocator);
        self.display.close();
    }

    pub fn run(self: *X11Backend) !void {
        var raw_event: display.c.XEvent = undefined;
        while (self.windows.items.len != 0) {
            _ = display.c.XNextEvent(self.display.handle, &raw_event);
            const target = event.windowHandle(&raw_event);
            const decoded = event.decode(&raw_event);

            if (self.windowPtr(target)) |owned_window| {
                if (event.requestsClose(decoded, owned_window.wm_delete_window)) {
                    self.events.push(self.allocator, .{
                        .window = .{
                            .window_id = target,
                            .kind = .close_requested,
                        },
                    }) catch {};
                    try self.closeWindow(target);
                    continue;
                }

                switch (decoded) {
                    .configure => |configure| {
                        owned_window.width = configure.width;
                        owned_window.height = configure.height;
                        self.events.push(self.allocator, .{
                            .window = .{
                                .window_id = target,
                                .kind = .resize,
                                .width = configure.width,
                                .height = configure.height,
                                .scale_factor = 1.0,
                            },
                        }) catch {};
                    },
                    .focus_in => {
                        self.active_window = target;
                        self.syncWindowFocusState(target);
                        self.events.push(self.allocator, .{
                            .window = .{
                                .window_id = target,
                                .kind = .focus,
                                .focused = true,
                            },
                        }) catch {};
                    },
                    .focus_out => {
                        if (self.active_window != null and self.active_window.? == target) {
                            self.active_window = null;
                        }
                        owned_window.setActive(false);
                        self.events.push(self.allocator, .{
                            .window = .{
                                .window_id = target,
                                .kind = .focus,
                                .focused = false,
                            },
                        }) catch {};
                    },
                    .enter => {
                        owned_window.setHovered(true);
                        self.events.push(self.allocator, .{
                            .window = .{
                                .window_id = target,
                                .kind = .hover,
                                .hovered = true,
                            },
                        }) catch {};
                    },
                    .leave => {
                        owned_window.setHovered(false);
                        self.events.push(self.allocator, .{
                            .window = .{
                                .window_id = target,
                                .kind = .hover,
                                .hovered = false,
                            },
                        }) catch {};
                    },
                    .key_press => |key_event| {
                        self.events.push(self.allocator, .{
                            .key = .{
                                .window_id = target,
                                .key_code = key_event.key_code,
                                .pressed = true,
                                .modifiers = modifierMaskFromXState(key_event.state),
                                .time_ms = key_event.time_ms,
                            },
                        }) catch {};
                    },
                    .key_release => |key_event| {
                        self.events.push(self.allocator, .{
                            .key = .{
                                .window_id = target,
                                .key_code = key_event.key_code,
                                .pressed = false,
                                .modifiers = modifierMaskFromXState(key_event.state),
                                .time_ms = key_event.time_ms,
                            },
                        }) catch {};
                    },
                    .button_press => |button_event| {
                        if (scrollDelta(button_event.button)) |delta| {
                            self.events.push(self.allocator, .{
                                .pointer = .{
                                    .window_id = target,
                                    .phase = .scroll,
                                    .x = button_event.x,
                                    .y = button_event.y,
                                    .scroll_x = delta.x,
                                    .scroll_y = delta.y,
                                    .continuous = false,
                                    .time_ms = button_event.time_ms,
                                },
                            }) catch {};
                        } else {
                            self.events.push(self.allocator, .{
                                .pointer = .{
                                    .window_id = target,
                                    .phase = .button,
                                    .x = button_event.x,
                                    .y = button_event.y,
                                    .button = pointerButtonFromX11(button_event.button),
                                    .pressed = true,
                                    .time_ms = button_event.time_ms,
                                },
                            }) catch {};
                        }
                    },
                    .button_release => |button_event| {
                        if (scrollDelta(button_event.button) != null) continue;
                        self.events.push(self.allocator, .{
                            .pointer = .{
                                .window_id = target,
                                .phase = .button,
                                .x = button_event.x,
                                .y = button_event.y,
                                .button = pointerButtonFromX11(button_event.button),
                                .pressed = false,
                                .time_ms = button_event.time_ms,
                            },
                        }) catch {};
                    },
                    .motion => |motion_event| {
                        self.events.push(self.allocator, .{
                            .pointer = .{
                                .window_id = target,
                                .phase = .move,
                                .x = motion_event.x,
                                .y = motion_event.y,
                                .time_ms = motion_event.time_ms,
                            },
                        }) catch {};
                    },
                    else => {},
                }
            }
        }
    }

    pub fn name(self: *const X11Backend) []const u8 {
        _ = self;
        return "linux-x11";
    }

    pub fn compositorName(self: *const X11Backend) []const u8 {
        _ = self;
        return "x11";
    }

    pub fn services(self: *const X11Backend) common.PlatformServices {
        const supports_ime = self.xim.availability != .unavailable;
        return .{
            .backend = .linux_x11,
            .supports_ime = supports_ime,
            .supports_clipboard = true,
            .supports_gpu_rendering = false,
            .supports_multiple_windows = true,
        };
    }

    pub fn diagnostics(self: *const X11Backend) common.Diagnostics {
        return .{
            .backend_name = "linux-x11",
            .window_system = "X11",
            .renderer = "unbound",
            .note = if (self.xim.supportsPreedit())
                "X11 fallback backend is active with XIM preedit support configured."
            else
                "X11 fallback backend is active.",
        };
    }

    pub fn keyboardInfo(self: *const X11Backend) keyboard.KeyboardInfo {
        return .{
            .compose_enabled = self.xim.availability != .unavailable,
        };
    }

    pub fn snapshot(self: *const X11Backend) types.LinuxRuntimeSnapshot {
        return .{
            .compositor_name = self.compositorName(),
            .keyboard = self.keyboardInfo(),
            .clipboard = .{
                .available = self.clipboard.has_clipboard,
                .has_text = self.clipboard.hasData(.clipboard),
                .mime_type = if (self.clipboard.hasData(.clipboard)) "text/plain;charset=utf-8" else null,
            },
            .primary_selection = .{
                .available = self.clipboard.has_primary_selection,
                .has_text = self.clipboard.hasData(.primary),
                .mime_type = if (self.clipboard.hasData(.primary)) "text/plain;charset=utf-8" else null,
            },
            .appearance = self.appearance,
            .button_layout = self.button_layout,
            .display_count = 1,
            .window_count = self.windowCount(),
            .active_window = self.activeWindowInfo(),
        };
    }

    pub fn setCursorStyle(self: *X11Backend, cursor_kind: common.Cursor) void {
        for (self.windows.items) |*owned_window| owned_window.applyCursor(&self.display, cursor_kind);
    }

    pub fn writeTextToClipboard(
        self: *X11Backend,
        kind: types.LinuxClipboardKind,
        text: []const u8,
    ) !void {
        self.clipboard.write(switch (kind) {
            .primary => .primary,
            .clipboard => .clipboard,
        }, text);
    }

    pub fn readTextFromClipboardAlloc(
        self: *X11Backend,
        kind: types.LinuxClipboardKind,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        const clipboard_kind = switch (kind) {
            .primary => clipboard.ClipboardKind.primary,
            .clipboard => clipboard.ClipboardKind.clipboard,
        };
        if (!self.clipboard.hasData(clipboard_kind)) return error.NoClipboardText;
        return allocator.dupe(u8, self.clipboard.read(clipboard_kind));
    }

    pub fn displayInfosAlloc(
        self: *const X11Backend,
        allocator: std.mem.Allocator,
    ) ![]types.LinuxDisplayInfo {
        const infos = try allocator.alloc(types.LinuxDisplayInfo, 1);
        infos[0] = self.display.snapshot();
        return infos;
    }

    pub fn windowInfosAlloc(
        self: *const X11Backend,
        allocator: std.mem.Allocator,
    ) ![]types.LinuxWindowInfo {
        const count = self.windowCount();
        const infos = try allocator.alloc(types.LinuxWindowInfo, count);
        var index: usize = 0;
        for (self.windows.items) |*owned_window| {
            if (owned_window.close_requested) continue;
            infos[index] = owned_window.snapshot();
            index += 1;
        }
        return infos;
    }

    pub fn drainEventsAlloc(
        self: *X11Backend,
        allocator: std.mem.Allocator,
    ) ![]ui_input.InputEvent {
        return self.events.drainAlloc(allocator);
    }

    pub fn openWindow(self: *X11Backend, options: common.WindowOptions) !usize {
        const owned_window = try window.X11Window.create(self.allocator, &self.display, options);
        try self.windows.append(self.allocator, owned_window);
        self.active_window = owned_window.handle;
        self.syncWindowFocusState(owned_window.handle);
        return owned_window.handle;
    }

    pub fn closeWindow(self: *X11Backend, handle: display.c.Window) !void {
        const index = self.windowIndex(handle) orelse return error.WindowNotFound;
        var owned_window = self.windows.orderedRemove(index);
        owned_window.close_requested = true;
        owned_window.destroy(&self.display);

        if (self.active_window != null and self.active_window.? == handle) {
            self.active_window = if (self.windows.items.len != 0) self.windows.items[self.windows.items.len - 1].handle else null;
            if (self.active_window) |next_handle| self.syncWindowFocusState(next_handle);
        }
    }

    pub fn setWindowTitle(self: *X11Backend, handle: display.c.Window, title: []const u8) !void {
        const owned_window = self.windowPtr(handle) orelse return error.WindowNotFound;
        try owned_window.setTitle(&self.display, title);
    }

    pub fn requestWindowDecorations(
        self: *X11Backend,
        handle: display.c.Window,
        decorations: common.WindowDecorations,
    ) !void {
        const owned_window = self.windowPtr(handle) orelse return error.WindowNotFound;
        try owned_window.requestDecorations(&self.display, decorations);
    }

    pub fn showWindowMenu(self: *X11Backend, handle: display.c.Window, x: f32, y: f32) !void {
        _ = self;
        _ = handle;
        _ = x;
        _ = y;
    }

    pub fn startWindowMove(self: *X11Backend, handle: display.c.Window) !void {
        _ = self;
        _ = handle;
    }

    pub fn startWindowResize(
        self: *X11Backend,
        handle: display.c.Window,
        edge: common.ResizeEdge,
    ) !void {
        _ = self;
        _ = handle;
        _ = edge;
    }

    pub fn windowDecorations(self: *const X11Backend, handle: display.c.Window) common.Decorations {
        return if (self.windowConstPtr(handle)) |owned_window|
            owned_window.actual_decorations
        else
            .server;
    }

    pub fn windowControls(self: *const X11Backend, handle: display.c.Window) common.WindowControls {
        return if (self.windowConstPtr(handle)) |owned_window|
            owned_window.window_controls
        else
            .{};
    }

    pub fn setClientInset(self: *X11Backend, handle: display.c.Window, inset: u32) !void {
        const owned_window = self.windowPtr(handle) orelse return error.WindowNotFound;
        owned_window.setClientInset(inset);
    }

    pub fn activeWindowInfo(self: *const X11Backend) ?types.LinuxWindowInfo {
        if (self.active_window) |handle| {
            if (self.windowConstPtr(handle)) |owned_window| return owned_window.snapshot();
        }
        for (self.windows.items) |*owned_window| {
            if (!owned_window.close_requested) return owned_window.snapshot();
        }
        return null;
    }

    fn windowCount(self: *const X11Backend) usize {
        var count: usize = 0;
        for (self.windows.items) |owned_window| {
            if (!owned_window.close_requested) count += 1;
        }
        return count;
    }

    fn windowIndex(self: *const X11Backend, handle: display.c.Window) ?usize {
        for (self.windows.items, 0..) |owned_window, index| {
            if (owned_window.handle == handle) return index;
        }
        return null;
    }

    fn windowPtr(self: *X11Backend, handle: display.c.Window) ?*window.X11Window {
        const index = self.windowIndex(handle) orelse return null;
        return &self.windows.items[index];
    }

    fn windowConstPtr(self: *const X11Backend, handle: display.c.Window) ?*const window.X11Window {
        const index = self.windowIndex(handle) orelse return null;
        return &self.windows.items[index];
    }

    fn syncWindowFocusState(self: *X11Backend, active_handle: display.c.Window) void {
        for (self.windows.items) |*owned_window| {
            owned_window.setActive(owned_window.handle == active_handle);
        }
    }
};

fn getenvSlice(name: [*:0]const u8) ?[]const u8 {
    const value = std.c.getenv(name) orelse return null;
    return std.mem.span(value);
}

fn detectXimState(locale_name: []const u8, xmodifiers: ?[]const u8) xim_handler.XimState {
    var state = xim_handler.XimState{};
    if (std.mem.eql(u8, locale_name, "C")) return state;
    if (xmodifiers != null) {
        state.enablePreedit(locale_name);
    } else {
        state.enableBasic(locale_name);
    }
    return state;
}

fn modifierMaskFromXState(state: u32) ui_input.ModifierMask {
    return .{
        .shift = (state & @as(u32, display.c.ShiftMask)) != 0,
        .ctrl = (state & @as(u32, display.c.ControlMask)) != 0,
        .alt = (state & @as(u32, display.c.Mod1Mask)) != 0,
        .super = (state & @as(u32, display.c.Mod4Mask)) != 0,
        .caps_lock = (state & @as(u32, display.c.LockMask)) != 0,
        .num_lock = (state & @as(u32, display.c.Mod2Mask)) != 0,
    };
}

fn pointerButtonFromX11(button: u32) ?ui_input.PointerButton {
    return switch (button) {
        1 => .left,
        2 => .middle,
        3 => .right,
        else => .other,
    };
}

fn scrollDelta(button: u32) ?struct { x: f32, y: f32 } {
    return switch (button) {
        4 => .{ .x = 0, .y = -1 },
        5 => .{ .x = 0, .y = 1 },
        6 => .{ .x = -1, .y = 0 },
        7 => .{ .x = 1, .y = 0 },
        else => null,
    };
}

const vtable = common.RuntimeVTable{
    .deinit = runtimeDeinit,
    .run = runtimeRun,
    .name = runtimeName,
    .services = runtimeServices,
    .diagnostics = runtimeDiagnostics,
    .snapshot = runtimeSnapshot,
    .display_infos_alloc = runtimeDisplayInfosAlloc,
    .window_infos_alloc = runtimeWindowInfosAlloc,
    .drain_events_alloc = runtimeDrainEventsAlloc,
    .set_cursor_style = runtimeSetCursorStyle,
    .write_text_to_clipboard = runtimeWriteTextToClipboard,
    .read_text_from_clipboard_alloc = runtimeReadTextFromClipboardAlloc,
    .open_uri = runtimeOpenUri,
    .reveal_path = runtimeRevealPath,
    .prompt_for_paths_alloc = runtimePromptForPathsAlloc,
    .prompt_for_new_path_alloc = runtimePromptForNewPathAlloc,
    .open_window = runtimeOpenWindow,
    .close_window = runtimeCloseWindow,
    .set_window_title = runtimeSetWindowTitle,
    .request_window_decorations = runtimeRequestWindowDecorations,
    .show_window_menu = runtimeShowWindowMenu,
    .start_window_move = runtimeStartWindowMove,
    .start_window_resize = runtimeStartWindowResize,
    .window_decorations = runtimeWindowDecorations,
    .window_controls = runtimeWindowControls,
    .set_client_inset = runtimeSetClientInset,
};

pub fn createRuntime(allocator: std.mem.Allocator, options: common.WindowOptions) !common.Runtime {
    const backend = try allocator.create(X11Backend);
    errdefer allocator.destroy(backend);

    backend.* = try X11Backend.init(allocator, options);
    return .{
        .allocator = allocator,
        .ptr = backend,
        .vtable = &vtable,
    };
}

fn runtimeDeinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const backend: *X11Backend = @ptrCast(@alignCast(ptr));
    backend.deinit();
    allocator.destroy(backend);
}

fn runtimeRun(ptr: *anyopaque) anyerror!void {
    const backend: *X11Backend = @ptrCast(@alignCast(ptr));
    try backend.run();
}

fn runtimeName(ptr: *const anyopaque) []const u8 {
    const backend: *const X11Backend = @ptrCast(@alignCast(ptr));
    return backend.name();
}

fn runtimeServices(ptr: *const anyopaque) common.PlatformServices {
    const backend: *const X11Backend = @ptrCast(@alignCast(ptr));
    return backend.services();
}

fn runtimeDiagnostics(ptr: *const anyopaque) common.Diagnostics {
    const backend: *const X11Backend = @ptrCast(@alignCast(ptr));
    return backend.diagnostics();
}

fn runtimeSnapshot(ptr: *const anyopaque) common.RuntimeSnapshot {
    const backend: *const X11Backend = @ptrCast(@alignCast(ptr));
    return backend.snapshot();
}

fn runtimeDisplayInfosAlloc(
    ptr: *const anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]common.DisplayInfo {
    const backend: *const X11Backend = @ptrCast(@alignCast(ptr));
    return try backend.displayInfosAlloc(allocator);
}

fn runtimeWindowInfosAlloc(
    ptr: *const anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]common.WindowInfo {
    const backend: *const X11Backend = @ptrCast(@alignCast(ptr));
    return try backend.windowInfosAlloc(allocator);
}

fn runtimeDrainEventsAlloc(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]ui_input.InputEvent {
    const backend: *X11Backend = @ptrCast(@alignCast(ptr));
    return try backend.drainEventsAlloc(allocator);
}

fn runtimeSetCursorStyle(ptr: *anyopaque, cursor_kind: common.Cursor) void {
    const backend: *X11Backend = @ptrCast(@alignCast(ptr));
    backend.setCursorStyle(cursor_kind);
}

fn runtimeWriteTextToClipboard(
    ptr: *anyopaque,
    kind: common.ClipboardKind,
    text: []const u8,
) anyerror!void {
    const backend: *X11Backend = @ptrCast(@alignCast(ptr));
    try backend.writeTextToClipboard(kind, text);
}

fn runtimeReadTextFromClipboardAlloc(
    ptr: *anyopaque,
    kind: common.ClipboardKind,
    allocator: std.mem.Allocator,
) anyerror![]u8 {
    const backend: *X11Backend = @ptrCast(@alignCast(ptr));
    return try backend.readTextFromClipboardAlloc(kind, allocator);
}

fn runtimeOpenUri(ptr: *anyopaque, uri: []const u8) anyerror!void {
    _ = ptr;
    _ = uri;
    return error.LaunchCommandUnavailable;
}

fn runtimeRevealPath(ptr: *anyopaque, path: []const u8) anyerror!void {
    _ = ptr;
    _ = path;
    return error.LaunchCommandUnavailable;
}

fn runtimePromptForPathsAlloc(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    options: common.PathPromptOptions,
) anyerror!?common.PathList {
    _ = ptr;
    _ = allocator;
    _ = options;
    return error.FileDialogUnavailable;
}

fn runtimePromptForNewPathAlloc(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    options: common.PathPromptOptions,
) anyerror!?[]u8 {
    _ = ptr;
    _ = allocator;
    _ = options;
    return error.FileDialogUnavailable;
}

fn runtimeOpenWindow(ptr: *anyopaque, options: common.WindowOptions) anyerror!usize {
    const backend: *X11Backend = @ptrCast(@alignCast(ptr));
    return try backend.openWindow(options);
}

fn runtimeCloseWindow(ptr: *anyopaque, handle: usize) anyerror!void {
    const backend: *X11Backend = @ptrCast(@alignCast(ptr));
    try backend.closeWindow(@intCast(handle));
}

fn runtimeSetWindowTitle(ptr: *anyopaque, handle: usize, title: []const u8) anyerror!void {
    const backend: *X11Backend = @ptrCast(@alignCast(ptr));
    try backend.setWindowTitle(@intCast(handle), title);
}

fn runtimeRequestWindowDecorations(
    ptr: *anyopaque,
    handle: usize,
    decorations: common.WindowDecorations,
) anyerror!void {
    const backend: *X11Backend = @ptrCast(@alignCast(ptr));
    try backend.requestWindowDecorations(@intCast(handle), decorations);
}

fn runtimeShowWindowMenu(ptr: *anyopaque, handle: usize, x: f32, y: f32) anyerror!void {
    const backend: *X11Backend = @ptrCast(@alignCast(ptr));
    try backend.showWindowMenu(@intCast(handle), x, y);
}

fn runtimeStartWindowMove(ptr: *anyopaque, handle: usize) anyerror!void {
    const backend: *X11Backend = @ptrCast(@alignCast(ptr));
    try backend.startWindowMove(@intCast(handle));
}

fn runtimeStartWindowResize(
    ptr: *anyopaque,
    handle: usize,
    edge: common.ResizeEdge,
) anyerror!void {
    const backend: *X11Backend = @ptrCast(@alignCast(ptr));
    try backend.startWindowResize(@intCast(handle), edge);
}

fn runtimeWindowDecorations(ptr: *const anyopaque, handle: usize) common.Decorations {
    const backend: *const X11Backend = @ptrCast(@alignCast(ptr));
    return backend.windowDecorations(@intCast(handle));
}

fn runtimeWindowControls(ptr: *const anyopaque, handle: usize) common.WindowControls {
    const backend: *const X11Backend = @ptrCast(@alignCast(ptr));
    return backend.windowControls(@intCast(handle));
}

fn runtimeSetClientInset(ptr: *anyopaque, handle: usize, inset: u32) anyerror!void {
    const backend: *X11Backend = @ptrCast(@alignCast(ptr));
    try backend.setClientInset(@intCast(handle), inset);
}

test "xim detection prefers preedit when XMODIFIERS is set" {
    const xim = detectXimState("en_US.UTF-8", "@im=ibus");
    try std.testing.expectEqual(xim_handler.XimAvailability.preedit, xim.availability);
}

test "xim detection falls back to basic callbacks without an XIM server" {
    const xim = detectXimState("en_US.UTF-8", null);
    try std.testing.expectEqual(xim_handler.XimAvailability.basic, xim.availability);
}

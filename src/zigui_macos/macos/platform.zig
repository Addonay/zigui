const std = @import("std");
const common = @import("../../zigui/common.zig");
const input = @import("../../zigui/input.zig");
const dispatcher = @import("dispatcher.zig");
const display = @import("display.zig");
const display_link = @import("display_link.zig");
const events = @import("events.zig");
const keyboard = @import("keyboard.zig");
const metal_renderer = @import("metal_renderer.zig");
const pasteboard = @import("pasteboard.zig");
const screen_capture = @import("screen_capture.zig");
const text_system = @import("text_system.zig");
const window = @import("window.zig");
const window_appearance = @import("window_appearance.zig");

pub const MacPlatform = struct {
    allocator: std.mem.Allocator,
    options: common.WindowOptions,
    dispatcher: dispatcher.Dispatcher = .{},
    display: display.DisplayState = .{},
    display_link: display_link.DisplayLink = .{},
    events: events.EventState = .{},
    keyboard: keyboard.KeyboardState = .{},
    keyboard_layout: keyboard.MacKeyboardLayout = .{},
    keyboard_mapper: keyboard.MacKeyboardMapper = .{},
    renderer: metal_renderer.MetalRenderer = .{},
    general_pasteboard: pasteboard.Pasteboard = .{ .kind = .general },
    find_pasteboard: pasteboard.Pasteboard = .{ .kind = .find },
    screen_capture: screen_capture.ScreenCaptureState = .{},
    text_system: text_system.MacTextSystem = .{},
    windows: window.WindowState = .{},
    appearance: window_appearance.MacWindowAppearance = .aqua,
    button_layout: common.WindowButtonLayout = .{
        .raw = ":close,minimize,maximize",
        .controls_on_left = true,
    },
    open_uri_requests: usize = 0,
    reveal_path_requests: usize = 0,
    path_prompt_requests: usize = 0,
    new_path_prompt_requests: usize = 0,
    last_open_uri: ?[]u8 = null,
    last_revealed_path: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator, options: common.WindowOptions) !MacPlatform {
        var display_state = display.DisplayState.init(options);
        var renderer = try metal_renderer.MetalRenderer.init(allocator, .{});
        errdefer renderer.deinit(allocator);
        try renderer.resize(options.width, options.height);

        const keyboard_layout = keyboard.MacKeyboardLayout.new();
        const keyboard_mapper = keyboard.MacKeyboardMapper.new(keyboard_layout.id);
        const display_link_instance = try display_link.DisplayLink.new(
            @as(u64, @intCast(display_state.primaryDisplay().id)),
            null,
            null,
        );

        var platform = MacPlatform{
            .allocator = allocator,
            .options = options,
            .display = display_state,
            .display_link = display_link_instance,
            .keyboard_layout = keyboard_layout,
            .keyboard_mapper = keyboard_mapper,
            .renderer = renderer,
            .general_pasteboard = pasteboard.Pasteboard.general(),
            .find_pasteboard = pasteboard.Pasteboard.find(),
            .appearance = .aqua,
        };

        platform.windows.setAppearance(platform.appearance);
        platform.screen_capture.refresh(&platform.display);
        return platform;
    }

    pub fn deinit(self: *MacPlatform) void {
        if (self.last_open_uri) |uri| self.allocator.free(uri);
        if (self.last_revealed_path) |path| self.allocator.free(path);
        self.text_system.deinit(self.allocator);
        self.windows.deinit(self.allocator);
        self.events.deinit(self.allocator);
        self.dispatcher.deinit(self.allocator);
        self.general_pasteboard.deinit(self.allocator);
        self.find_pasteboard.deinit(self.allocator);
        self.renderer.deinit(self.allocator);
        self.display.deinit(self.allocator);
        self.display_link.deinit();
    }

    pub fn run(self: *MacPlatform) !void {
        const tasks = self.dispatcher.drain();
        for (tasks) |task| {
            switch (task.kind) {
                .wake, .redraw => self.renderer.markDrawable(),
                .quit => while (self.windows.count() != 0) {
                    const active = self.windows.activeWindowInfo() orelse break;
                    try self.closeWindow(active.id);
                },
            }
        }

        if (self.display_link.running and self.windows.count() != 0) {
            self.display_link.requestFrame();
            self.renderer.markDrawable();
        }
    }

    pub fn name(self: *const MacPlatform) []const u8 {
        _ = self;
        return "macos-native";
    }

    pub fn services(self: *const MacPlatform) common.PlatformServices {
        return .{
            .backend = .macos_native,
            .supports_ime = self.keyboard.snapshot().compose_enabled,
            .supports_clipboard = true,
            .supports_gpu_rendering = self.renderer.supportsGpuRendering(),
            .supports_multiple_windows = true,
        };
    }

    pub fn diagnostics(self: *const MacPlatform) common.Diagnostics {
        return .{
            .backend_name = "macos-native",
            .window_system = "AppKit",
            .renderer = self.renderer.backendName(),
            .note = "macOS backend tracks logical windows, display links, pasteboards, screen capture, and a stateful Metal renderer. Cocoa interop is still modeled in Zig.",
        };
    }

    pub fn snapshot(self: *const MacPlatform) common.RuntimeSnapshot {
        return .{
            .compositor_name = "appkit",
            .keyboard = self.keyboard.snapshot(),
            .clipboard = self.general_pasteboard.snapshot(),
            .primary_selection = self.find_pasteboard.snapshot(),
            .appearance = self.appearance.toCommon(),
            .button_layout = self.button_layout,
            .display_count = self.display.count(),
            .window_count = self.windows.count(),
            .active_window = self.windows.activeWindowInfo(),
        };
    }

    pub fn displayInfosAlloc(self: *const MacPlatform, allocator: std.mem.Allocator) ![]common.DisplayInfo {
        return try self.display.infosAlloc(allocator);
    }

    pub fn windowInfosAlloc(self: *const MacPlatform, allocator: std.mem.Allocator) ![]common.WindowInfo {
        return try self.windows.infosAlloc(allocator);
    }

    pub fn drainEventsAlloc(self: *MacPlatform, allocator: std.mem.Allocator) ![]input.InputEvent {
        return try self.events.drainAlloc(allocator);
    }

    pub fn setCursorStyle(self: *MacPlatform, cursor_kind: common.Cursor) void {
        self.windows.setCursor(cursor_kind);
    }

    pub fn writeTextToClipboard(
        self: *MacPlatform,
        kind: common.ClipboardKind,
        text: []const u8,
    ) !void {
        switch (kind) {
            .clipboard => try self.general_pasteboard.writeTextToClipboard(self.allocator, kind, text),
            .primary => try self.find_pasteboard.writeTextToClipboard(self.allocator, kind, text),
        }
    }

    pub fn readTextFromClipboardAlloc(
        self: *MacPlatform,
        kind: common.ClipboardKind,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        return switch (kind) {
            .clipboard => try self.general_pasteboard.readTextFromClipboardAlloc(self.allocator, kind, allocator),
            .primary => try self.find_pasteboard.readTextFromClipboardAlloc(self.allocator, kind, allocator),
        };
    }

    pub fn openUri(self: *MacPlatform, uri: []const u8) !void {
        self.open_uri_requests += 1;
        try replaceOwnedSlice(self.allocator, &self.last_open_uri, uri);
    }

    pub fn revealPath(self: *MacPlatform, path: []const u8) !void {
        self.reveal_path_requests += 1;
        try replaceOwnedSlice(self.allocator, &self.last_revealed_path, path);
    }

    pub fn promptForPathsAlloc(
        self: *MacPlatform,
        allocator: std.mem.Allocator,
        options: common.PathPromptOptions,
    ) !?common.PathList {
        _ = allocator;
        _ = options;
        self.path_prompt_requests += 1;
        return null;
    }

    pub fn promptForNewPathAlloc(
        self: *MacPlatform,
        allocator: std.mem.Allocator,
        options: common.PathPromptOptions,
    ) !?[]u8 {
        _ = allocator;
        _ = options;
        self.new_path_prompt_requests += 1;
        return null;
    }

    pub fn openWindow(self: *MacPlatform, options: common.WindowOptions) !usize {
        const previous_active = self.windows.activeWindowInfo();
        const handle = try self.windows.open(self.allocator, options);
        self.windows.setAppearance(self.appearance);
        if (!self.display_link.running) {
            self.display_link.start() catch {};
        }
        self.renderer.markDrawable();
        self.display_link.requestFrame();
        self.screen_capture.refresh(&self.display);

        if (previous_active) |active| {
            self.events.pushWindowEvent(self.allocator, .{
                .window_id = active.id,
                .kind = .focus,
                .focused = false,
            }) catch {};
        }

        self.events.pushWindowEvent(self.allocator, .{
            .window_id = handle,
            .kind = .resize,
            .width = options.width,
            .height = options.height,
            .scale_factor = 1.0,
        }) catch {};
        self.events.pushWindowEvent(self.allocator, .{
            .window_id = handle,
            .kind = .focus,
            .focused = true,
        }) catch {};

        return handle;
    }

    pub fn closeWindow(self: *MacPlatform, handle: usize) !void {
        try self.windows.close(self.allocator, handle);
        self.events.pushWindowEvent(self.allocator, .{
            .window_id = handle,
            .kind = .close_requested,
        }) catch {};

        if (self.windows.activeWindowInfo()) |active| {
            self.events.pushWindowEvent(self.allocator, .{
                .window_id = active.id,
                .kind = .focus,
                .focused = true,
            }) catch {};
        }

        if (self.windows.count() == 0) {
            self.display_link.stop() catch {};
        }

        self.renderer.markDrawable();
    }

    pub fn setWindowTitle(self: *MacPlatform, handle: usize, title: []const u8) !void {
        const managed = self.windows.getMut(handle) orelse return error.WindowNotFound;
        try managed.setTitle(self.allocator, title);
    }

    pub fn requestWindowDecorations(
        self: *MacPlatform,
        handle: usize,
        decorations: common.WindowDecorations,
    ) !void {
        const managed = self.windows.getMut(handle) orelse return error.WindowNotFound;
        managed.requestDecorations(decorations);
    }

    pub fn showWindowMenu(self: *MacPlatform, handle: usize, x: f32, y: f32) !void {
        const managed = self.windows.getMut(handle) orelse return error.WindowNotFound;
        managed.requestMenu(x, y);
    }

    pub fn startWindowMove(self: *MacPlatform, handle: usize) !void {
        const managed = self.windows.getMut(handle) orelse return error.WindowNotFound;
        managed.requestMove();
    }

    pub fn startWindowResize(self: *MacPlatform, handle: usize, edge: common.ResizeEdge) !void {
        const managed = self.windows.getMut(handle) orelse return error.WindowNotFound;
        managed.requestResize(edge);
    }

    pub fn windowDecorations(self: *const MacPlatform, handle: usize) common.Decorations {
        return if (self.windows.get(handle)) |managed|
            managed.actual_decorations
        else
            .server;
    }

    pub fn windowControls(self: *const MacPlatform, handle: usize) common.WindowControls {
        return if (self.windows.get(handle)) |managed|
            managed.window_controls
        else
            .{};
    }

    pub fn setClientInset(self: *MacPlatform, handle: usize, inset: u32) !void {
        const managed = self.windows.getMut(handle) orelse return error.WindowNotFound;
        managed.setClientInset(inset);
    }
};

pub const MacOSBackend = MacPlatform;

pub fn createRuntime(allocator: std.mem.Allocator, options: common.WindowOptions) !common.Runtime {
    const backend = try allocator.create(MacPlatform);
    errdefer allocator.destroy(backend);

    backend.* = try MacPlatform.init(allocator, options);
    return .{
        .allocator = allocator,
        .ptr = backend,
        .vtable = &vtable,
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

fn runtimeDeinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    backend.deinit();
    allocator.destroy(backend);
}

fn runtimeRun(ptr: *anyopaque) anyerror!void {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    try backend.run();
}

fn runtimeName(ptr: *const anyopaque) []const u8 {
    const backend: *const MacPlatform = @ptrCast(@alignCast(ptr));
    return backend.name();
}

fn runtimeServices(ptr: *const anyopaque) common.PlatformServices {
    const backend: *const MacPlatform = @ptrCast(@alignCast(ptr));
    return backend.services();
}

fn runtimeDiagnostics(ptr: *const anyopaque) common.Diagnostics {
    const backend: *const MacPlatform = @ptrCast(@alignCast(ptr));
    return backend.diagnostics();
}

fn runtimeSnapshot(ptr: *const anyopaque) common.RuntimeSnapshot {
    const backend: *const MacPlatform = @ptrCast(@alignCast(ptr));
    return backend.snapshot();
}

fn runtimeDisplayInfosAlloc(
    ptr: *const anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]common.DisplayInfo {
    const backend: *const MacPlatform = @ptrCast(@alignCast(ptr));
    return try backend.displayInfosAlloc(allocator);
}

fn runtimeWindowInfosAlloc(
    ptr: *const anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]common.WindowInfo {
    const backend: *const MacPlatform = @ptrCast(@alignCast(ptr));
    return try backend.windowInfosAlloc(allocator);
}

fn runtimeDrainEventsAlloc(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]input.InputEvent {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    return try backend.drainEventsAlloc(allocator);
}

fn runtimeSetCursorStyle(ptr: *anyopaque, cursor_kind: common.Cursor) void {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    backend.setCursorStyle(cursor_kind);
}

fn runtimeWriteTextToClipboard(
    ptr: *anyopaque,
    kind: common.ClipboardKind,
    text: []const u8,
) anyerror!void {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    try backend.writeTextToClipboard(kind, text);
}

fn runtimeReadTextFromClipboardAlloc(
    ptr: *anyopaque,
    kind: common.ClipboardKind,
    allocator: std.mem.Allocator,
) anyerror![]u8 {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    return try backend.readTextFromClipboardAlloc(kind, allocator);
}

fn runtimeOpenUri(ptr: *anyopaque, uri: []const u8) anyerror!void {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    try backend.openUri(uri);
}

fn runtimeRevealPath(ptr: *anyopaque, path: []const u8) anyerror!void {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    try backend.revealPath(path);
}

fn runtimePromptForPathsAlloc(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    options: common.PathPromptOptions,
) anyerror!?common.PathList {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    return try backend.promptForPathsAlloc(allocator, options);
}

fn runtimePromptForNewPathAlloc(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    options: common.PathPromptOptions,
) anyerror!?[]u8 {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    return try backend.promptForNewPathAlloc(allocator, options);
}

fn runtimeOpenWindow(ptr: *anyopaque, options: common.WindowOptions) anyerror!usize {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    return try backend.openWindow(options);
}

fn runtimeCloseWindow(ptr: *anyopaque, handle: usize) anyerror!void {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    try backend.closeWindow(handle);
}

fn runtimeSetWindowTitle(ptr: *anyopaque, handle: usize, title: []const u8) anyerror!void {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    try backend.setWindowTitle(handle, title);
}

fn runtimeRequestWindowDecorations(
    ptr: *anyopaque,
    handle: usize,
    decorations: common.WindowDecorations,
) anyerror!void {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    try backend.requestWindowDecorations(handle, decorations);
}

fn runtimeShowWindowMenu(
    ptr: *anyopaque,
    handle: usize,
    x: f32,
    y: f32,
) anyerror!void {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    try backend.showWindowMenu(handle, x, y);
}

fn runtimeStartWindowMove(ptr: *anyopaque, handle: usize) anyerror!void {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    try backend.startWindowMove(handle);
}

fn runtimeStartWindowResize(
    ptr: *anyopaque,
    handle: usize,
    edge: common.ResizeEdge,
) anyerror!void {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    try backend.startWindowResize(handle, edge);
}

fn runtimeWindowDecorations(ptr: *const anyopaque, handle: usize) common.Decorations {
    const backend: *const MacPlatform = @ptrCast(@alignCast(ptr));
    return backend.windowDecorations(handle);
}

fn runtimeWindowControls(ptr: *const anyopaque, handle: usize) common.WindowControls {
    const backend: *const MacPlatform = @ptrCast(@alignCast(ptr));
    return backend.windowControls(handle);
}

fn runtimeSetClientInset(ptr: *anyopaque, handle: usize, inset: u32) anyerror!void {
    const backend: *MacPlatform = @ptrCast(@alignCast(ptr));
    try backend.setClientInset(handle, inset);
}

fn replaceOwnedSlice(
    allocator: std.mem.Allocator,
    slot: *?[]u8,
    value: []const u8,
) !void {
    if (slot.*) |existing| allocator.free(existing);
    slot.* = try allocator.dupe(u8, value);
}

test "macos backend reports metadata and tracks clipboard and windows" {
    var backend = try MacPlatform.init(std.testing.allocator, .{});
    defer backend.deinit();

    try std.testing.expectEqualStrings("macos-native", backend.name());
    const services = backend.services();
    try std.testing.expectEqual(common.BackendKind.macos_native, services.backend);
    try std.testing.expect(services.supports_ime);
    try std.testing.expect(services.supports_clipboard);
    try std.testing.expect(services.supports_gpu_rendering);
    try std.testing.expect(services.supports_multiple_windows);

    const diagnostics = backend.diagnostics();
    try std.testing.expectEqualStrings("macos-native", diagnostics.backend_name);
    try std.testing.expectEqualStrings("AppKit", diagnostics.window_system);
    try std.testing.expectEqualStrings("metal", diagnostics.renderer);

    const snapshot = backend.snapshot();
    try std.testing.expectEqual(@as(usize, 1), snapshot.display_count);
    try std.testing.expectEqual(@as(usize, 0), snapshot.window_count);

    try backend.writeTextToClipboard(.clipboard, "hello");
    const text = try backend.readTextFromClipboardAlloc(.clipboard, std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("hello", text);

    const handle = try backend.openWindow(.{ .title = "demo" });
    try std.testing.expectEqual(@as(usize, 1), backend.windows.count());
    try std.testing.expectEqual(handle, backend.windows.activeWindowInfo().?.id);
    try backend.closeWindow(handle);
}

test "macos runtime creation exposes the backend contract" {
    var runtime = try createRuntime(std.testing.allocator, .{});
    defer runtime.deinit();

    try std.testing.expectEqualStrings("macos-native", runtime.name());
    const services = runtime.services();
    try std.testing.expectEqual(common.BackendKind.macos_native, services.backend);
    try std.testing.expect(services.supports_gpu_rendering);
    try std.testing.expectEqualStrings("metal", runtime.diagnostics().renderer);
}

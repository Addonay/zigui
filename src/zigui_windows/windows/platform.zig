const std = @import("std");
const common = @import("../../zigui/common.zig");
const clipboard = @import("clipboard.zig");
const direct_manipulation = @import("direct_manipulation.zig");
const directx_devices = @import("directx_devices.zig");
const dispatcher = @import("dispatcher.zig");
const display = @import("display.zig");
const direct_write = @import("direct_write.zig");
const directx_renderer = @import("directx_renderer.zig");
const destination_list = @import("destination_list.zig");
const events = @import("events.zig");
const keyboard = @import("keyboard.zig");
const system_settings = @import("system_settings.zig");
const vsync = @import("vsync.zig");
const window = @import("window.zig");

pub const WindowsBackend = struct {
    allocator: std.mem.Allocator,
    directx_devices: directx_devices.DirectXDevices = .{},
    renderer: directx_renderer.DirectXRenderer = .{},
    dispatcher: dispatcher.Dispatcher = .{},
    display: display.Display = .{},
    direct_manipulation: direct_manipulation.DirectManipulationHandler = .{},
    events: events.EventState = .{},
    keyboard: keyboard.KeyboardState = .{},
    direct_write: direct_write.DirectWriteTextSystemConfig = .{},
    jump_list: destination_list.JumpList = .{},
    system_settings: system_settings.WindowsSystemSettings = .{},
    vsync: vsync.VSyncProvider = .{},
    windows: window.WindowState = .{},
    appearance: common.WindowAppearance = .light,
    clipboard: clipboard.ClipboardState = .{},

    pub fn init(allocator: std.mem.Allocator, options: common.WindowOptions) !WindowsBackend {
        var backend = WindowsBackend{
            .allocator = allocator,
        };
        backend.system_settings = system_settings.WindowsSystemSettings.init(allocator);
        backend.appearance = backend.system_settings.appearance;
        backend.directx_devices = try directx_devices.DirectXDevices.init(allocator);
        backend.renderer = try directx_renderer.DirectXRenderer.init(allocator, &backend.directx_devices, false);
        backend.direct_manipulation = .{ .scale_factor = backend.display.scale_factor };
        try backend.renderer.resize(options.width, options.height);
        _ = try backend.openWindow(options);
        return backend;
    }

    pub fn deinit(self: *WindowsBackend) void {
        self.renderer.deinit(self.allocator);
        self.jump_list.deinit(self.allocator);
        self.direct_manipulation.deinit(self.allocator);
        self.clipboard.deinit(self.allocator);
        self.windows.deinit(self.allocator);
        self.events.deinit(self.allocator);
        self.dispatcher.deinit(self.allocator);
        self.directx_devices.deinit(self.allocator);
    }

    pub fn run(self: *WindowsBackend) !void {
        const tasks = self.dispatcher.drain();
        for (tasks) |task| {
            switch (task.kind) {
                .wake, .redraw => {},
                .quit => while (self.windows.count() != 0) {
                    const active = self.windows.activeWindowInfo() orelse break;
                    try self.closeWindow(active.id);
                },
            }
        }
    }

    pub fn name(self: *const WindowsBackend) []const u8 {
        _ = self;
        return "windows-native";
    }

    pub fn services(self: *const WindowsBackend) common.PlatformServices {
        return .{
            .backend = .windows_native,
            .supports_ime = self.direct_write.supports_ime,
            .supports_clipboard = true,
            .supports_gpu_rendering = self.renderer.supportsGpuRendering(),
            .supports_multiple_windows = true,
        };
    }

    pub fn diagnostics(self: *const WindowsBackend) common.Diagnostics {
        return .{
            .backend_name = "windows-native",
            .window_system = "Win32",
            .renderer = self.renderer.backendName(),
            .note = "Windows runtime now tracks native device snapshots, renderer state, logical windows, clipboard access, shell launch helpers, and file dialogs through backend modules that mirror GPUI's Windows split.",
        };
    }

    pub fn snapshot(self: *const WindowsBackend) common.RuntimeSnapshot {
        return .{
            .compositor_name = "win32",
            .keyboard = self.keyboard.snapshot(),
            .clipboard = .{
                .available = true,
                .has_text = self.clipboard.clipboard_text != null,
                .mime_type = if (self.clipboard.clipboard_text != null) "text/plain;charset=utf-8" else null,
            },
            .primary_selection = .{},
            .appearance = self.appearance,
            .button_layout = .{},
            .display_count = self.display.count(),
            .window_count = self.windows.count(),
            .active_window = self.windows.activeWindowInfo(),
        };
    }

    pub fn displayInfosAlloc(self: *const WindowsBackend, allocator: std.mem.Allocator) ![]common.DisplayInfo {
        return try self.display.infosAlloc(allocator);
    }

    pub fn windowInfosAlloc(self: *const WindowsBackend, allocator: std.mem.Allocator) ![]common.WindowInfo {
        return try self.windows.infosAlloc(allocator);
    }

    pub fn drainEventsAlloc(self: *WindowsBackend, allocator: std.mem.Allocator) ![]@import("../../zigui/input.zig").InputEvent {
        return try self.events.drainAlloc(allocator);
    }

    pub fn setCursorStyle(self: *WindowsBackend, cursor_kind: common.Cursor) void {
        self.windows.setCursor(cursor_kind);
    }

    pub fn writeTextToClipboard(
        self: *WindowsBackend,
        kind: common.ClipboardKind,
        text: []const u8,
    ) !void {
        try self.clipboard.writeTextToClipboard(self.allocator, kind, text);
    }

    pub fn readTextFromClipboardAlloc(
        self: *WindowsBackend,
        kind: common.ClipboardKind,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        return try self.clipboard.readTextFromClipboardAlloc(self.allocator, kind, allocator);
    }

    pub fn openUri(self: *WindowsBackend, uri: []const u8) !void {
        try clipboard.openUri(self.allocator, uri);
    }

    pub fn revealPath(self: *WindowsBackend, path: []const u8) !void {
        try clipboard.revealPath(self.allocator, path);
    }

    pub fn promptForPathsAlloc(
        self: *WindowsBackend,
        allocator: std.mem.Allocator,
        options: common.PathPromptOptions,
    ) !?common.PathList {
        _ = self;
        return try clipboard.promptForPathsAlloc(allocator, options);
    }

    pub fn promptForNewPathAlloc(
        self: *WindowsBackend,
        allocator: std.mem.Allocator,
        options: common.PathPromptOptions,
    ) !?[]u8 {
        _ = self;
        return try clipboard.promptForNewPathAlloc(allocator, options);
    }

    pub fn openWindow(self: *WindowsBackend, options: common.WindowOptions) !usize {
        const previous_active = self.windows.activeWindowInfo();
        const handle = try self.windows.open(self.allocator, options);
        self.direct_manipulation.setScaleFactor(self.display.scale_factor);
        self.renderer.markDrawable();

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

    pub fn closeWindow(self: *WindowsBackend, handle: usize) !void {
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
            self.renderer.markDrawable();
        }
    }

    pub fn setWindowTitle(self: *WindowsBackend, handle: usize, title: []const u8) !void {
        const managed = self.windows.getMut(handle) orelse return error.WindowNotFound;
        try managed.setTitle(self.allocator, title);
    }

    pub fn requestWindowDecorations(
        self: *WindowsBackend,
        handle: usize,
        decorations: common.WindowDecorations,
    ) !void {
        const managed = self.windows.getMut(handle) orelse return error.WindowNotFound;
        managed.requestDecorations(decorations);
    }

    pub fn showWindowMenu(self: *WindowsBackend, handle: usize, x: f32, y: f32) !void {
        _ = self;
        _ = handle;
        _ = x;
        _ = y;
    }

    pub fn startWindowMove(self: *WindowsBackend, handle: usize) !void {
        _ = self;
        _ = handle;
    }

    pub fn startWindowResize(self: *WindowsBackend, handle: usize, edge: common.ResizeEdge) !void {
        _ = self;
        _ = handle;
        _ = edge;
    }

    pub fn windowDecorations(self: *const WindowsBackend, handle: usize) common.Decorations {
        return if (self.windows.get(handle)) |managed|
            managed.actual_decorations
        else
            .server;
    }

    pub fn windowControls(self: *const WindowsBackend, handle: usize) common.WindowControls {
        return if (self.windows.get(handle)) |managed|
            managed.window_controls
        else
            .{};
    }

    pub fn setClientInset(self: *WindowsBackend, handle: usize, inset: u32) !void {
        const managed = self.windows.getMut(handle) orelse return error.WindowNotFound;
        managed.setClientInset(inset);
    }
};

pub const WindowsPlatform = WindowsBackend;

pub fn createRuntime(allocator: std.mem.Allocator, options: common.WindowOptions) !common.Runtime {
    const backend = try allocator.create(WindowsBackend);
    errdefer allocator.destroy(backend);

    backend.* = try WindowsBackend.init(allocator, options);
    return .{
        .allocator = allocator,
        .ptr = backend,
        .vtable = &vtable,
    };
}

const ui_input = @import("../../zigui/input.zig");

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
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    backend.deinit();
    allocator.destroy(backend);
}

fn runtimeRun(ptr: *anyopaque) anyerror!void {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    try backend.run();
}

fn runtimeName(ptr: *const anyopaque) []const u8 {
    const backend: *const WindowsBackend = @ptrCast(@alignCast(ptr));
    return backend.name();
}

fn runtimeServices(ptr: *const anyopaque) common.PlatformServices {
    const backend: *const WindowsBackend = @ptrCast(@alignCast(ptr));
    return backend.services();
}

fn runtimeDiagnostics(ptr: *const anyopaque) common.Diagnostics {
    const backend: *const WindowsBackend = @ptrCast(@alignCast(ptr));
    return backend.diagnostics();
}

fn runtimeSnapshot(ptr: *const anyopaque) common.RuntimeSnapshot {
    const backend: *const WindowsBackend = @ptrCast(@alignCast(ptr));
    return backend.snapshot();
}

fn runtimeDisplayInfosAlloc(
    ptr: *const anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]common.DisplayInfo {
    const backend: *const WindowsBackend = @ptrCast(@alignCast(ptr));
    return try backend.displayInfosAlloc(allocator);
}

fn runtimeWindowInfosAlloc(
    ptr: *const anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]common.WindowInfo {
    const backend: *const WindowsBackend = @ptrCast(@alignCast(ptr));
    return try backend.windowInfosAlloc(allocator);
}

fn runtimeDrainEventsAlloc(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]ui_input.InputEvent {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    return try backend.drainEventsAlloc(allocator);
}

fn runtimeSetCursorStyle(ptr: *anyopaque, cursor_kind: common.Cursor) void {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    backend.setCursorStyle(cursor_kind);
}

fn runtimeWriteTextToClipboard(
    ptr: *anyopaque,
    kind: common.ClipboardKind,
    text: []const u8,
) anyerror!void {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    try backend.writeTextToClipboard(kind, text);
}

fn runtimeReadTextFromClipboardAlloc(
    ptr: *anyopaque,
    kind: common.ClipboardKind,
    allocator: std.mem.Allocator,
) anyerror![]u8 {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    return try backend.readTextFromClipboardAlloc(kind, allocator);
}

fn runtimeOpenUri(ptr: *anyopaque, uri: []const u8) anyerror!void {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    try backend.openUri(uri);
}

fn runtimeRevealPath(ptr: *anyopaque, path: []const u8) anyerror!void {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    try backend.revealPath(path);
}

fn runtimePromptForPathsAlloc(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    options: common.PathPromptOptions,
) anyerror!?common.PathList {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    return try backend.promptForPathsAlloc(allocator, options);
}

fn runtimePromptForNewPathAlloc(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    options: common.PathPromptOptions,
) anyerror!?[]u8 {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    return try backend.promptForNewPathAlloc(allocator, options);
}

fn runtimeOpenWindow(ptr: *anyopaque, options: common.WindowOptions) anyerror!usize {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    return try backend.openWindow(options);
}

fn runtimeCloseWindow(ptr: *anyopaque, handle: usize) anyerror!void {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    try backend.closeWindow(handle);
}

fn runtimeSetWindowTitle(ptr: *anyopaque, handle: usize, title: []const u8) anyerror!void {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    try backend.setWindowTitle(handle, title);
}

fn runtimeRequestWindowDecorations(
    ptr: *anyopaque,
    handle: usize,
    decorations: common.WindowDecorations,
) anyerror!void {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    try backend.requestWindowDecorations(handle, decorations);
}

fn runtimeShowWindowMenu(ptr: *anyopaque, handle: usize, x: f32, y: f32) anyerror!void {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    try backend.showWindowMenu(handle, x, y);
}

fn runtimeStartWindowMove(ptr: *anyopaque, handle: usize) anyerror!void {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    try backend.startWindowMove(handle);
}

fn runtimeStartWindowResize(
    ptr: *anyopaque,
    handle: usize,
    edge: common.ResizeEdge,
) anyerror!void {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    try backend.startWindowResize(handle, edge);
}

fn runtimeWindowDecorations(ptr: *const anyopaque, handle: usize) common.Decorations {
    const backend: *const WindowsBackend = @ptrCast(@alignCast(ptr));
    return backend.windowDecorations(handle);
}

fn runtimeWindowControls(ptr: *const anyopaque, handle: usize) common.WindowControls {
    const backend: *const WindowsBackend = @ptrCast(@alignCast(ptr));
    return backend.windowControls(handle);
}

fn runtimeSetClientInset(ptr: *anyopaque, handle: usize, inset: u32) anyerror!void {
    const backend: *WindowsBackend = @ptrCast(@alignCast(ptr));
    try backend.setClientInset(handle, inset);
}

test "windows backend wires devices renderer and initial window state" {
    var backend = try WindowsBackend.init(std.testing.allocator, .{
        .title = "demo",
        .width = 640,
        .height = 480,
    });
    defer backend.deinit();

    try std.testing.expectEqual(@as(usize, 1), backend.windows.count());
    try std.testing.expectEqual(@as(u32, 640), backend.renderer.width);
    try std.testing.expectEqual(@as(u32, 480), backend.renderer.height);
    try std.testing.expectEqualStrings("d3d12-pending", backend.renderer.backendName());
    try std.testing.expectEqual(backend.display.scale_factor, backend.direct_manipulation.scale_factor);

    const snapshot = backend.snapshot();
    try std.testing.expectEqual(@as(usize, 1), snapshot.window_count);
    try std.testing.expectEqual(backend.appearance, snapshot.appearance);
    try std.testing.expect(!backend.services().supports_gpu_rendering);
}

const std = @import("std");
const common = @import("../common.zig");
const keyboard = @import("keyboard.zig");
const types = @import("types.zig");
const xdg_desktop_portal = @import("xdg_desktop_portal.zig");
const ui_input = @import("../../input.zig");

pub const HeadlessBackend = struct {
    allocator: std.mem.Allocator,
    options: common.WindowOptions,
    appearance: types.LinuxWindowAppearance = .light,
    button_layout: types.LinuxWindowButtonLayout = .{},

    pub fn init(allocator: std.mem.Allocator, options: common.WindowOptions) HeadlessBackend {
        const visual_settings = xdg_desktop_portal.currentVisualSettings(allocator);
        return .{
            .allocator = allocator,
            .options = options,
            .appearance = visual_settings.appearance,
            .button_layout = visual_settings.button_layout,
        };
    }

    pub fn deinit(self: *HeadlessBackend) void {
        _ = self;
    }

    pub fn run(self: *HeadlessBackend) !void {
        _ = self;
    }

    pub fn name(self: *const HeadlessBackend) []const u8 {
        _ = self;
        return "linux-headless";
    }

    pub fn compositorName(self: *const HeadlessBackend) []const u8 {
        _ = self;
        return "headless";
    }

    pub fn services(self: *const HeadlessBackend) common.PlatformServices {
        _ = self;
        return .{
            .backend = .linux_headless,
            .supports_ime = false,
            .supports_clipboard = false,
            .supports_gpu_rendering = false,
            .supports_multiple_windows = false,
        };
    }

    pub fn diagnostics(self: *const HeadlessBackend) common.Diagnostics {
        _ = self;
        return .{
            .backend_name = "linux-headless",
            .window_system = "none",
            .renderer = "unbound",
            .note = "Headless runtime selected because no usable desktop display backend was available.",
        };
    }

    pub fn keyboardInfo(self: *const HeadlessBackend) keyboard.KeyboardInfo {
        _ = self;
        return .{};
    }

    pub fn snapshot(self: *const HeadlessBackend) types.LinuxRuntimeSnapshot {
        return .{
            .compositor_name = self.compositorName(),
            .keyboard = self.keyboardInfo(),
            .appearance = self.appearance,
            .button_layout = self.button_layout,
        };
    }

    pub fn setCursorStyle(self: *HeadlessBackend, cursor_kind: common.Cursor) void {
        _ = self;
        _ = cursor_kind;
    }

    pub fn writeTextToClipboard(
        self: *HeadlessBackend,
        kind: types.LinuxClipboardKind,
        text: []const u8,
    ) !void {
        _ = self;
        _ = kind;
        _ = text;
        return error.NoClipboardSupport;
    }

    pub fn readTextFromClipboardAlloc(
        self: *HeadlessBackend,
        kind: types.LinuxClipboardKind,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        _ = self;
        _ = kind;
        _ = allocator;
        return error.NoClipboardText;
    }

    pub fn displayInfosAlloc(
        self: *const HeadlessBackend,
        allocator: std.mem.Allocator,
    ) ![]types.LinuxDisplayInfo {
        _ = self;
        return allocator.alloc(types.LinuxDisplayInfo, 0);
    }

    pub fn windowInfosAlloc(
        self: *const HeadlessBackend,
        allocator: std.mem.Allocator,
    ) ![]types.LinuxWindowInfo {
        _ = self;
        return allocator.alloc(types.LinuxWindowInfo, 0);
    }

    pub fn drainEventsAlloc(
        self: *HeadlessBackend,
        allocator: std.mem.Allocator,
    ) ![]ui_input.InputEvent {
        _ = self;
        return allocator.alloc(ui_input.InputEvent, 0);
    }

    pub fn openWindow(self: *HeadlessBackend, options: common.WindowOptions) !usize {
        _ = self;
        _ = options;
        return error.WindowingUnavailable;
    }

    pub fn closeWindow(self: *HeadlessBackend, handle: usize) !void {
        _ = self;
        _ = handle;
        return error.WindowingUnavailable;
    }

    pub fn setWindowTitle(self: *HeadlessBackend, handle: usize, title: []const u8) !void {
        _ = self;
        _ = handle;
        _ = title;
        return error.WindowingUnavailable;
    }

    pub fn requestWindowDecorations(
        self: *HeadlessBackend,
        handle: usize,
        decorations: common.WindowDecorations,
    ) !void {
        _ = self;
        _ = handle;
        _ = decorations;
        return error.WindowingUnavailable;
    }

    pub fn showWindowMenu(self: *HeadlessBackend, handle: usize, x: f32, y: f32) !void {
        _ = self;
        _ = handle;
        _ = x;
        _ = y;
        return error.WindowingUnavailable;
    }

    pub fn startWindowMove(self: *HeadlessBackend, handle: usize) !void {
        _ = self;
        _ = handle;
        return error.WindowingUnavailable;
    }

    pub fn startWindowResize(self: *HeadlessBackend, handle: usize, edge: common.ResizeEdge) !void {
        _ = self;
        _ = handle;
        _ = edge;
        return error.WindowingUnavailable;
    }

    pub fn windowDecorations(self: *const HeadlessBackend, handle: usize) common.Decorations {
        _ = self;
        _ = handle;
        return .server;
    }

    pub fn windowControls(self: *const HeadlessBackend, handle: usize) common.WindowControls {
        _ = self;
        _ = handle;
        return .{};
    }

    pub fn setClientInset(self: *HeadlessBackend, handle: usize, inset: u32) !void {
        _ = self;
        _ = handle;
        _ = inset;
        return error.WindowingUnavailable;
    }
};

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
    const backend = try allocator.create(HeadlessBackend);
    errdefer allocator.destroy(backend);

    backend.* = HeadlessBackend.init(allocator, options);
    return .{
        .allocator = allocator,
        .ptr = backend,
        .vtable = &vtable,
    };
}

fn runtimeDeinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const backend: *HeadlessBackend = @ptrCast(@alignCast(ptr));
    backend.deinit();
    allocator.destroy(backend);
}

fn runtimeRun(ptr: *anyopaque) anyerror!void {
    const backend: *HeadlessBackend = @ptrCast(@alignCast(ptr));
    try backend.run();
}

fn runtimeName(ptr: *const anyopaque) []const u8 {
    const backend: *const HeadlessBackend = @ptrCast(@alignCast(ptr));
    return backend.name();
}

fn runtimeServices(ptr: *const anyopaque) common.PlatformServices {
    const backend: *const HeadlessBackend = @ptrCast(@alignCast(ptr));
    return backend.services();
}

fn runtimeDiagnostics(ptr: *const anyopaque) common.Diagnostics {
    const backend: *const HeadlessBackend = @ptrCast(@alignCast(ptr));
    return backend.diagnostics();
}

fn runtimeSnapshot(ptr: *const anyopaque) common.RuntimeSnapshot {
    const backend: *const HeadlessBackend = @ptrCast(@alignCast(ptr));
    return backend.snapshot();
}

fn runtimeDisplayInfosAlloc(
    ptr: *const anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]common.DisplayInfo {
    const backend: *const HeadlessBackend = @ptrCast(@alignCast(ptr));
    return try backend.displayInfosAlloc(allocator);
}

fn runtimeWindowInfosAlloc(
    ptr: *const anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]common.WindowInfo {
    const backend: *const HeadlessBackend = @ptrCast(@alignCast(ptr));
    return try backend.windowInfosAlloc(allocator);
}

fn runtimeDrainEventsAlloc(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]ui_input.InputEvent {
    const backend: *HeadlessBackend = @ptrCast(@alignCast(ptr));
    return try backend.drainEventsAlloc(allocator);
}

fn runtimeSetCursorStyle(ptr: *anyopaque, cursor_kind: common.Cursor) void {
    const backend: *HeadlessBackend = @ptrCast(@alignCast(ptr));
    backend.setCursorStyle(cursor_kind);
}

fn runtimeWriteTextToClipboard(
    ptr: *anyopaque,
    kind: common.ClipboardKind,
    text: []const u8,
) anyerror!void {
    const backend: *HeadlessBackend = @ptrCast(@alignCast(ptr));
    try backend.writeTextToClipboard(kind, text);
}

fn runtimeReadTextFromClipboardAlloc(
    ptr: *anyopaque,
    kind: common.ClipboardKind,
    allocator: std.mem.Allocator,
) anyerror![]u8 {
    const backend: *HeadlessBackend = @ptrCast(@alignCast(ptr));
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
    const backend: *HeadlessBackend = @ptrCast(@alignCast(ptr));
    return try backend.openWindow(options);
}

fn runtimeCloseWindow(ptr: *anyopaque, handle: usize) anyerror!void {
    const backend: *HeadlessBackend = @ptrCast(@alignCast(ptr));
    try backend.closeWindow(handle);
}

fn runtimeSetWindowTitle(ptr: *anyopaque, handle: usize, title: []const u8) anyerror!void {
    const backend: *HeadlessBackend = @ptrCast(@alignCast(ptr));
    try backend.setWindowTitle(handle, title);
}

fn runtimeRequestWindowDecorations(
    ptr: *anyopaque,
    handle: usize,
    decorations: common.WindowDecorations,
) anyerror!void {
    const backend: *HeadlessBackend = @ptrCast(@alignCast(ptr));
    try backend.requestWindowDecorations(handle, decorations);
}

fn runtimeShowWindowMenu(ptr: *anyopaque, handle: usize, x: f32, y: f32) anyerror!void {
    const backend: *HeadlessBackend = @ptrCast(@alignCast(ptr));
    try backend.showWindowMenu(handle, x, y);
}

fn runtimeStartWindowMove(ptr: *anyopaque, handle: usize) anyerror!void {
    const backend: *HeadlessBackend = @ptrCast(@alignCast(ptr));
    try backend.startWindowMove(handle);
}

fn runtimeStartWindowResize(
    ptr: *anyopaque,
    handle: usize,
    edge: common.ResizeEdge,
) anyerror!void {
    const backend: *HeadlessBackend = @ptrCast(@alignCast(ptr));
    try backend.startWindowResize(handle, edge);
}

fn runtimeWindowDecorations(ptr: *const anyopaque, handle: usize) common.Decorations {
    const backend: *const HeadlessBackend = @ptrCast(@alignCast(ptr));
    return backend.windowDecorations(handle);
}

fn runtimeWindowControls(ptr: *const anyopaque, handle: usize) common.WindowControls {
    const backend: *const HeadlessBackend = @ptrCast(@alignCast(ptr));
    return backend.windowControls(handle);
}

fn runtimeSetClientInset(ptr: *anyopaque, handle: usize, inset: u32) anyerror!void {
    const backend: *HeadlessBackend = @ptrCast(@alignCast(ptr));
    try backend.setClientInset(handle, inset);
}

test "headless snapshot reports an empty desktop state" {
    const backend = HeadlessBackend.init(std.testing.allocator, .{});
    const snapshot = backend.snapshot();

    try std.testing.expectEqualStrings("headless", snapshot.compositor_name);
    try std.testing.expectEqual(@as(usize, 0), snapshot.display_count);
    try std.testing.expectEqual(@as(usize, 0), snapshot.window_count);
}

const std = @import("std");
const entity = @import("entity.zig");
const input = @import("input.zig");
const platform = @import("platform.zig");
const renderer = @import("renderer.zig");
const theme = @import("theme.zig");
const window = @import("window.zig");

pub const AppConfig = struct {
    name: []const u8 = "zigui-app",
    renderer: renderer.RendererConfig = .{},
    window: platform.WindowOptions = .{},
    theme: theme.Theme = .{},
    open_default_window: bool = true,
    log_runtime: bool = true,
};

pub const AppContext = struct {
    gpa: std.mem.Allocator,
    entities: *entity.EntityStore,
    windows: *std.ArrayListUnmanaged(window.Window),
    theme: *theme.Theme,
};

pub const Application = struct {
    allocator: std.mem.Allocator,
    config: AppConfig,
    entities: entity.EntityStore,
    windows: std.ArrayListUnmanaged(window.Window) = .empty,
    next_window_id: u64 = 1,
    runtime: ?platform.Runtime = null,
    active_theme: theme.Theme,

    pub fn init(allocator: std.mem.Allocator, config: AppConfig) Application {
        return .{
            .allocator = allocator,
            .config = config,
            .entities = entity.EntityStore.init(),
            .active_theme = config.theme,
        };
    }

    pub fn deinit(self: *Application) void {
        if (self.runtime) |*runtime| runtime.deinit();
        for (self.windows.items) |*win| win.deinit(self.allocator);
        self.windows.deinit(self.allocator);
        self.entities.deinit(self.allocator);
    }

    pub fn context(self: *Application) AppContext {
        return .{
            .gpa = self.allocator,
            .entities = &self.entities,
            .windows = &self.windows,
            .theme = &self.active_theme,
        };
    }

    pub fn openWindow(self: *Application, options: platform.WindowOptions) !window.WindowId {
        const window_id: window.WindowId = @enumFromInt(self.next_window_id);
        self.next_window_id += 1;

        var win = try window.Window.init(self.allocator, window_id, options);
        errdefer win.deinit(self.allocator);
        win.theme = self.active_theme;

        if (self.runtime) |*runtime| {
            _ = try runtime.openWindow(win.options);
            win.state = .visible;
        }

        _ = try self.entities.create(self.allocator, "zigui.Window");
        try self.windows.append(self.allocator, win);
        return window_id;
    }

    pub fn getWindow(self: *Application, id: window.WindowId) ?*window.Window {
        for (self.windows.items) |*win| {
            if (win.id == id) return win;
        }
        return null;
    }

    pub fn primaryWindow(self: *Application) ?*window.Window {
        if (self.windows.items.len == 0) return null;
        return &self.windows.items[0];
    }

    pub fn diagnostics(self: *const Application) ?platform.Diagnostics {
        if (self.runtime) |runtime| return runtime.diagnostics();
        return null;
    }

    pub fn runtimeSnapshot(self: *const Application) ?platform.RuntimeSnapshot {
        if (self.runtime) |runtime| return runtime.snapshot();
        return null;
    }

    pub fn displayInfosAlloc(self: *Application, allocator: std.mem.Allocator) ![]platform.DisplayInfo {
        const runtime = self.runtime orelse return error.RuntimeUnavailable;
        return try runtime.displayInfosAlloc(allocator);
    }

    pub fn windowInfosAlloc(self: *Application, allocator: std.mem.Allocator) ![]platform.WindowInfo {
        const runtime = self.runtime orelse return error.RuntimeUnavailable;
        return try runtime.windowInfosAlloc(allocator);
    }

    pub fn drainInputEventsAlloc(self: *Application, allocator: std.mem.Allocator) ![]input.InputEvent {
        const runtime = self.runtime orelse return error.RuntimeUnavailable;
        return try runtime.drainEventsAlloc(allocator);
    }

    pub fn setCursorStyle(self: *Application, cursor_kind: platform.Cursor) !void {
        const runtime = self.runtime orelse return error.RuntimeUnavailable;
        runtime.setCursorStyle(cursor_kind);
    }

    pub fn writeTextToClipboard(
        self: *Application,
        kind: platform.ClipboardKind,
        text: []const u8,
    ) !void {
        const runtime = self.runtime orelse return error.RuntimeUnavailable;
        try runtime.writeTextToClipboard(kind, text);
    }

    pub fn readTextFromClipboardAlloc(
        self: *Application,
        kind: platform.ClipboardKind,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        const runtime = self.runtime orelse return error.RuntimeUnavailable;
        return try runtime.readTextFromClipboardAlloc(kind, allocator);
    }

    pub fn openUri(self: *Application, uri: []const u8) !void {
        const runtime = self.runtime orelse return error.RuntimeUnavailable;
        try runtime.openUri(uri);
    }

    pub fn revealPath(self: *Application, path: []const u8) !void {
        const runtime = self.runtime orelse return error.RuntimeUnavailable;
        try runtime.revealPath(path);
    }

    pub fn promptForPathsAlloc(
        self: *Application,
        allocator: std.mem.Allocator,
        options: platform.PathPromptOptions,
    ) !?platform.PathList {
        const runtime = self.runtime orelse return error.RuntimeUnavailable;
        return try runtime.promptForPathsAlloc(allocator, options);
    }

    pub fn promptForNewPathAlloc(
        self: *Application,
        allocator: std.mem.Allocator,
        options: platform.PathPromptOptions,
    ) !?[]u8 {
        const runtime = self.runtime orelse return error.RuntimeUnavailable;
        return try runtime.promptForNewPathAlloc(allocator, options);
    }

    pub fn closeWindow(self: *Application, id: window.WindowId) !void {
        const win = self.getWindow(id) orelse return error.WindowNotFound;
        if (self.runtime) |*runtime| {
            if (win.native_handle) |handle| try runtime.closeWindow(handle);
        }
        win.native_handle = null;
        win.state = .closed;
    }

    pub fn run(self: *Application) !void {
        if (self.windows.items.len == 0 and self.config.open_default_window) {
            _ = try self.openWindow(self.config.window);
        }
        if (self.windows.items.len == 0) return error.NoWindowsOpen;

        if (self.runtime == null) {
            self.runtime = try platform.createRuntime(self.allocator, self.windows.items[0].options);
            if (self.config.log_runtime) {
                const runtime_diagnostics = self.runtime.?.diagnostics();
                std.log.info(
                    "zigui runtime backend={s} window_system={s} renderer={s}",
                    .{
                        runtime_diagnostics.backend_name,
                        runtime_diagnostics.window_system,
                        runtime_diagnostics.renderer,
                    },
                );
                if (runtime_diagnostics.note.len != 0) {
                    std.log.info("{s}", .{runtime_diagnostics.note});
                }
            }

            const initial_handles = try self.runtime.?.windowInfosAlloc(self.allocator);
            defer self.allocator.free(initial_handles);
            if (self.windows.items.len != 0 and self.windows.items[0].native_handle == null and initial_handles.len != 0) {
                self.windows.items[0].native_handle = initial_handles[0].id;
            }
        }

        if (self.windows.items.len > 1 and !self.runtime.?.services().supports_multiple_windows) {
            return error.MultipleWindowsUnsupported;
        }

        for (self.windows.items, 0..) |*win, index| {
            if (win.state != .created) continue;
            if (index != 0) {
                win.native_handle = try self.runtime.?.openWindow(win.options);
            }
            win.state = .visible;
        }

        try self.runtime.?.run();
        for (self.windows.items) |*win| win.state = .closed;
    }
};

test "application creates a context backed by entity storage" {
    var app_instance = Application.init(std.testing.allocator, .{});
    defer app_instance.deinit();

    const cx = app_instance.context();
    try std.testing.expectEqual(std.testing.allocator, cx.gpa);
    try std.testing.expectEqual(@as(usize, 0), cx.entities.count());
    try std.testing.expectEqual(@as(usize, 0), cx.windows.items.len);
}

test "application can register a window before the runtime exists" {
    var app_instance = Application.init(std.testing.allocator, .{});
    defer app_instance.deinit();

    const id = try app_instance.openWindow(.{ .title = "hello" });
    const win = app_instance.getWindow(id).?;
    try std.testing.expectEqualStrings("hello", win.title());
    try std.testing.expectEqual(@as(usize, 1), app_instance.windows.items.len);
}

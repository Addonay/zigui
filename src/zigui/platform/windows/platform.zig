const builtin = @import("builtin");
const std = @import("std");
const common = @import("../common.zig");
const dispatcher = @import("dispatcher.zig");
const display = @import("display.zig");
const directx_renderer = @import("directx_renderer.zig");
const events = @import("events.zig");
const keyboard = @import("keyboard.zig");
const text_system = @import("text_system.zig");
const window = @import("window.zig");

pub const WindowsBackend = struct {
    allocator: std.mem.Allocator,
    dispatcher: dispatcher.Dispatcher = .{},
    display: display.Display = .{},
    events: events.EventState = .{},
    keyboard: keyboard.KeyboardState = .{},
    renderer: directx_renderer.DirectXRendererConfig = .{},
    text: text_system.TextSystemConfig = .{},
    windows: window.WindowState = .{},
    appearance: common.WindowAppearance = .light,
    clipboard_text: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator, options: common.WindowOptions) !WindowsBackend {
        var backend = WindowsBackend{
            .allocator = allocator,
        };
        backend.appearance = queryAppearance(allocator) catch .light;
        _ = try backend.openWindow(options);
        return backend;
    }

    pub fn deinit(self: *WindowsBackend) void {
        if (self.clipboard_text) |clipboard_text| self.allocator.free(clipboard_text);
        self.windows.deinit(self.allocator);
        self.events.deinit(self.allocator);
        self.dispatcher.deinit(self.allocator);
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
        _ = self;
        return .{
            .backend = .windows_native,
            .supports_ime = true,
            .supports_clipboard = true,
            .supports_gpu_rendering = false,
            .supports_multiple_windows = true,
        };
    }

    pub fn diagnostics(self: *const WindowsBackend) common.Diagnostics {
        _ = self;
        return .{
            .backend_name = "windows-native",
            .window_system = "Win32",
            .renderer = "unbound",
            .note = "Windows runtime now exposes runtime snapshots, logical windows, clipboard access, shell launch helpers, and file dialogs through native shell tools. A real HWND message loop and DirectX presentation path are still pending.",
        };
    }

    pub fn snapshot(self: *const WindowsBackend) common.RuntimeSnapshot {
        return .{
            .compositor_name = "win32",
            .keyboard = self.keyboard.snapshot(),
            .clipboard = .{
                .available = true,
                .has_text = self.clipboard_text != null,
                .mime_type = if (self.clipboard_text != null) "text/plain;charset=utf-8" else null,
            },
            .primary_selection = .{},
            .appearance = self.appearance,
            .button_layout = .{},
            .display_count = 1,
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

    pub fn drainEventsAlloc(self: *WindowsBackend, allocator: std.mem.Allocator) ![]@import("../../input.zig").InputEvent {
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
        if (kind == .primary) return error.NoClipboardSupport;

        const script = try clipboardWriteScript(self.allocator, text);
        defer self.allocator.free(script);
        try runPowerShellStatus(self.allocator, script);

        if (self.clipboard_text) |existing| self.allocator.free(existing);
        self.clipboard_text = try self.allocator.dupe(u8, text);
    }

    pub fn readTextFromClipboardAlloc(
        self: *WindowsBackend,
        kind: common.ClipboardKind,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        if (kind == .primary) return error.NoClipboardSupport;

        const stdout = try runPowerShellCapture(self.allocator, "Get-Clipboard -Raw");
        defer self.allocator.free(stdout);
        const trimmed = std.mem.trimRight(u8, stdout, "\r\n");
        if (trimmed.len == 0) return error.NoClipboardText;

        if (self.clipboard_text) |existing| self.allocator.free(existing);
        self.clipboard_text = try self.allocator.dupe(u8, trimmed);
        return try allocator.dupe(u8, trimmed);
    }

    pub fn openUri(self: *WindowsBackend, uri: []const u8) !void {
        const script = try startProcessScript(self.allocator, uri);
        defer self.allocator.free(script);
        try runPowerShellStatus(self.allocator, script);
    }

    pub fn revealPath(self: *WindowsBackend, path: []const u8) !void {
        const select_arg = try std.fmt.allocPrint(self.allocator, "/select,{s}", .{path});
        defer self.allocator.free(select_arg);

        const script = try explorerScript(self.allocator, select_arg);
        defer self.allocator.free(script);
        try runPowerShellStatus(self.allocator, script);
    }

    pub fn promptForPathsAlloc(
        self: *WindowsBackend,
        allocator: std.mem.Allocator,
        options: common.PathPromptOptions,
    ) !?common.PathList {
        _ = self;
        const script = try openDialogScript(allocator, options);
        defer allocator.free(script);

        const stdout = try runPowerShellCapture(allocator, script);
        defer allocator.free(stdout);
        return try parsePathList(allocator, stdout);
    }

    pub fn promptForNewPathAlloc(
        self: *WindowsBackend,
        allocator: std.mem.Allocator,
        options: common.PathPromptOptions,
    ) !?[]u8 {
        _ = self;
        const script = try saveDialogScript(allocator, options);
        defer allocator.free(script);

        const stdout = try runPowerShellCapture(allocator, script);
        defer allocator.free(stdout);
        return try parseSinglePath(allocator, stdout);
    }

    pub fn openWindow(self: *WindowsBackend, options: common.WindowOptions) !usize {
        const previous_active = self.windows.activeWindowInfo();
        const handle = try self.windows.open(self.allocator, options);

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

const ui_input = @import("../../input.zig");

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

fn queryAppearance(allocator: std.mem.Allocator) !common.WindowAppearance {
    if (builtin.os.tag != .windows) return .light;

    const stdout = runPowerShellCapture(
        allocator,
        "try { $theme = Get-ItemPropertyValue -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize' -Name AppsUseLightTheme -ErrorAction Stop; if ($theme -eq 0) { [Console]::WriteLine('dark') } else { [Console]::WriteLine('light') } } catch { [Console]::WriteLine('light') }",
    ) catch return .light;
    defer allocator.free(stdout);

    const trimmed = std.mem.trim(u8, stdout, " \r\n\t");
    if (std.ascii.eqlIgnoreCase(trimmed, "dark")) return .dark;
    return .light;
}

fn clipboardWriteScript(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var script: std.ArrayListUnmanaged(u8) = .empty;
    defer script.deinit(allocator);

    try script.appendSlice(allocator, "Set-Clipboard -Value ");
    try appendPowerShellLiteral(&script, allocator, text);
    return try script.toOwnedSlice(allocator);
}

fn startProcessScript(allocator: std.mem.Allocator, target: []const u8) ![]u8 {
    var script: std.ArrayListUnmanaged(u8) = .empty;
    defer script.deinit(allocator);

    try script.appendSlice(allocator, "Start-Process ");
    try appendPowerShellLiteral(&script, allocator, target);
    return try script.toOwnedSlice(allocator);
}

fn explorerScript(allocator: std.mem.Allocator, select_arg: []const u8) ![]u8 {
    var script: std.ArrayListUnmanaged(u8) = .empty;
    defer script.deinit(allocator);

    try script.appendSlice(allocator, "Start-Process explorer.exe -ArgumentList ");
    try appendPowerShellLiteral(&script, allocator, select_arg);
    return try script.toOwnedSlice(allocator);
}

fn openDialogScript(allocator: std.mem.Allocator, options: common.PathPromptOptions) ![]u8 {
    if (options.directories and options.multiple) return error.FileDialogUnavailable;

    var script: std.ArrayListUnmanaged(u8) = .empty;
    defer script.deinit(allocator);
    try script.appendSlice(allocator, "Add-Type -AssemblyName System.Windows.Forms; ");

    if (options.directories) {
        try script.appendSlice(allocator, "$dialog = New-Object System.Windows.Forms.FolderBrowserDialog; ");
        if (options.title) |title| {
            try script.appendSlice(allocator, "$dialog.Description = ");
            try appendPowerShellLiteral(&script, allocator, title);
            try script.appendSlice(allocator, "; ");
        }
        if (options.current_directory) |cwd| {
            try script.appendSlice(allocator, "$dialog.SelectedPath = ");
            try appendPowerShellLiteral(&script, allocator, cwd);
            try script.appendSlice(allocator, "; ");
        }
        try script.appendSlice(allocator, "if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { [Console]::WriteLine($dialog.SelectedPath) }");
        return try script.toOwnedSlice(allocator);
    }

    try script.appendSlice(allocator, "$dialog = New-Object System.Windows.Forms.OpenFileDialog; ");
    if (options.title) |title| {
        try script.appendSlice(allocator, "$dialog.Title = ");
        try appendPowerShellLiteral(&script, allocator, title);
        try script.appendSlice(allocator, "; ");
    }
    if (options.current_directory) |cwd| {
        try script.appendSlice(allocator, "$dialog.InitialDirectory = ");
        try appendPowerShellLiteral(&script, allocator, cwd);
        try script.appendSlice(allocator, "; ");
    }
    if (options.suggested_name) |suggested_name| {
        try script.appendSlice(allocator, "$dialog.FileName = ");
        try appendPowerShellLiteral(&script, allocator, suggested_name);
        try script.appendSlice(allocator, "; ");
    }
    try script.appendSlice(allocator, "$dialog.Multiselect = ");
    try script.appendSlice(allocator, if (options.multiple) "$true; " else "$false; ");
    try script.appendSlice(allocator, "if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $dialog.FileNames | ForEach-Object { [Console]::WriteLine($_) } }");
    return try script.toOwnedSlice(allocator);
}

fn saveDialogScript(allocator: std.mem.Allocator, options: common.PathPromptOptions) ![]u8 {
    var script: std.ArrayListUnmanaged(u8) = .empty;
    defer script.deinit(allocator);
    try script.appendSlice(allocator, "Add-Type -AssemblyName System.Windows.Forms; $dialog = New-Object System.Windows.Forms.SaveFileDialog; ");

    if (options.title) |title| {
        try script.appendSlice(allocator, "$dialog.Title = ");
        try appendPowerShellLiteral(&script, allocator, title);
        try script.appendSlice(allocator, "; ");
    }
    if (options.current_directory) |cwd| {
        try script.appendSlice(allocator, "$dialog.InitialDirectory = ");
        try appendPowerShellLiteral(&script, allocator, cwd);
        try script.appendSlice(allocator, "; ");
    }
    if (options.suggested_name) |suggested_name| {
        try script.appendSlice(allocator, "$dialog.FileName = ");
        try appendPowerShellLiteral(&script, allocator, suggested_name);
        try script.appendSlice(allocator, "; ");
    }
    try script.appendSlice(allocator, "if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { [Console]::WriteLine($dialog.FileName) }");
    return try script.toOwnedSlice(allocator);
}

fn appendPowerShellLiteral(
    builder: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,
    value: []const u8,
) !void {
    try builder.append(allocator, '\'');
    for (value) |byte| {
        if (byte == '\'') {
            try builder.appendSlice(allocator, "''");
        } else {
            try builder.append(allocator, byte);
        }
    }
    try builder.append(allocator, '\'');
}

fn runPowerShellCapture(allocator: std.mem.Allocator, script: []const u8) ![]u8 {
    if (builtin.os.tag != .windows) return error.UnsupportedPlatform;

    const result = try runProcess(allocator, &.{
        "powershell.exe",
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        script,
    });
    defer allocator.free(result.stderr);

    return switch (result.term) {
        .exited => |code| if (code == 0) result.stdout else blk: {
            allocator.free(result.stdout);
            break :blk error.ProcessExitedNonZero;
        },
        else => blk: {
            allocator.free(result.stdout);
            break :blk error.ProcessExitedNonZero;
        },
    };
}

fn runPowerShellStatus(allocator: std.mem.Allocator, script: []const u8) !void {
    const stdout = try runPowerShellCapture(allocator, script);
    allocator.free(stdout);
}

fn runProcess(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.RunResult {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    return std.process.run(allocator, threaded.io(), .{
        .argv = argv,
    });
}

fn parsePathList(allocator: std.mem.Allocator, stdout: []const u8) !?common.PathList {
    const trimmed = std.mem.trim(u8, stdout, " \r\n\t");
    if (trimmed.len == 0) return null;

    var count: usize = 0;
    var counter = std.mem.splitScalar(u8, trimmed, '\n');
    while (counter.next()) |_| count += 1;

    const paths = try allocator.alloc([]u8, count);
    var initialized: usize = 0;
    errdefer {
        for (paths[0..initialized]) |path| allocator.free(path);
        allocator.free(paths);
    }

    var split = std.mem.splitScalar(u8, trimmed, '\n');
    var index: usize = 0;
    while (split.next()) |line| : (index += 1) {
        paths[index] = try allocator.dupe(u8, std.mem.trimRight(u8, line, "\r"));
        initialized += 1;
    }

    return .{ .paths = paths };
}

fn parseSinglePath(allocator: std.mem.Allocator, stdout: []const u8) !?[]u8 {
    const trimmed = std.mem.trim(u8, stdout, " \r\n\t");
    if (trimmed.len == 0) return null;
    return try allocator.dupe(u8, trimmed);
}

test "powershell literal escaping doubles apostrophes" {
    var builder: std.ArrayListUnmanaged(u8) = .empty;
    defer builder.deinit(std.testing.allocator);

    try appendPowerShellLiteral(&builder, std.testing.allocator, "O'Brien");
    const owned = try builder.toOwnedSlice(std.testing.allocator);
    defer std.testing.allocator.free(owned);

    try std.testing.expectEqualStrings("'O''Brien'", owned);
}

test "path list parsing returns newline-delimited selections" {
    const parsed = (try parsePathList(std.testing.allocator, "C:\\a\nC:\\b\r\n")).?;
    defer {
        var owned = parsed;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), parsed.paths.len);
    try std.testing.expectEqualStrings("C:\\a", parsed.paths[0]);
    try std.testing.expectEqualStrings("C:\\b", parsed.paths[1]);
}

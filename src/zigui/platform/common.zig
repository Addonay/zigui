const std = @import("std");
const input = @import("../input.zig");

pub const BackendKind = enum {
    linux_wayland,
    linux_x11,
    linux_headless,
    macos_native,
    windows_native,
    unsupported,
};

pub const Cursor = enum {
    arrow,
    ibeam,
    pointing_hand,
    resize_left_right,
    resize_up_down,
};

pub const KeyRepeatConfig = struct {
    delay_ms: u32 = 250,
    rate_hz: u32 = 30,
};

pub const ModifierMask = packed struct(u8) {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,
    reserved_a: bool = false,
    reserved_b: bool = false,
};

pub const KeyboardLayout = enum {
    unknown,
    xkb,
};

pub const KeyboardInfo = struct {
    layout: KeyboardLayout = .unknown,
    repeat: KeyRepeatConfig = .{},
    modifiers: ModifierMask = .{},
    compose_enabled: bool = false,

    pub fn hasAnyModifier(self: KeyboardInfo) bool {
        return @as(u8, @bitCast(self.modifiers)) != 0;
    }
};

pub const WindowOptions = struct {
    title: []const u8 = "zigui",
    width: u32 = 1280,
    height: u32 = 800,
    resizable: bool = true,
    decorations: bool = true,
};

pub const ClipboardKind = enum {
    primary,
    clipboard,
};

pub const ClipboardSnapshot = struct {
    available: bool = false,
    has_text: bool = false,
    mime_type: ?[]const u8 = null,
};

pub const DisplayInfo = struct {
    id: usize = 0,
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    scale_factor: f32 = 1.0,
    is_primary: bool = false,
};

pub const WindowInfo = struct {
    id: usize = 0,
    title: []const u8 = "",
    width: u32 = 0,
    height: u32 = 0,
    scale_factor: f32 = 1.0,
    active: bool = false,
    hovered: bool = false,
    fullscreen: bool = false,
    decorated: bool = true,
    resizable: bool = true,
    visible: bool = true,
};

pub const WindowAppearance = enum {
    light,
    dark,
};

pub const WindowButtonLayout = struct {
    raw: []const u8 = ":minimize,maximize,close",
    controls_on_left: bool = false,
};

pub const PathPromptOptions = struct {
    directories: bool = false,
    multiple: bool = false,
    title: ?[]const u8 = null,
    prompt_label: ?[]const u8 = null,
    current_directory: ?[]const u8 = null,
    suggested_name: ?[]const u8 = null,
};

pub const PathList = struct {
    paths: [][]u8 = &.{},

    pub fn deinit(self: *PathList, allocator: std.mem.Allocator) void {
        for (self.paths) |path| allocator.free(path);
        allocator.free(self.paths);
        self.* = .{};
    }
};

pub const DesktopSettings = struct {
    appearance: WindowAppearance = .light,
    button_layout: WindowButtonLayout = .{},
    cursor_theme: ?[]const u8 = null,
    cursor_size: ?u32 = null,
    auto_hide_scrollbars: bool = false,
};

pub const RuntimeSnapshot = struct {
    compositor_name: []const u8 = "unknown",
    keyboard: KeyboardInfo = .{},
    clipboard: ClipboardSnapshot = .{},
    primary_selection: ClipboardSnapshot = .{},
    appearance: WindowAppearance = .light,
    button_layout: WindowButtonLayout = .{},
    seat_name: ?[]const u8 = null,
    display_count: usize = 0,
    window_count: usize = 0,
    active_window: ?WindowInfo = null,
};

pub const PlatformServices = struct {
    backend: BackendKind = .unsupported,
    supports_ime: bool = false,
    supports_clipboard: bool = false,
    supports_gpu_rendering: bool = false,
    supports_multiple_windows: bool = false,
};

pub const Diagnostics = struct {
    backend_name: []const u8 = "unsupported",
    window_system: []const u8 = "none",
    renderer: []const u8 = "unbound",
    note: []const u8 = "",
};

pub const RuntimeVTable = struct {
    deinit: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,
    run: *const fn (ptr: *anyopaque) anyerror!void,
    name: *const fn (ptr: *const anyopaque) []const u8,
    services: *const fn (ptr: *const anyopaque) PlatformServices,
    diagnostics: *const fn (ptr: *const anyopaque) Diagnostics,
    snapshot: *const fn (ptr: *const anyopaque) RuntimeSnapshot,
    display_infos_alloc: *const fn (ptr: *const anyopaque, allocator: std.mem.Allocator) anyerror![]DisplayInfo,
    window_infos_alloc: *const fn (ptr: *const anyopaque, allocator: std.mem.Allocator) anyerror![]WindowInfo,
    drain_events_alloc: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) anyerror![]input.InputEvent,
    set_cursor_style: *const fn (ptr: *anyopaque, cursor_kind: Cursor) void,
    write_text_to_clipboard: *const fn (ptr: *anyopaque, kind: ClipboardKind, text: []const u8) anyerror!void,
    read_text_from_clipboard_alloc: *const fn (ptr: *anyopaque, kind: ClipboardKind, allocator: std.mem.Allocator) anyerror![]u8,
    open_uri: *const fn (ptr: *anyopaque, uri: []const u8) anyerror!void,
    reveal_path: *const fn (ptr: *anyopaque, path: []const u8) anyerror!void,
    prompt_for_paths_alloc: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, options: PathPromptOptions) anyerror!?PathList,
    prompt_for_new_path_alloc: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, options: PathPromptOptions) anyerror!?[]u8,
    open_window: *const fn (ptr: *anyopaque, options: WindowOptions) anyerror!usize,
    close_window: *const fn (ptr: *anyopaque, handle: usize) anyerror!void,
};

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    ptr: *anyopaque,
    vtable: *const RuntimeVTable,

    pub fn deinit(self: *Runtime) void {
        self.vtable.deinit(self.ptr, self.allocator);
        self.* = undefined;
    }

    pub fn run(self: *Runtime) !void {
        try self.vtable.run(self.ptr);
    }

    pub fn name(self: *const Runtime) []const u8 {
        return self.vtable.name(self.ptr);
    }

    pub fn services(self: *const Runtime) PlatformServices {
        return self.vtable.services(self.ptr);
    }

    pub fn diagnostics(self: *const Runtime) Diagnostics {
        return self.vtable.diagnostics(self.ptr);
    }

    pub fn snapshot(self: *const Runtime) RuntimeSnapshot {
        return self.vtable.snapshot(self.ptr);
    }

    pub fn displayInfosAlloc(self: *const Runtime, allocator: std.mem.Allocator) ![]DisplayInfo {
        return try self.vtable.display_infos_alloc(self.ptr, allocator);
    }

    pub fn windowInfosAlloc(self: *const Runtime, allocator: std.mem.Allocator) ![]WindowInfo {
        return try self.vtable.window_infos_alloc(self.ptr, allocator);
    }

    pub fn drainEventsAlloc(self: *Runtime, allocator: std.mem.Allocator) ![]input.InputEvent {
        return try self.vtable.drain_events_alloc(self.ptr, allocator);
    }

    pub fn setCursorStyle(self: *Runtime, cursor_kind: Cursor) void {
        self.vtable.set_cursor_style(self.ptr, cursor_kind);
    }

    pub fn writeTextToClipboard(self: *Runtime, kind: ClipboardKind, text: []const u8) !void {
        try self.vtable.write_text_to_clipboard(self.ptr, kind, text);
    }

    pub fn readTextFromClipboardAlloc(
        self: *Runtime,
        kind: ClipboardKind,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        return try self.vtable.read_text_from_clipboard_alloc(self.ptr, kind, allocator);
    }

    pub fn openUri(self: *Runtime, uri: []const u8) !void {
        try self.vtable.open_uri(self.ptr, uri);
    }

    pub fn revealPath(self: *Runtime, path: []const u8) !void {
        try self.vtable.reveal_path(self.ptr, path);
    }

    pub fn promptForPathsAlloc(
        self: *Runtime,
        allocator: std.mem.Allocator,
        options: PathPromptOptions,
    ) !?PathList {
        return try self.vtable.prompt_for_paths_alloc(self.ptr, allocator, options);
    }

    pub fn promptForNewPathAlloc(
        self: *Runtime,
        allocator: std.mem.Allocator,
        options: PathPromptOptions,
    ) !?[]u8 {
        return try self.vtable.prompt_for_new_path_alloc(self.ptr, allocator, options);
    }

    pub fn openWindow(self: *Runtime, options: WindowOptions) !usize {
        return try self.vtable.open_window(self.ptr, options);
    }

    pub fn closeWindow(self: *Runtime, handle: usize) !void {
        try self.vtable.close_window(self.ptr, handle);
    }
};

test "runtime snapshot defaults to an empty runtime state" {
    const snapshot = RuntimeSnapshot{};
    try std.testing.expectEqualStrings("unknown", snapshot.compositor_name);
    try std.testing.expectEqual(@as(usize, 0), snapshot.display_count);
    try std.testing.expectEqual(@as(?WindowInfo, null), snapshot.active_window);
}

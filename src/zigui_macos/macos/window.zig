const std = @import("std");
const common = @import("../../zigui/common.zig");
const window_appearance = @import("window_appearance.zig");

pub const UserTabbingPreference = enum {
    never,
    always,
    in_full_screen,
};

pub const ManagedWindow = struct {
    handle: usize,
    options: common.WindowOptions,
    title: []u8,
    width: u32,
    height: u32,
    scale_factor: f32 = 1.0,
    active: bool = false,
    hovered: bool = false,
    fullscreen: bool = false,
    visible: bool = true,
    decorated: bool = true,
    uses_native_titlebar: bool = true,
    appearance: window_appearance.MacWindowAppearance = .aqua,
    background_blur_radius: u32 = 0,
    current_cursor: common.Cursor = .arrow,
    actual_decorations: common.Decorations = .server,
    window_controls: common.WindowControls = .{},
    client_inset: u32 = 0,
    show_menu_requested: bool = false,
    menu_x: f32 = 0,
    menu_y: f32 = 0,
    move_requested: bool = false,
    resize_edge: ?common.ResizeEdge = null,

    pub fn init(
        allocator: std.mem.Allocator,
        handle: usize,
        options: common.WindowOptions,
        appearance: window_appearance.MacWindowAppearance,
    ) !ManagedWindow {
        const title = try allocator.dupe(u8, options.title);
        errdefer allocator.free(title);

        var stored_options = options;
        stored_options.title = title;

        return .{
            .handle = handle,
            .options = stored_options,
            .title = title,
            .width = options.width,
            .height = options.height,
            .appearance = appearance,
            .actual_decorations = switch (options.decorations) {
                .server => .server,
                .client => .{ .client = .{} },
            },
            .window_controls = .{
                .fullscreen = true,
                .maximize = options.resizable,
                .minimize = true,
                .window_menu = true,
            },
        };
    }

    pub fn deinit(self: *ManagedWindow, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
    }

    pub fn info(self: *const ManagedWindow) common.WindowInfo {
        return .{
            .id = self.handle,
            .title = self.title,
            .width = self.width,
            .height = self.height,
            .scale_factor = self.scale_factor,
            .active = self.active,
            .hovered = self.hovered,
            .fullscreen = self.fullscreen,
            .decorated = self.decorated,
            .decorations = self.actual_decorations,
            .resizable = self.options.resizable,
            .visible = self.visible,
            .window_controls = self.window_controls,
        };
    }

    pub fn setTitle(self: *ManagedWindow, allocator: std.mem.Allocator, title: []const u8) !void {
        const owned = try allocator.dupe(u8, title);
        allocator.free(self.title);
        self.title = owned;
        self.options.title = self.title;
    }

    pub fn requestDecorations(self: *ManagedWindow, decorations: common.WindowDecorations) void {
        self.options.decorations = decorations;
        self.actual_decorations = switch (decorations) {
            .server => .server,
            .client => .{ .client = .{} },
        };
    }

    pub fn setClientInset(self: *ManagedWindow, inset: u32) void {
        self.client_inset = inset;
    }

    pub fn setAppearance(self: *ManagedWindow, appearance: window_appearance.MacWindowAppearance) void {
        self.appearance = appearance;
    }

    pub fn requestMenu(self: *ManagedWindow, x: f32, y: f32) void {
        self.show_menu_requested = true;
        self.menu_x = x;
        self.menu_y = y;
    }

    pub fn requestMove(self: *ManagedWindow) void {
        self.move_requested = true;
    }

    pub fn requestResize(self: *ManagedWindow, edge: common.ResizeEdge) void {
        self.resize_edge = edge;
    }
};

pub const MacWindow = ManagedWindow;

pub const WindowState = struct {
    uses_native_windowing: bool = true,
    next_handle: usize = 1,
    active_handle: ?usize = null,
    current_cursor: common.Cursor = .arrow,
    current_appearance: window_appearance.MacWindowAppearance = .aqua,
    tabbing_preference: UserTabbingPreference = .never,
    windows: std.ArrayListUnmanaged(ManagedWindow) = .empty,

    pub fn deinit(self: *WindowState, allocator: std.mem.Allocator) void {
        for (self.windows.items) |*managed| managed.deinit(allocator);
        self.windows.deinit(allocator);
    }

    pub fn open(
        self: *WindowState,
        allocator: std.mem.Allocator,
        options: common.WindowOptions,
    ) !usize {
        const handle = self.next_handle;
        self.next_handle += 1;

        var managed = try ManagedWindow.init(allocator, handle, options, self.current_appearance);
        errdefer managed.deinit(allocator);
        managed.current_cursor = self.current_cursor;

        try self.windows.append(allocator, managed);
        self.active_handle = handle;
        self.syncFocus(handle);
        return handle;
    }

    pub fn close(self: *WindowState, allocator: std.mem.Allocator, handle: usize) !void {
        const index = self.indexOf(handle) orelse return error.WindowNotFound;
        var managed = self.windows.orderedRemove(index);
        managed.visible = false;
        managed.deinit(allocator);

        if (self.active_handle != null and self.active_handle.? == handle) {
            self.active_handle = if (self.windows.items.len == 0)
                null
            else
                self.windows.items[self.windows.items.len - 1].handle;
            if (self.active_handle) |next_handle| {
                self.syncFocus(next_handle);
            }
        }
    }

    pub fn setCursor(self: *WindowState, cursor_kind: common.Cursor) void {
        self.current_cursor = cursor_kind;
        for (self.windows.items) |*managed| managed.current_cursor = cursor_kind;
    }

    pub fn setAppearance(self: *WindowState, appearance: window_appearance.MacWindowAppearance) void {
        self.current_appearance = appearance;
        for (self.windows.items) |*managed| managed.setAppearance(appearance);
    }

    pub fn count(self: *const WindowState) usize {
        return self.windows.items.len;
    }

    pub fn activeWindowInfo(self: *const WindowState) ?common.WindowInfo {
        if (self.active_handle) |handle| {
            if (self.get(handle)) |managed| return managed.info();
        }
        if (self.windows.items.len == 0) return null;
        return self.windows.items[self.windows.items.len - 1].info();
    }

    pub fn infosAlloc(self: *const WindowState, allocator: std.mem.Allocator) ![]common.WindowInfo {
        const infos = try allocator.alloc(common.WindowInfo, self.windows.items.len);
        for (self.windows.items, 0..) |managed, index| {
            infos[index] = managed.info();
        }
        return infos;
    }

    pub fn get(self: *const WindowState, handle: usize) ?*const ManagedWindow {
        const index = self.indexOf(handle) orelse return null;
        return &self.windows.items[index];
    }

    pub fn getMut(self: *WindowState, handle: usize) ?*ManagedWindow {
        const index = self.indexOf(handle) orelse return null;
        return &self.windows.items[index];
    }

    fn indexOf(self: *const WindowState, handle: usize) ?usize {
        for (self.windows.items, 0..) |managed, index| {
            if (managed.handle == handle) return index;
        }
        return null;
    }

    fn syncFocus(self: *WindowState, active_handle: usize) void {
        for (self.windows.items) |*managed| {
            managed.active = managed.handle == active_handle;
        }
    }
};

pub const MacWindowState = WindowState;

test "window state tracks multiple logical windows" {
    var state = WindowState{};
    defer state.deinit(std.testing.allocator);

    const first = try state.open(std.testing.allocator, .{ .title = "first" });
    const second = try state.open(std.testing.allocator, .{ .title = "second" });

    try std.testing.expectEqual(@as(usize, 2), state.count());
    try std.testing.expectEqual(second, state.activeWindowInfo().?.id);

    try state.close(std.testing.allocator, second);
    try std.testing.expectEqual(@as(usize, 1), state.count());
    try std.testing.expectEqual(first, state.activeWindowInfo().?.id);
}

test "window state tracks appearance and cursor updates" {
    var state = WindowState{};
    defer state.deinit(std.testing.allocator);

    _ = try state.open(std.testing.allocator, .{ .title = "demo" });
    state.setCursor(.ibeam);
    state.setAppearance(.dark_aqua);

    try std.testing.expectEqual(common.Cursor.ibeam, state.current_cursor);
    try std.testing.expectEqual(window_appearance.MacWindowAppearance.dark_aqua, state.current_appearance);
    try std.testing.expectEqual(window_appearance.MacWindowAppearance.dark_aqua, state.windows.items[0].appearance);
}

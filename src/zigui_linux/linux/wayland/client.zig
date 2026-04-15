const std = @import("std");
const common = @import("../../../zigui/common.zig");
const ui_input = @import("../../../zigui/input.zig");
const linux_keyboard = @import("../keyboard.zig");
const types = @import("../types.zig");
const activation = @import("activation.zig");
const c = @import("c.zig").c;
const display = @import("display.zig");
const clipboard = @import("clipboard.zig");
const cursor = @import("cursor.zig");
const input = @import("input.zig");
const output = @import("output.zig");
const window = @import("window.zig");

const Globals = struct {
    activation_manager: ?*c.xdg_activation_v1 = null,
    compositor: ?*c.wl_compositor = null,
    data_device_manager: ?*c.wl_data_device_manager = null,
    decoration_manager: ?*c.zxdg_decoration_manager_v1 = null,
    fractional_scale_manager: ?*c.wp_fractional_scale_manager_v1 = null,
    primary_selection_manager: ?*c.zwp_primary_selection_device_manager_v1 = null,
    shm: ?*c.wl_shm = null,
    seat: ?*c.wl_seat = null,
    viewporter: ?*c.wp_viewporter = null,
    output_count: usize = 0,
    wm_base: ?*c.xdg_wm_base = null,
};

const WaylandState = struct {
    allocator: std.mem.Allocator,
    display: display.WaylandDisplay,
    registry: *c.wl_registry,
    globals: Globals = .{},
    windows: std.ArrayListUnmanaged(*window.WaylandWindow) = .empty,
    events: ui_input.EventQueue = .{},
    pointer: ?*c.wl_pointer = null,
    keyboard_device: ?*c.wl_keyboard = null,
    data_device: ?*c.wl_data_device = null,
    primary_selection_device: ?*c.zwp_primary_selection_device_v1 = null,
    clipboard_source: ?*c.wl_data_source = null,
    primary_selection_source: ?*c.zwp_primary_selection_source_v1 = null,
    cursor_manager: ?cursor.CursorManager = null,
    input_state: input.WaylandInputState,
    clipboard_state: clipboard.ClipboardState = .{},
    clipboard_offers: std.AutoHashMapUnmanaged(usize, clipboard.ClipboardOffer) = .empty,
    primary_selection_offers: std.AutoHashMapUnmanaged(usize, clipboard.ClipboardOffer) = .empty,
    seat_name: ?[]u8 = null,
    outputs: std.AutoHashMapUnmanaged(output.OutputId, output.OutputInfo) = .empty,
    in_progress_outputs: std.AutoHashMapUnmanaged(output.OutputId, output.InProgressOutput) = .empty,
    output_handles: std.AutoHashMapUnmanaged(output.OutputId, *c.wl_output) = .empty,
    output_globals: std.AutoHashMapUnmanaged(u32, output.OutputId) = .empty,
    startup_activation_token: ?[]u8 = null,
    owned_clipboard_text: ?[]u8 = null,
    owned_primary_selection_text: ?[]u8 = null,
    running: bool = true,
};

pub const WaylandClient = struct {
    allocator: std.mem.Allocator,
    compositor_name: []const u8 = "wayland",
    state: *WaylandState,

    pub fn init(allocator: std.mem.Allocator, options: anytype) !WaylandClient {
        const server_name = if (std.c.getenv("WAYLAND_DISPLAY")) |ptr| std.mem.span(ptr) else null;
        const state = try allocator.create(WaylandState);
        errdefer allocator.destroy(state);

        state.* = .{
            .allocator = allocator,
            .display = try display.WaylandDisplay.connect(server_name),
            .registry = undefined,
            .input_state = input.WaylandInputState.init(allocator),
        };
        errdefer state.display.disconnect();
        errdefer state.input_state.deinit();
        state.startup_activation_token = try activation.loadEnvironmentTokenAlloc(allocator);
        errdefer if (state.startup_activation_token) |token| allocator.free(token);

        state.registry = c.wl_display_get_registry(state.display.handle) orelse return error.RegistryUnavailable;
        errdefer c.wl_registry_destroy(state.registry);

        if (c.wl_registry_add_listener(state.registry, &registry_listener, state) != 0) {
            return error.RegistryListenerFailed;
        }
        try state.display.roundtrip();

        state.clipboard_state.has_clipboard = state.globals.data_device_manager != null;
        state.clipboard_state.has_primary_selection = state.globals.primary_selection_manager != null;

        const compositor = state.globals.compositor orelse return error.MissingCompositor;
        const shm = state.globals.shm orelse return error.MissingSharedMemory;
        const wm_base = state.globals.wm_base orelse return error.MissingShell;

        if (c.xdg_wm_base_add_listener(wm_base, &wm_base_listener, state) != 0) {
            return error.ShellListenerFailed;
        }
        if (state.globals.seat) |seat| {
            if (c.wl_seat_add_listener(seat, &seat_listener, state) != 0) return error.SeatListenerFailed;
            try state.display.roundtrip();
        }
        if (state.globals.data_device_manager) |manager| {
            if (state.globals.seat) |seat| {
                const data_device = c.wl_data_device_manager_get_data_device(manager, seat) orelse return error.DataDeviceUnavailable;
                if (c.wl_data_device_add_listener(data_device, &data_device_listener, state) != 0) {
                    c.wl_data_device_release(data_device);
                    return error.DataDeviceListenerFailed;
                }
                state.data_device = data_device;
            }
        }
        if (state.globals.primary_selection_manager) |manager| {
            if (state.globals.seat) |seat| {
                const primary_selection_device = c.zwp_primary_selection_device_manager_v1_get_device(manager, seat) orelse return error.DataDeviceUnavailable;
                if (c.zwp_primary_selection_device_v1_add_listener(primary_selection_device, &primary_selection_device_listener, state) != 0) {
                    c.zwp_primary_selection_device_v1_destroy(primary_selection_device);
                    return error.DataDeviceListenerFailed;
                }
                state.primary_selection_device = primary_selection_device;
            }
        }

        state.cursor_manager = try cursor.CursorManager.init(allocator, compositor, shm);
        errdefer {
            if (state.cursor_manager) |*manager| manager.deinit();
        }

        const owned_window = try createTrackedWindow(state, options);
        errdefer closeTrackedWindow(state, owned_window.surface);

        if (state.startup_activation_token) |token| {
            try activateSurface(state, token);
            activation.clearEnvironmentToken();
        }

        owned_window.commitInitial();
        try state.display.roundtrip();

        return .{
            .allocator = allocator,
            .compositor_name = state.display.server_name,
            .state = state,
        };
    }

    pub fn deinit(self: *WaylandClient) void {
        if (self.state.pointer) |pointer| c.wl_pointer_release(pointer);
        if (self.state.keyboard_device) |keyboard_device| c.wl_keyboard_release(keyboard_device);
        if (self.state.data_device) |data_device| c.wl_data_device_release(data_device);
        if (self.state.primary_selection_device) |device| c.zwp_primary_selection_device_v1_destroy(device);
        if (self.state.clipboard_source) |source| c.wl_data_source_destroy(source);
        if (self.state.primary_selection_source) |source| c.zwp_primary_selection_source_v1_destroy(source);
        if (self.state.cursor_manager) |*manager| manager.deinit();
        for (self.state.windows.items) |owned_window| {
            owned_window.deinit();
            self.allocator.destroy(owned_window);
        }
        self.state.windows.deinit(self.allocator);
        self.state.events.deinit(self.allocator);
        if (self.state.globals.seat) |seat| c.wl_seat_release(seat);
        if (self.state.globals.data_device_manager) |manager| c.wl_data_device_manager_destroy(manager);
        if (self.state.globals.decoration_manager) |manager| c.zxdg_decoration_manager_v1_destroy(manager);
        if (self.state.globals.fractional_scale_manager) |manager| c.wp_fractional_scale_manager_v1_destroy(manager);
        if (self.state.globals.primary_selection_manager) |manager| c.zwp_primary_selection_device_manager_v1_destroy(manager);
        if (self.state.globals.viewporter) |manager| c.wp_viewporter_destroy(manager);
        if (self.state.globals.activation_manager) |manager| c.xdg_activation_v1_destroy(manager);
        {
            var iterator = self.state.clipboard_offers.iterator();
            while (iterator.next()) |entry| {
                c.wl_data_offer_destroy(@ptrFromInt(entry.key_ptr.*));
                entry.value_ptr.deinit(self.allocator);
            }
            self.state.clipboard_offers.deinit(self.allocator);
        }
        {
            var iterator = self.state.primary_selection_offers.iterator();
            while (iterator.next()) |entry| {
                c.zwp_primary_selection_offer_v1_destroy(@ptrFromInt(entry.key_ptr.*));
                entry.value_ptr.deinit(self.allocator);
            }
            self.state.primary_selection_offers.deinit(self.allocator);
        }
        {
            var iterator = self.state.outputs.valueIterator();
            while (iterator.next()) |display_info| display_info.deinit(self.allocator);
            self.state.outputs.deinit(self.allocator);
        }
        {
            var iterator = self.state.in_progress_outputs.valueIterator();
            while (iterator.next()) |display_info| display_info.deinit(self.allocator);
            self.state.in_progress_outputs.deinit(self.allocator);
        }
        {
            var iterator = self.state.output_handles.valueIterator();
            while (iterator.next()) |wl_output| {
                if (c.wl_output_get_version(wl_output.*) >= c.WL_OUTPUT_RELEASE_SINCE_VERSION) {
                    c.wl_output_release(wl_output.*);
                } else {
                    c.wl_proxy_destroy(@ptrCast(wl_output.*));
                }
            }
            self.state.output_handles.deinit(self.allocator);
        }
        self.state.output_globals.deinit(self.allocator);
        if (self.state.globals.wm_base) |wm_base| c.xdg_wm_base_destroy(wm_base);
        if (self.state.globals.shm) |shm| c.wl_shm_destroy(shm);
        if (self.state.globals.compositor) |compositor| c.wl_compositor_destroy(compositor);
        if (self.state.seat_name) |seat_name| self.allocator.free(seat_name);
        if (self.state.startup_activation_token) |token| self.allocator.free(token);
        if (self.state.owned_clipboard_text) |text| self.allocator.free(text);
        if (self.state.owned_primary_selection_text) |text| self.allocator.free(text);
        self.state.input_state.deinit();
        c.wl_registry_destroy(self.state.registry);
        self.state.display.disconnect();
        self.allocator.destroy(self.state);
    }

    pub fn run(self: *WaylandClient) !void {
        while (self.state.running) {
            try self.state.display.dispatch();
        }
    }

    pub fn compositorName(self: *const WaylandClient) []const u8 {
        return self.compositor_name;
    }

    pub fn seatName(self: *const WaylandClient) ?[]const u8 {
        return self.state.seat_name;
    }

    pub fn keyboardInfo(self: *const WaylandClient) linux_keyboard.KeyboardInfo {
        return self.state.input_state.keyboard.snapshot();
    }

    pub fn pointerPosition(self: *const WaylandClient) struct { x: f64, y: f64 } {
        return .{
            .x = self.state.input_state.pointer.surface_x,
            .y = self.state.input_state.pointer.surface_y,
        };
    }

    pub fn outputCount(self: *const WaylandClient) usize {
        return self.state.outputs.count();
    }

    pub fn clipboardState(self: *const WaylandClient) clipboard.ClipboardState {
        return self.state.clipboard_state;
    }

    pub fn clipboardSnapshot(
        self: *const WaylandClient,
        kind: types.LinuxClipboardKind,
    ) types.LinuxClipboardSnapshot {
        return switch (kind) {
            .clipboard => .{
                .available = self.state.clipboard_state.has_clipboard,
                .has_text = if (self.state.owned_clipboard_text) |text|
                    text.len != 0
                else
                    self.state.clipboard_state.selection_has_text,
                .mime_type = if (self.state.owned_clipboard_text != null)
                    clipboard.text_mime_types[0]
                else if (self.state.clipboard_state.selection_has_text)
                    self.state.clipboard_state.preferred_text_mime
                else
                    null,
            },
            .primary => .{
                .available = self.state.clipboard_state.has_primary_selection,
                .has_text = if (self.state.owned_primary_selection_text) |text|
                    text.len != 0
                else
                    self.state.clipboard_state.primary_selection_has_text,
                .mime_type = if (self.state.owned_primary_selection_text != null)
                    clipboard.text_mime_types[0]
                else if (self.state.clipboard_state.primary_selection_has_text)
                    self.state.clipboard_state.primary_preferred_text_mime
                else
                    null,
            },
        };
    }

    pub fn activeWindowInfo(self: *const WaylandClient) ?types.LinuxWindowInfo {
        const owned_window = activeOrPrimaryWindow(self.state) orelse return null;
        if (owned_window.close_requested) return null;
        return snapshotWindowInfo(self.state, owned_window);
    }

    pub fn windowInfosAlloc(
        self: *const WaylandClient,
        allocator: std.mem.Allocator,
    ) ![]types.LinuxWindowInfo {
        const count = windowCount(self.state);
        const infos = try allocator.alloc(types.LinuxWindowInfo, count);
        var index: usize = 0;
        for (self.state.windows.items) |owned_window| {
            if (owned_window.close_requested) continue;
            infos[index] = snapshotWindowInfo(self.state, owned_window);
            index += 1;
        }
        return infos;
    }

    pub fn displayInfosAlloc(
        self: *const WaylandClient,
        allocator: std.mem.Allocator,
    ) ![]types.LinuxDisplayInfo {
        const infos = try allocator.alloc(types.LinuxDisplayInfo, self.state.outputs.count());
        const primary_output = selectPrimaryOutputId(self.state);
        var iterator = self.state.outputs.iterator();
        var index: usize = 0;
        while (iterator.next()) |entry| : (index += 1) {
            const info = entry.value_ptr.*;
            infos[index] = .{
                .id = info.id,
                .name = info.name,
                .description = info.description,
                .x = info.x,
                .y = info.y,
                .width = info.width,
                .height = info.height,
                .scale_factor = @floatFromInt(info.scale),
                .is_primary = primary_output != null and primary_output.? == info.id,
            };
        }
        return infos;
    }

    pub fn snapshot(self: *const WaylandClient) types.LinuxRuntimeSnapshot {
        const active_window = self.activeWindowInfo();
        return .{
            .compositor_name = self.compositorName(),
            .keyboard = self.keyboardInfo(),
            .clipboard = self.clipboardSnapshot(.clipboard),
            .primary_selection = self.clipboardSnapshot(.primary),
            .seat_name = self.seatName(),
            .display_count = self.outputCount(),
            .window_count = windowCount(self.state),
            .active_window = active_window,
        };
    }

    pub fn writeTextToClipboard(
        self: *WaylandClient,
        kind: types.LinuxClipboardKind,
        text: []const u8,
    ) !void {
        const owned = try self.allocator.dupe(u8, text);
        switch (kind) {
            .clipboard => {
                if (self.state.owned_clipboard_text) |previous| self.allocator.free(previous);
                self.state.owned_clipboard_text = owned;
                self.state.clipboard_state.has_clipboard = true;
                self.state.clipboard_state.selection_offer = null;
                self.state.clipboard_state.selection_has_text = text.len != 0;
                self.state.clipboard_state.preferred_text_mime = clipboard.text_mime_types[0];
                installClipboardSource(self.state) catch {};
            },
            .primary => {
                if (self.state.owned_primary_selection_text) |previous| self.allocator.free(previous);
                self.state.owned_primary_selection_text = owned;
                self.state.clipboard_state.has_primary_selection = true;
                self.state.clipboard_state.primary_selection_offer = null;
                self.state.clipboard_state.primary_selection_has_text = text.len != 0;
                self.state.clipboard_state.primary_preferred_text_mime = clipboard.text_mime_types[0];
                installPrimarySelectionSource(self.state) catch {};
            },
        }
    }

    pub fn readClipboardTextAlloc(self: *WaylandClient, allocator: std.mem.Allocator) ![]u8 {
        if (self.state.owned_clipboard_text) |text| {
            return allocator.dupe(u8, text);
        }
        const offer_id = self.state.clipboard_state.selection_offer orelse return error.NoClipboardText;
        const offer = self.state.clipboard_offers.getPtr(offer_id) orelse return error.NoClipboardText;
        const mime_type = offer.preferredTextMime() orelse return error.NoClipboardText;

        var fds: [2]c_int = undefined;
        if (std.c.pipe(&fds) != 0) return error.PipeCreationFailed;
        errdefer _ = std.os.linux.close(fds[0]);
        errdefer _ = std.os.linux.close(fds[1]);

        const mime_type_z = try allocator.dupeZ(u8, mime_type);
        defer allocator.free(mime_type_z);

        c.wl_data_offer_receive(@ptrFromInt(offer_id), mime_type_z.ptr, fds[1]);
        try self.state.display.flush();
        _ = std.os.linux.close(fds[1]);

        var bytes: std.ArrayList(u8) = .empty;
        errdefer bytes.deinit(allocator);
        var buffer: [4096]u8 = undefined;
        while (true) {
            const read_len = std.posix.read(fds[0], &buffer) catch |err| switch (err) {
                error.WouldBlock => continue,
                else => return err,
            };
            if (read_len == 0) break;
            try bytes.appendSlice(allocator, buffer[0..read_len]);
        }
        _ = std.os.linux.close(fds[0]);
        return bytes.toOwnedSlice(allocator);
    }

    pub fn readPrimarySelectionTextAlloc(self: *WaylandClient, allocator: std.mem.Allocator) ![]u8 {
        if (self.state.owned_primary_selection_text) |text| {
            return allocator.dupe(u8, text);
        }
        const offer_id = self.state.clipboard_state.primary_selection_offer orelse return error.NoPrimarySelectionText;
        const offer = self.state.primary_selection_offers.getPtr(offer_id) orelse return error.NoPrimarySelectionText;
        const mime_type = offer.preferredTextMime() orelse return error.NoPrimarySelectionText;

        var fds: [2]c_int = undefined;
        if (std.c.pipe(&fds) != 0) return error.PipeCreationFailed;
        errdefer _ = std.os.linux.close(fds[0]);
        errdefer _ = std.os.linux.close(fds[1]);

        const mime_type_z = try allocator.dupeZ(u8, mime_type);
        defer allocator.free(mime_type_z);

        c.zwp_primary_selection_offer_v1_receive(@ptrFromInt(offer_id), mime_type_z.ptr, fds[1]);
        try self.state.display.flush();
        _ = std.os.linux.close(fds[1]);

        var bytes: std.ArrayList(u8) = .empty;
        errdefer bytes.deinit(allocator);
        var buffer: [4096]u8 = undefined;
        while (true) {
            const read_len = std.posix.read(fds[0], &buffer) catch |err| switch (err) {
                error.WouldBlock => continue,
                else => return err,
            };
            if (read_len == 0) break;
            try bytes.appendSlice(allocator, buffer[0..read_len]);
        }
        _ = std.os.linux.close(fds[0]);
        return bytes.toOwnedSlice(allocator);
    }

    pub fn setCursorStyle(self: *WaylandClient, cursor_kind: common.Cursor) void {
        self.state.input_state.pointer.cursor = cursor_kind;
        applyCurrentCursor(self.state, activeOrPrimaryWindow(self.state));
    }

    pub fn activateFromToken(self: *WaylandClient, token: []const u8) !void {
        try activateSurface(self.state, token);
    }

    pub fn openWindow(self: *WaylandClient, options: common.WindowOptions) !usize {
        const owned_window = try createTrackedWindow(self.state, options);
        owned_window.commitInitial();
        try self.state.display.flush();
        return @intFromPtr(owned_window.surface);
    }

    pub fn closeWindow(self: *WaylandClient, handle: usize) !void {
        const surface: *c.wl_surface = @ptrFromInt(handle);
        if (findWindowBySurface(self.state, surface) == null) return error.WindowNotFound;
        closeTrackedWindow(self.state, surface);
        try self.state.display.flush();
    }

    pub fn setWindowTitle(self: *WaylandClient, handle: usize, title: []const u8) !void {
        const surface: *c.wl_surface = @ptrFromInt(handle);
        const owned_window = findWindowBySurface(self.state, surface) orelse return error.WindowNotFound;
        try owned_window.setTitle(self.allocator, title);
        presentWindowIfConfigured(self.state, owned_window);
        try self.state.display.flush();
    }

    pub fn requestWindowDecorations(
        self: *WaylandClient,
        handle: usize,
        decorations: common.WindowDecorations,
    ) !void {
        const surface: *c.wl_surface = @ptrFromInt(handle);
        const owned_window = findWindowBySurface(self.state, surface) orelse return error.WindowNotFound;
        owned_window.requestDecorations(decorations);
        presentWindowIfConfigured(self.state, owned_window);
        try self.state.display.flush();
    }

    pub fn showWindowMenu(self: *WaylandClient, handle: usize, x: f32, y: f32) !void {
        const seat = self.state.globals.seat orelse return error.SeatUnavailable;
        const surface: *c.wl_surface = @ptrFromInt(handle);
        const owned_window = findWindowBySurface(self.state, surface) orelse return error.WindowNotFound;
        const serial_value = self.state.input_state.pointer.serials.latestPointer();
        if (serial_value == 0) return error.SelectionSerialUnavailable;
        c.xdg_toplevel_show_window_menu(
            owned_window.xdg_toplevel,
            seat,
            serial_value,
            @intFromFloat(x),
            @intFromFloat(y),
        );
        try self.state.display.flush();
    }

    pub fn startWindowMove(self: *WaylandClient, handle: usize) !void {
        const seat = self.state.globals.seat orelse return error.SeatUnavailable;
        const surface: *c.wl_surface = @ptrFromInt(handle);
        const owned_window = findWindowBySurface(self.state, surface) orelse return error.WindowNotFound;
        const serial_value = self.state.input_state.pointer.serials.latestPointer();
        if (serial_value == 0) return error.SelectionSerialUnavailable;
        c.xdg_toplevel_move(owned_window.xdg_toplevel, seat, serial_value);
        try self.state.display.flush();
    }

    pub fn startWindowResize(self: *WaylandClient, handle: usize, edge: common.ResizeEdge) !void {
        const seat = self.state.globals.seat orelse return error.SeatUnavailable;
        const surface: *c.wl_surface = @ptrFromInt(handle);
        const owned_window = findWindowBySurface(self.state, surface) orelse return error.WindowNotFound;
        const serial_value = self.state.input_state.pointer.serials.latestPointer();
        if (serial_value == 0) return error.SelectionSerialUnavailable;
        c.xdg_toplevel_resize(owned_window.xdg_toplevel, seat, serial_value, resizeEdgeToXdg(edge));
        try self.state.display.flush();
    }

    pub fn windowDecorations(self: *const WaylandClient, handle: usize) common.Decorations {
        const surface: *c.wl_surface = @ptrFromInt(handle);
        const owned_window = findWindowBySurface(self.state, surface) orelse return .server;
        return owned_window.actualDecorations();
    }

    pub fn windowControls(self: *const WaylandClient, handle: usize) common.WindowControls {
        const surface: *c.wl_surface = @ptrFromInt(handle);
        const owned_window = findWindowBySurface(self.state, surface) orelse return .{};
        return owned_window.window_controls;
    }

    pub fn setClientInset(self: *WaylandClient, handle: usize, inset: u32) !void {
        const surface: *c.wl_surface = @ptrFromInt(handle);
        const owned_window = findWindowBySurface(self.state, surface) orelse return error.WindowNotFound;
        owned_window.setClientInset(inset);
        presentWindowIfConfigured(self.state, owned_window);
        try self.state.display.flush();
    }

    pub fn drainEventsAlloc(self: *WaylandClient, allocator: std.mem.Allocator) ![]ui_input.InputEvent {
        return self.state.events.drainAlloc(allocator);
    }
};

fn resizeEdgeToXdg(edge: common.ResizeEdge) u32 {
    return switch (edge) {
        .top => c.XDG_TOPLEVEL_RESIZE_EDGE_TOP,
        .top_right => c.XDG_TOPLEVEL_RESIZE_EDGE_TOP_RIGHT,
        .right => c.XDG_TOPLEVEL_RESIZE_EDGE_RIGHT,
        .bottom_right => c.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_RIGHT,
        .bottom => c.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM,
        .bottom_left => c.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_LEFT,
        .left => c.XDG_TOPLEVEL_RESIZE_EDGE_LEFT,
        .top_left => c.XDG_TOPLEVEL_RESIZE_EDGE_TOP_LEFT,
    };
}

fn activateSurface(state: *WaylandState, token: []const u8) !void {
    const manager = state.globals.activation_manager orelse return error.ActivationUnsupported;
    const owned_window = activeOrPrimaryWindow(state) orelse return error.WindowUnavailable;
    const token_z = try activation.dupTokenZ(state.allocator, token);
    defer state.allocator.free(token_z);

    c.xdg_activation_v1_activate(manager, token_z.ptr, owned_window.surface);
    try state.display.flush();
}

fn createTrackedWindow(state: *WaylandState, options: anytype) !*window.WaylandWindow {
    const compositor = state.globals.compositor orelse return error.MissingCompositor;
    const wm_base = state.globals.wm_base orelse return error.MissingShell;

    const owned_window = try state.allocator.create(window.WaylandWindow);
    errdefer state.allocator.destroy(owned_window);

    owned_window.* = try window.WaylandWindow.create(
        state.allocator,
        compositor,
        wm_base,
        state.globals.decoration_manager,
        state.globals.viewporter,
        state.globals.fractional_scale_manager,
        options,
    );
    errdefer owned_window.deinit();

    if (c.wl_surface_add_listener(owned_window.surface, &surface_listener, state) != 0) {
        return error.SurfaceListenerFailed;
    }
    if (owned_window.decoration) |decoration| {
        if (c.zxdg_toplevel_decoration_v1_add_listener(decoration, &decoration_listener, state) != 0) {
            return error.DecorationListenerFailed;
        }
    }
    if (owned_window.fractional_scale) |surface_fractional_scale| {
        if (c.wp_fractional_scale_v1_add_listener(surface_fractional_scale, &fractional_scale_listener, state) != 0) {
            return error.SurfaceListenerFailed;
        }
    }
    if (c.xdg_surface_add_listener(owned_window.xdg_surface, &xdg_surface_listener, state) != 0) {
        return error.SurfaceListenerFailed;
    }
    if (c.xdg_toplevel_add_listener(owned_window.xdg_toplevel, &xdg_toplevel_listener, state) != 0) {
        return error.ToplevelListenerFailed;
    }

    try state.windows.append(state.allocator, owned_window);
    return owned_window;
}

fn closeTrackedWindow(state: *WaylandState, surface: *c.wl_surface) void {
    for (state.windows.items, 0..) |owned_window, index| {
        if (owned_window.surface != surface) continue;
        clearWindowFocus(state, surface);
        const removed = state.windows.orderedRemove(index);
        removed.deinit();
        state.allocator.destroy(removed);
        if (state.windows.items.len == 0) state.running = false;
        return;
    }
}

fn primaryWindow(state: *const WaylandState) ?*window.WaylandWindow {
    if (state.windows.items.len == 0) return null;
    return state.windows.items[0];
}

fn activeOrPrimaryWindow(state: *const WaylandState) ?*window.WaylandWindow {
    if (state.input_state.keyboard.focused_surface) |surface| {
        if (findWindowBySurface(state, surface)) |owned_window| return owned_window;
    }
    if (state.input_state.pointer.focused_surface) |surface| {
        if (findWindowBySurface(state, surface)) |owned_window| return owned_window;
    }
    return primaryWindow(state);
}

fn windowCount(state: *const WaylandState) usize {
    var count: usize = 0;
    for (state.windows.items) |owned_window| {
        if (!owned_window.close_requested) count += 1;
    }
    return count;
}

fn findWindowBySurface(state: *const WaylandState, surface: *c.wl_surface) ?*window.WaylandWindow {
    for (state.windows.items) |owned_window| {
        if (owned_window.surface == surface) return owned_window;
    }
    return null;
}

fn findWindowByXdgSurface(state: *const WaylandState, xdg_surface: *c.xdg_surface) ?*window.WaylandWindow {
    for (state.windows.items) |owned_window| {
        if (owned_window.xdg_surface == xdg_surface) return owned_window;
    }
    return null;
}

fn findWindowByToplevel(state: *const WaylandState, xdg_toplevel: *c.xdg_toplevel) ?*window.WaylandWindow {
    for (state.windows.items) |owned_window| {
        if (owned_window.xdg_toplevel == xdg_toplevel) return owned_window;
    }
    return null;
}

fn findWindowByDecoration(state: *const WaylandState, decoration: *c.zxdg_toplevel_decoration_v1) ?*window.WaylandWindow {
    for (state.windows.items) |owned_window| {
        if (owned_window.decoration != null and owned_window.decoration.? == decoration) return owned_window;
    }
    return null;
}

fn findWindowByFractionalScale(state: *const WaylandState, fractional_scale: *c.wp_fractional_scale_v1) ?*window.WaylandWindow {
    for (state.windows.items) |owned_window| {
        if (owned_window.fractional_scale != null and owned_window.fractional_scale.? == fractional_scale) return owned_window;
    }
    return null;
}

fn clearWindowFocus(state: *WaylandState, surface: *c.wl_surface) void {
    if (state.input_state.pointer.focused_surface == surface) {
        state.input_state.pointer.noteLeave(state.input_state.pointer.serials.latestPointer());
    }
    if (state.input_state.keyboard.focused_surface == surface) {
        state.input_state.keyboard.noteLeave();
    }
}

fn snapshotWindowInfo(state: *const WaylandState, owned_window: *const window.WaylandWindow) types.LinuxWindowInfo {
    const active = state.input_state.keyboard.focused_surface == owned_window.surface;
    const hovered = state.input_state.pointer.entered and
        state.input_state.pointer.focused_surface == owned_window.surface;
    return owned_window.snapshot(&state.outputs, active, hovered);
}

fn applyCurrentCursor(state: *WaylandState, owned_window: ?*window.WaylandWindow) void {
    if (state.pointer) |pointer| {
        if (state.cursor_manager) |*manager| {
            const serial_value = state.input_state.pointer.serials.latestPointer();
            if (serial_value != 0 and state.input_state.pointer.entered) {
                const cursor_kind = if (owned_window) |window_ref|
                    window_ref.decorationCursor(
                        state.input_state.pointer.surface_x,
                        state.input_state.pointer.surface_y,
                    ) orelse state.input_state.pointer.cursor
                else
                    state.input_state.pointer.cursor;
                const scale = if (owned_window) |window_ref|
                    window_ref.primaryOutputScale(&state.outputs)
                else
                    1;
                manager.apply(pointer, serial_value, cursor_kind, scale) catch {};
            }
        }
    }
}

fn presentWindowIfConfigured(state: *WaylandState, owned_window: *window.WaylandWindow) void {
    if (!owned_window.configured) return;
    const shm = state.globals.shm orelse return;
    owned_window.present(shm, &state.outputs) catch {
        state.running = false;
    };
}

fn presentAllConfiguredWindows(state: *WaylandState) void {
    for (state.windows.items) |owned_window| {
        presentWindowIfConfigured(state, owned_window);
    }
}

fn pushWindowEvent(state: *WaylandState, event: ui_input.WindowEvent) void {
    state.events.push(state.allocator, .{ .window = event }) catch {};
}

fn pushPointerEvent(state: *WaylandState, event: ui_input.PointerEvent) void {
    state.events.push(state.allocator, .{ .pointer = event }) catch {};
}

fn pushKeyEvent(state: *WaylandState, event: ui_input.KeyEvent) void {
    state.events.push(state.allocator, .{ .key = event }) catch {};
}

fn pointerButtonFromWayland(button: u32) ui_input.PointerButton {
    return switch (button) {
        0x110 => .left,
        0x111 => .right,
        0x112 => .middle,
        else => .other,
    };
}

fn toplevelStatesContain(states: ?*c.wl_array, expected: u32) bool {
    const wl_states = states orelse return false;
    const raw = wl_states.data orelse return false;
    const count = wl_states.size / @sizeOf(u32);
    const values: [*]const u32 = @ptrCast(@alignCast(raw));
    for (values[0..count]) |value| {
        if (value == expected) return true;
    }
    return false;
}

fn latestSelectionSerial(state: *const WaylandState) u32 {
    const keyboard_serial = state.input_state.keyboard.serials.latestKeyboard();
    if (keyboard_serial != 0) return keyboard_serial;
    return state.input_state.pointer.serials.latestPointer();
}

fn installClipboardSource(state: *WaylandState) !void {
    const manager = state.globals.data_device_manager orelse return error.ClipboardUnavailable;
    const data_device = state.data_device orelse return error.ClipboardUnavailable;
    const serial_value = latestSelectionSerial(state);
    if (serial_value == 0) return error.SelectionSerialUnavailable;

    if (state.clipboard_source) |source| {
        c.wl_data_source_destroy(source);
        state.clipboard_source = null;
    }

    const source = c.wl_data_device_manager_create_data_source(manager) orelse return error.ClipboardUnavailable;
    errdefer c.wl_data_source_destroy(source);

    for (clipboard.text_mime_types) |mime_type| {
        const mime_type_z = try state.allocator.dupeZ(u8, mime_type);
        defer state.allocator.free(mime_type_z);
        c.wl_data_source_offer(source, mime_type_z.ptr);
    }
    if (c.wl_data_source_add_listener(source, &data_source_listener, state) != 0) {
        return error.DataDeviceListenerFailed;
    }

    c.wl_data_device_set_selection(data_device, source, serial_value);
    try state.display.flush();
    state.clipboard_source = source;
}

fn installPrimarySelectionSource(state: *WaylandState) !void {
    const manager = state.globals.primary_selection_manager orelse return error.ClipboardUnavailable;
    const device = state.primary_selection_device orelse return error.ClipboardUnavailable;
    const serial_value = latestSelectionSerial(state);
    if (serial_value == 0) return error.SelectionSerialUnavailable;

    if (state.primary_selection_source) |source| {
        c.zwp_primary_selection_source_v1_destroy(source);
        state.primary_selection_source = null;
    }

    const source = c.zwp_primary_selection_device_manager_v1_create_source(manager) orelse return error.ClipboardUnavailable;
    errdefer c.zwp_primary_selection_source_v1_destroy(source);

    for (clipboard.text_mime_types) |mime_type| {
        const mime_type_z = try state.allocator.dupeZ(u8, mime_type);
        defer state.allocator.free(mime_type_z);
        c.zwp_primary_selection_source_v1_offer(source, mime_type_z.ptr);
    }
    if (c.zwp_primary_selection_source_v1_add_listener(source, &primary_selection_source_listener, state) != 0) {
        return error.DataDeviceListenerFailed;
    }

    c.zwp_primary_selection_device_v1_set_selection(device, source, serial_value);
    try state.display.flush();
    state.primary_selection_source = source;
}

fn writeOwnedSelectionToFd(bytes: []const u8, fd: i32) void {
    defer _ = std.os.linux.close(fd);
    var remaining = bytes;
    while (remaining.len != 0) {
        const written = std.c.write(fd, remaining.ptr, remaining.len);
        if (written <= 0) break;
        remaining = remaining[@intCast(written)..];
    }
}

fn dataSourceTarget(
    data: ?*anyopaque,
    source: ?*c.wl_data_source,
    mime_type: ?[*:0]const u8,
) callconv(.c) void {
    _ = data;
    _ = source;
    _ = mime_type;
}

fn dataSourceSend(
    data: ?*anyopaque,
    source: ?*c.wl_data_source,
    mime_type: [*c]const u8,
    fd: i32,
) callconv(.c) void {
    _ = source;
    _ = mime_type;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const text = state.owned_clipboard_text orelse {
        _ = std.os.linux.close(fd);
        return;
    };
    writeOwnedSelectionToFd(text, fd);
}

fn dataSourceCancelled(data: ?*anyopaque, source: ?*c.wl_data_source) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const resolved = source orelse return;
    if (state.clipboard_source == resolved) state.clipboard_source = null;
    c.wl_data_source_destroy(resolved);
}

fn dataSourceDndDropPerformed(data: ?*anyopaque, source: ?*c.wl_data_source) callconv(.c) void {
    _ = data;
    _ = source;
}

fn dataSourceDndFinished(data: ?*anyopaque, source: ?*c.wl_data_source) callconv(.c) void {
    _ = data;
    _ = source;
}

fn dataSourceAction(data: ?*anyopaque, source: ?*c.wl_data_source, action: u32) callconv(.c) void {
    _ = data;
    _ = source;
    _ = action;
}

const data_source_listener = c.wl_data_source_listener{
    .target = dataSourceTarget,
    .send = dataSourceSend,
    .cancelled = dataSourceCancelled,
    .dnd_drop_performed = dataSourceDndDropPerformed,
    .dnd_finished = dataSourceDndFinished,
    .action = dataSourceAction,
};

fn primarySelectionSourceSend(
    data: ?*anyopaque,
    source: ?*c.zwp_primary_selection_source_v1,
    mime_type: [*c]const u8,
    fd: i32,
) callconv(.c) void {
    _ = source;
    _ = mime_type;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const text = state.owned_primary_selection_text orelse {
        _ = std.os.linux.close(fd);
        return;
    };
    writeOwnedSelectionToFd(text, fd);
}

fn primarySelectionSourceCancelled(
    data: ?*anyopaque,
    source: ?*c.zwp_primary_selection_source_v1,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const resolved = source orelse return;
    if (state.primary_selection_source == resolved) state.primary_selection_source = null;
    c.zwp_primary_selection_source_v1_destroy(resolved);
}

const primary_selection_source_listener = c.zwp_primary_selection_source_v1_listener{
    .send = primarySelectionSourceSend,
    .cancelled = primarySelectionSourceCancelled,
};

fn selectPrimaryOutputId(state: *const WaylandState) ?output.OutputId {
    if (activeOrPrimaryWindow(state)) |owned_window| {
        var entered = owned_window.entered_outputs.iterator();
        if (entered.next()) |entry| return entry.key_ptr.*;
    }

    var iterator = state.outputs.iterator();
    if (iterator.next()) |entry| return entry.key_ptr.*;
    return null;
}

fn registryGlobal(
    data: ?*anyopaque,
    registry: ?*c.wl_registry,
    name: u32,
    interface: [*c]const u8,
    version: u32,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const wl_registry = registry orelse return;
    const iface = std.mem.span(@as([*:0]const u8, @ptrCast(interface)));

    if (std.mem.eql(u8, iface, "wl_compositor")) {
        const bound = c.wl_registry_bind(wl_registry, name, &c.wl_compositor_interface, @min(version, 4));
        state.globals.compositor = @ptrCast(@alignCast(bound));
    } else if (std.mem.eql(u8, iface, "xdg_activation_v1")) {
        const bound = c.wl_registry_bind(wl_registry, name, &c.xdg_activation_v1_interface, 1);
        state.globals.activation_manager = @ptrCast(@alignCast(bound));
    } else if (std.mem.eql(u8, iface, "wl_data_device_manager")) {
        const bound = c.wl_registry_bind(wl_registry, name, &c.wl_data_device_manager_interface, @min(version, 3));
        state.globals.data_device_manager = @ptrCast(@alignCast(bound));
    } else if (std.mem.eql(u8, iface, "zwp_primary_selection_device_manager_v1")) {
        const bound = c.wl_registry_bind(wl_registry, name, &c.zwp_primary_selection_device_manager_v1_interface, 1);
        state.globals.primary_selection_manager = @ptrCast(@alignCast(bound));
    } else if (std.mem.eql(u8, iface, "wp_viewporter")) {
        const bound = c.wl_registry_bind(wl_registry, name, &c.wp_viewporter_interface, 1);
        state.globals.viewporter = @ptrCast(@alignCast(bound));
    } else if (std.mem.eql(u8, iface, "zxdg_decoration_manager_v1")) {
        const bound = c.wl_registry_bind(wl_registry, name, &c.zxdg_decoration_manager_v1_interface, 1);
        state.globals.decoration_manager = @ptrCast(@alignCast(bound));
    } else if (std.mem.eql(u8, iface, "wp_fractional_scale_manager_v1")) {
        const bound = c.wl_registry_bind(wl_registry, name, &c.wp_fractional_scale_manager_v1_interface, 1);
        state.globals.fractional_scale_manager = @ptrCast(@alignCast(bound));
    } else if (std.mem.eql(u8, iface, "wl_shm")) {
        const bound = c.wl_registry_bind(wl_registry, name, &c.wl_shm_interface, 1);
        state.globals.shm = @ptrCast(@alignCast(bound));
    } else if (std.mem.eql(u8, iface, "wl_seat")) {
        const bound = c.wl_registry_bind(wl_registry, name, &c.wl_seat_interface, @min(version, 7));
        state.globals.seat = @ptrCast(@alignCast(bound));
    } else if (std.mem.eql(u8, iface, "wl_output")) {
        const bound = c.wl_registry_bind(wl_registry, name, &c.wl_output_interface, @min(version, 4));
        const wl_output: *c.wl_output = @ptrCast(@alignCast(bound));
        if (c.wl_output_add_listener(wl_output, &output_listener, state) != 0) {
            c.wl_output_release(wl_output);
            return;
        }
        state.output_handles.put(state.allocator, @intFromPtr(wl_output), wl_output) catch {};
        state.output_globals.put(state.allocator, name, @intFromPtr(wl_output)) catch {};
        state.in_progress_outputs.put(
            state.allocator,
            @intFromPtr(wl_output),
            .{},
        ) catch {};
        state.globals.output_count += 1;
    } else if (std.mem.eql(u8, iface, "xdg_wm_base")) {
        const bound = c.wl_registry_bind(wl_registry, name, &c.xdg_wm_base_interface, 1);
        state.globals.wm_base = @ptrCast(@alignCast(bound));
    }
}

fn registryGlobalRemove(
    data: ?*anyopaque,
    registry: ?*c.wl_registry,
    name: u32,
) callconv(.c) void {
    _ = registry;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    if (state.output_globals.fetchRemove(name)) |removed| {
        const output_id = removed.value;
        for (state.windows.items) |owned_window| owned_window.noteOutputLeave(output_id);

        if (state.output_handles.fetchRemove(output_id)) |entry| {
            if (c.wl_output_get_version(entry.value) >= c.WL_OUTPUT_RELEASE_SINCE_VERSION) {
                c.wl_output_release(entry.value);
            } else {
                c.wl_proxy_destroy(@ptrCast(entry.value));
            }
        }
        if (state.outputs.fetchRemove(output_id)) |entry| {
            var display_info = entry.value;
            display_info.deinit(state.allocator);
        }
        if (state.in_progress_outputs.fetchRemove(output_id)) |entry| {
            var pending = entry.value;
            pending.deinit(state.allocator);
        }
        if (state.globals.output_count > 0) state.globals.output_count -= 1;
        presentAllConfiguredWindows(state);
    }
}

const registry_listener = c.wl_registry_listener{
    .global = registryGlobal,
    .global_remove = registryGlobalRemove,
};

fn seatCapabilities(
    data: ?*anyopaque,
    seat_ptr: ?*c.wl_seat,
    capabilities: u32,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const seat = seat_ptr orelse return;
    const has_pointer = (capabilities & c.WL_SEAT_CAPABILITY_POINTER) != 0;
    const has_keyboard = (capabilities & c.WL_SEAT_CAPABILITY_KEYBOARD) != 0;

    if (has_pointer and state.pointer == null) {
        const pointer = c.wl_seat_get_pointer(seat) orelse return;
        if (c.wl_pointer_add_listener(pointer, &pointer_listener, state) != 0) {
            c.wl_pointer_release(pointer);
        } else {
            state.pointer = pointer;
        }
    } else if (!has_pointer) {
        if (state.pointer) |pointer| {
            c.wl_pointer_release(pointer);
            state.pointer = null;
            state.input_state.pointer.entered = false;
        }
    }

    if (has_keyboard and state.keyboard_device == null) {
        const keyboard_device = c.wl_seat_get_keyboard(seat) orelse return;
        if (c.wl_keyboard_add_listener(keyboard_device, &keyboard_listener, state) != 0) {
            c.wl_keyboard_release(keyboard_device);
        } else {
            state.keyboard_device = keyboard_device;
        }
    } else if (!has_keyboard) {
        if (state.keyboard_device) |keyboard_device| {
            c.wl_keyboard_release(keyboard_device);
            state.keyboard_device = null;
            state.input_state.keyboard.noteLeave();
        }
    }
}

fn seatName(
    data: ?*anyopaque,
    seat_ptr: ?*c.wl_seat,
    name: [*c]const u8,
) callconv(.c) void {
    _ = seat_ptr;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    if (state.seat_name) |seat_name| state.allocator.free(seat_name);
    state.seat_name = state.allocator.dupe(u8, std.mem.span(@as([*:0]const u8, @ptrCast(name)))) catch null;
}

const seat_listener = c.wl_seat_listener{
    .capabilities = seatCapabilities,
    .name = seatName,
};

fn wmBasePing(
    data: ?*anyopaque,
    wm_base: ?*c.xdg_wm_base,
    serial: u32,
) callconv(.c) void {
    _ = data;
    const shell = wm_base orelse return;
    c.xdg_wm_base_pong(shell, serial);
}

const wm_base_listener = c.xdg_wm_base_listener{
    .ping = wmBasePing,
};

fn pointerEnter(
    data: ?*anyopaque,
    pointer: ?*c.wl_pointer,
    serial_value: u32,
    surface: ?*c.wl_surface,
    surface_x: c.wl_fixed_t,
    surface_y: c.wl_fixed_t,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const wl_pointer = pointer orelse return;
    state.input_state.pointer.noteEnter(
        serial_value,
        surface,
        c.wl_fixed_to_double(surface_x),
        c.wl_fixed_to_double(surface_y),
    );
    if (surface) |surface_ptr| {
        const window_id = @intFromPtr(surface_ptr);
        pushWindowEvent(state, .{
            .window_id = window_id,
            .kind = .hover,
            .hovered = true,
        });
        pushPointerEvent(state, .{
            .window_id = window_id,
            .phase = .enter,
            .x = @floatCast(c.wl_fixed_to_double(surface_x)),
            .y = @floatCast(c.wl_fixed_to_double(surface_y)),
        });
    }
    _ = wl_pointer;
    applyCurrentCursor(state, if (surface) |surface_ptr| findWindowBySurface(state, surface_ptr) else activeOrPrimaryWindow(state));
}

fn pointerLeave(
    data: ?*anyopaque,
    pointer: ?*c.wl_pointer,
    serial_value: u32,
    surface: ?*c.wl_surface,
) callconv(.c) void {
    _ = pointer;
    _ = surface;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    if (state.input_state.pointer.focused_surface) |focused_surface| {
        pushWindowEvent(state, .{
            .window_id = @intFromPtr(focused_surface),
            .kind = .hover,
            .hovered = false,
        });
        pushPointerEvent(state, .{
            .window_id = @intFromPtr(focused_surface),
            .phase = .leave,
            .x = @floatCast(state.input_state.pointer.surface_x),
            .y = @floatCast(state.input_state.pointer.surface_y),
        });
    }
    state.input_state.pointer.noteLeave(serial_value);
}

fn pointerMotion(
    data: ?*anyopaque,
    pointer: ?*c.wl_pointer,
    time_ms: u32,
    surface_x: c.wl_fixed_t,
    surface_y: c.wl_fixed_t,
) callconv(.c) void {
    _ = pointer;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    state.input_state.pointer.noteMotion(
        c.wl_fixed_to_double(surface_x),
        c.wl_fixed_to_double(surface_y),
    );
    const active_window = if (state.input_state.pointer.focused_surface) |focused_surface|
        findWindowBySurface(state, focused_surface)
    else
        activeOrPrimaryWindow(state);
    applyCurrentCursor(state, active_window);
    if (state.input_state.pointer.focused_surface) |focused_surface| {
        pushPointerEvent(state, .{
            .window_id = @intFromPtr(focused_surface),
            .phase = .move,
            .x = @floatCast(c.wl_fixed_to_double(surface_x)),
            .y = @floatCast(c.wl_fixed_to_double(surface_y)),
            .time_ms = time_ms,
        });
    }
}

fn pointerButton(
    data: ?*anyopaque,
    pointer: ?*c.wl_pointer,
    serial_value: u32,
    time_ms: u32,
    button: u32,
    state_value: u32,
) callconv(.c) void {
    _ = pointer;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    state.input_state.pointer.noteButton(serial_value, time_ms, button, state_value);
    if (state.input_state.pointer.focused_surface) |focused_surface| {
        if (findWindowBySurface(state, focused_surface)) |owned_window| {
            if (handleDecorationPointerButton(state, owned_window, serial_value, button, state_value)) {
                return;
            }
        }
        pushPointerEvent(state, .{
            .window_id = @intFromPtr(focused_surface),
            .phase = .button,
            .x = @floatCast(state.input_state.pointer.surface_x),
            .y = @floatCast(state.input_state.pointer.surface_y),
            .button = pointerButtonFromWayland(button),
            .pressed = state_value == c.WL_POINTER_BUTTON_STATE_PRESSED,
            .time_ms = time_ms,
        });
    }
}

fn pointerAxis(
    data: ?*anyopaque,
    pointer: ?*c.wl_pointer,
    time_ms: u32,
    axis: u32,
    value: c.wl_fixed_t,
) callconv(.c) void {
    _ = pointer;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    state.input_state.pointer.noteAxis(axis, c.wl_fixed_to_double(value));
    if (state.input_state.pointer.focused_surface) |focused_surface| {
        pushPointerEvent(state, .{
            .window_id = @intFromPtr(focused_surface),
            .phase = .scroll,
            .x = @floatCast(state.input_state.pointer.surface_x),
            .y = @floatCast(state.input_state.pointer.surface_y),
            .scroll_x = if (axis == c.WL_POINTER_AXIS_HORIZONTAL_SCROLL) @floatCast(c.wl_fixed_to_double(value)) else 0,
            .scroll_y = if (axis == c.WL_POINTER_AXIS_VERTICAL_SCROLL) @floatCast(c.wl_fixed_to_double(value)) else 0,
            .continuous = true,
            .time_ms = time_ms,
        });
    }
}

fn pointerFrame(data: ?*anyopaque, pointer: ?*c.wl_pointer) callconv(.c) void {
    _ = data;
    _ = pointer;
}

fn pointerAxisSource(data: ?*anyopaque, pointer: ?*c.wl_pointer, axis_source: u32) callconv(.c) void {
    _ = pointer;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    state.input_state.pointer.axis_source = axis_source;
}

fn pointerAxisStop(data: ?*anyopaque, pointer: ?*c.wl_pointer, time_ms: u32, axis: u32) callconv(.c) void {
    _ = pointer;
    _ = time_ms;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    switch (axis) {
        c.WL_POINTER_AXIS_VERTICAL_SCROLL => state.input_state.pointer.vertical_scroll = 0,
        c.WL_POINTER_AXIS_HORIZONTAL_SCROLL => state.input_state.pointer.horizontal_scroll = 0,
        else => {},
    }
}

fn pointerAxisDiscrete(data: ?*anyopaque, pointer: ?*c.wl_pointer, axis: u32, discrete: i32) callconv(.c) void {
    _ = pointer;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    state.input_state.pointer.noteAxis(axis, @floatFromInt(discrete));
}

const pointer_listener = c.wl_pointer_listener{
    .enter = pointerEnter,
    .leave = pointerLeave,
    .motion = pointerMotion,
    .button = pointerButton,
    .axis = pointerAxis,
    .frame = pointerFrame,
    .axis_source = pointerAxisSource,
    .axis_stop = pointerAxisStop,
    .axis_discrete = pointerAxisDiscrete,
    .axis_value120 = null,
    .axis_relative_direction = null,
};

fn keyboardKeymap(
    data: ?*anyopaque,
    keyboard_device: ?*c.wl_keyboard,
    format: u32,
    fd: i32,
    size: u32,
) callconv(.c) void {
    _ = keyboard_device;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    if (format != c.WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) {
        _ = std.os.linux.close(fd);
        return;
    }
    state.input_state.keyboard.loadKeymap(fd, size) catch {
        state.running = false;
    };
}

fn keyboardEnter(
    data: ?*anyopaque,
    keyboard_device: ?*c.wl_keyboard,
    serial_value: u32,
    surface: ?*c.wl_surface,
    keys: ?*c.wl_array,
) callconv(.c) void {
    _ = keyboard_device;
    _ = keys;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    state.input_state.keyboard.noteEnter(serial_value, surface);
    if (surface) |surface_ptr| {
        pushWindowEvent(state, .{
            .window_id = @intFromPtr(surface_ptr),
            .kind = .focus,
            .focused = true,
        });
    }
}

fn keyboardLeave(
    data: ?*anyopaque,
    keyboard_device: ?*c.wl_keyboard,
    serial_value: u32,
    surface: ?*c.wl_surface,
) callconv(.c) void {
    _ = keyboard_device;
    _ = serial_value;
    _ = surface;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    if (state.input_state.keyboard.focused_surface) |focused_surface| {
        pushWindowEvent(state, .{
            .window_id = @intFromPtr(focused_surface),
            .kind = .focus,
            .focused = false,
        });
    }
    state.input_state.keyboard.noteLeave();
}

fn keyboardKey(
    data: ?*anyopaque,
    keyboard_device: ?*c.wl_keyboard,
    serial_value: u32,
    time_ms: u32,
    key: u32,
    state_value: u32,
) callconv(.c) void {
    _ = keyboard_device;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    state.input_state.keyboard.serials.record(.keyboard_enter, serial_value);
    state.input_state.keyboard.noteKey(time_ms, key, state_value);
    pushKeyEvent(state, .{
        .window_id = if (state.input_state.keyboard.focused_surface) |surface| @intFromPtr(surface) else null,
        .key_code = key,
        .pressed = state_value == c.WL_KEYBOARD_KEY_STATE_PRESSED,
        .modifiers = @as(ui_input.ModifierMask, @bitCast(state.input_state.keyboard.state.active_modifiers)),
        .time_ms = time_ms,
    });
}

fn keyboardModifiers(
    data: ?*anyopaque,
    keyboard_device: ?*c.wl_keyboard,
    serial_value: u32,
    mods_depressed: u32,
    mods_latched: u32,
    mods_locked: u32,
    group: u32,
) callconv(.c) void {
    _ = keyboard_device;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    state.input_state.keyboard.serials.record(.keyboard_enter, serial_value);
    state.input_state.keyboard.updateModifiers(mods_depressed, mods_latched, mods_locked, group);
}

fn keyboardRepeatInfo(
    data: ?*anyopaque,
    keyboard_device: ?*c.wl_keyboard,
    rate: i32,
    delay: i32,
) callconv(.c) void {
    _ = keyboard_device;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    state.input_state.keyboard.setRepeatInfo(rate, delay);
}

const keyboard_listener = c.wl_keyboard_listener{
    .keymap = keyboardKeymap,
    .enter = keyboardEnter,
    .leave = keyboardLeave,
    .key = keyboardKey,
    .modifiers = keyboardModifiers,
    .repeat_info = keyboardRepeatInfo,
};

fn destroyDataOffer(state: *WaylandState, offer_id: usize) void {
    if (state.clipboard_offers.fetchRemove(offer_id)) |entry| {
        var offer = entry.value;
        offer.deinit(state.allocator);
        c.wl_data_offer_destroy(@ptrFromInt(offer_id));
    }
}

fn maybeDestroyDataOffer(state: *WaylandState, offer_id: usize) void {
    if (state.clipboard_state.selection_offer == offer_id) return;
    if (state.clipboard_state.drag.offer_id == offer_id) return;
    destroyDataOffer(state, offer_id);
}

fn destroyPrimarySelectionOffer(state: *WaylandState, offer_id: usize) void {
    if (state.primary_selection_offers.fetchRemove(offer_id)) |entry| {
        var offer = entry.value;
        offer.deinit(state.allocator);
        c.zwp_primary_selection_offer_v1_destroy(@ptrFromInt(offer_id));
    }
}

fn maybeDestroyPrimarySelectionOffer(state: *WaylandState, offer_id: usize) void {
    if (state.clipboard_state.primary_selection_offer == offer_id) return;
    destroyPrimarySelectionOffer(state, offer_id);
}

fn dataOfferMimeType(
    data: ?*anyopaque,
    wl_data_offer: ?*c.wl_data_offer,
    mime_type: [*c]const u8,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const offer_ptr = wl_data_offer orelse return;
    const offer_id = @intFromPtr(offer_ptr);
    const offer = state.clipboard_offers.getPtr(offer_id) orelse return;
    offer.addMimeType(state.allocator, std.mem.span(@as([*:0]const u8, @ptrCast(mime_type)))) catch {};
}

fn dataOfferSourceActions(
    data: ?*anyopaque,
    wl_data_offer: ?*c.wl_data_offer,
    source_actions: u32,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const offer_ptr = wl_data_offer orelse return;
    if (state.clipboard_offers.getPtr(@intFromPtr(offer_ptr))) |offer| {
        offer.source_actions = source_actions;
    }
}

fn dataOfferAction(
    data: ?*anyopaque,
    wl_data_offer: ?*c.wl_data_offer,
    selected_action: u32,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const offer_ptr = wl_data_offer orelse return;
    if (state.clipboard_offers.getPtr(@intFromPtr(offer_ptr))) |offer| {
        offer.selected_action = selected_action;
    }
}

const data_offer_listener = c.wl_data_offer_listener{
    .offer = dataOfferMimeType,
    .source_actions = dataOfferSourceActions,
    .action = dataOfferAction,
};

fn dataDeviceOffer(
    data: ?*anyopaque,
    data_device: ?*c.wl_data_device,
    wl_data_offer: ?*c.wl_data_offer,
) callconv(.c) void {
    _ = data_device;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const offer_ptr = wl_data_offer orelse return;
    const offer_id = @intFromPtr(offer_ptr);
    state.clipboard_offers.put(state.allocator, offer_id, .{}) catch return;
    if (c.wl_data_offer_add_listener(offer_ptr, &data_offer_listener, state) != 0) {
        destroyDataOffer(state, offer_id);
    }
}

fn dataDeviceEnter(
    data: ?*anyopaque,
    data_device: ?*c.wl_data_device,
    serial_value: u32,
    surface: ?*c.wl_surface,
    x: c.wl_fixed_t,
    y: c.wl_fixed_t,
    wl_data_offer: ?*c.wl_data_offer,
) callconv(.c) void {
    _ = data_device;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const old_offer = state.clipboard_state.drag.offer_id;
    const offer_id = if (wl_data_offer) |offer_ptr| @intFromPtr(offer_ptr) else null;
    const offer = if (offer_id) |id| state.clipboard_offers.getPtr(id) else null;
    if (wl_data_offer) |offer_ptr| {
        const mime_type = if (offer) |resolved| resolved.preferredTextMime() else null;
        if (mime_type) |accepted_mime| {
            const accepted_mime_z = state.allocator.dupeZ(u8, accepted_mime) catch null;
            if (accepted_mime_z) |mime_z| {
                defer state.allocator.free(mime_z);
                c.wl_data_offer_accept(offer_ptr, serial_value, mime_z.ptr);
            }
        } else {
            c.wl_data_offer_accept(offer_ptr, serial_value, null);
        }
    }
    state.clipboard_state.drag.noteEnter(
        serial_value,
        if (surface) |surface_ptr| @intFromPtr(surface_ptr) else null,
        c.wl_fixed_to_double(x),
        c.wl_fixed_to_double(y),
        offer_id,
        offer,
    );
    if (old_offer) |previous| {
        if (offer_id == null or previous != offer_id.?) maybeDestroyDataOffer(state, previous);
    }
}

fn dataDeviceLeave(
    data: ?*anyopaque,
    data_device: ?*c.wl_data_device,
) callconv(.c) void {
    _ = data_device;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const offer_id = state.clipboard_state.drag.offer_id;
    state.clipboard_state.drag.noteLeave();
    if (offer_id) |id| maybeDestroyDataOffer(state, id);
}

fn dataDeviceMotion(
    data: ?*anyopaque,
    data_device: ?*c.wl_data_device,
    time_ms: u32,
    x: c.wl_fixed_t,
    y: c.wl_fixed_t,
) callconv(.c) void {
    _ = data_device;
    _ = time_ms;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    state.clipboard_state.drag.noteMotion(
        c.wl_fixed_to_double(x),
        c.wl_fixed_to_double(y),
    );
}

fn dataDeviceDrop(
    data: ?*anyopaque,
    data_device: ?*c.wl_data_device,
) callconv(.c) void {
    _ = data_device;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    state.clipboard_state.drag.noteDrop();
}

fn dataDeviceSelection(
    data: ?*anyopaque,
    data_device: ?*c.wl_data_device,
    wl_data_offer: ?*c.wl_data_offer,
) callconv(.c) void {
    _ = data_device;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const previous_offer = state.clipboard_state.selection_offer;
    if (wl_data_offer) |offer_ptr| {
        const offer_id = @intFromPtr(offer_ptr);
        state.clipboard_state.noteSelection(offer_id, state.clipboard_offers.getPtr(offer_id));
    } else {
        state.clipboard_state.noteSelection(null, null);
    }
    if (previous_offer) |offer_id| {
        if (state.clipboard_state.selection_offer == null or offer_id != state.clipboard_state.selection_offer.?) {
            maybeDestroyDataOffer(state, offer_id);
        }
    }
}

const data_device_listener = c.wl_data_device_listener{
    .data_offer = dataDeviceOffer,
    .enter = dataDeviceEnter,
    .leave = dataDeviceLeave,
    .motion = dataDeviceMotion,
    .drop = dataDeviceDrop,
    .selection = dataDeviceSelection,
};

fn primarySelectionOfferMimeType(
    data: ?*anyopaque,
    offer_ptr: ?*c.zwp_primary_selection_offer_v1,
    mime_type: [*c]const u8,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const offer = offer_ptr orelse return;
    const offer_id = @intFromPtr(offer);
    const entry = state.primary_selection_offers.getPtr(offer_id) orelse return;
    entry.addMimeType(state.allocator, std.mem.span(@as([*:0]const u8, @ptrCast(mime_type)))) catch {};
}

const primary_selection_offer_listener = c.zwp_primary_selection_offer_v1_listener{
    .offer = primarySelectionOfferMimeType,
};

fn primarySelectionDeviceOffer(
    data: ?*anyopaque,
    device: ?*c.zwp_primary_selection_device_v1,
    offer_ptr: ?*c.zwp_primary_selection_offer_v1,
) callconv(.c) void {
    _ = device;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const offer = offer_ptr orelse return;
    const offer_id = @intFromPtr(offer);
    state.primary_selection_offers.put(state.allocator, offer_id, .{}) catch return;
    if (c.zwp_primary_selection_offer_v1_add_listener(offer, &primary_selection_offer_listener, state) != 0) {
        destroyPrimarySelectionOffer(state, offer_id);
    }
}

fn primarySelectionDeviceSelection(
    data: ?*anyopaque,
    device: ?*c.zwp_primary_selection_device_v1,
    offer_ptr: ?*c.zwp_primary_selection_offer_v1,
) callconv(.c) void {
    _ = device;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const previous_offer = state.clipboard_state.primary_selection_offer;
    if (offer_ptr) |offer| {
        const offer_id = @intFromPtr(offer);
        state.clipboard_state.notePrimarySelection(offer_id, state.primary_selection_offers.getPtr(offer_id));
    } else {
        state.clipboard_state.notePrimarySelection(null, null);
    }
    if (previous_offer) |offer_id| {
        if (state.clipboard_state.primary_selection_offer == null or offer_id != state.clipboard_state.primary_selection_offer.?) {
            maybeDestroyPrimarySelectionOffer(state, offer_id);
        }
    }
}

const primary_selection_device_listener = c.zwp_primary_selection_device_v1_listener{
    .data_offer = primarySelectionDeviceOffer,
    .selection = primarySelectionDeviceSelection,
};

fn outputGeometry(
    data: ?*anyopaque,
    wl_output: ?*c.wl_output,
    x: i32,
    y: i32,
    physical_width: i32,
    physical_height: i32,
    subpixel: i32,
    make: [*c]const u8,
    model: [*c]const u8,
    transform: i32,
) callconv(.c) void {
    _ = physical_width;
    _ = physical_height;
    _ = subpixel;
    _ = make;
    _ = model;
    _ = transform;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const output_ptr = wl_output orelse return;
    const output_id: output.OutputId = @intFromPtr(output_ptr);
    const pending = state.in_progress_outputs.getPtr(output_id) orelse return;
    pending.x = x;
    pending.y = y;
}

fn outputMode(
    data: ?*anyopaque,
    wl_output: ?*c.wl_output,
    flags: u32,
    width: i32,
    height: i32,
    refresh: i32,
) callconv(.c) void {
    _ = refresh;
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const output_ptr = wl_output orelse return;
    const output_id: output.OutputId = @intFromPtr(output_ptr);
    const pending = state.in_progress_outputs.getPtr(output_id) orelse return;
    if ((flags & c.WL_OUTPUT_MODE_CURRENT) != 0 or pending.width == null or pending.height == null) {
        pending.width = width;
        pending.height = height;
    }
}

fn outputDone(
    data: ?*anyopaque,
    wl_output: ?*c.wl_output,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const output_ptr = wl_output orelse return;
    const output_id: output.OutputId = @intFromPtr(output_ptr);
    const pending = state.in_progress_outputs.getPtr(output_id) orelse return;

    const complete = pending.complete(output_id) orelse return;
    if (state.outputs.fetchRemove(output_id)) |existing| {
        var old = existing.value;
        old.deinit(state.allocator);
    }
    const clone = complete.clone(state.allocator) catch return;
    state.outputs.put(state.allocator, output_id, clone) catch {
        var doomed = clone;
        doomed.deinit(state.allocator);
    };
}

fn outputScale(
    data: ?*anyopaque,
    wl_output: ?*c.wl_output,
    factor: i32,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const output_ptr = wl_output orelse return;
    const output_id: output.OutputId = @intFromPtr(output_ptr);
    if (state.in_progress_outputs.getPtr(output_id)) |pending| pending.scale = @max(factor, 1);
    if (state.outputs.getPtr(output_id)) |display_info| display_info.scale = @max(factor, 1);
}

fn outputName(
    data: ?*anyopaque,
    wl_output: ?*c.wl_output,
    name: [*c]const u8,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const output_ptr = wl_output orelse return;
    const output_id: output.OutputId = @intFromPtr(output_ptr);
    const pending = state.in_progress_outputs.getPtr(output_id) orelse return;
    if (pending.name) |existing| state.allocator.free(existing);
    pending.name = state.allocator.dupe(u8, std.mem.span(@as([*:0]const u8, @ptrCast(name)))) catch null;
}

fn outputDescription(
    data: ?*anyopaque,
    wl_output: ?*c.wl_output,
    description: [*c]const u8,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const output_ptr = wl_output orelse return;
    const output_id: output.OutputId = @intFromPtr(output_ptr);
    const pending = state.in_progress_outputs.getPtr(output_id) orelse return;
    if (pending.description) |existing| state.allocator.free(existing);
    pending.description = state.allocator.dupe(u8, std.mem.span(@as([*:0]const u8, @ptrCast(description)))) catch null;
}

const output_listener = c.wl_output_listener{
    .geometry = outputGeometry,
    .mode = outputMode,
    .done = outputDone,
    .scale = outputScale,
    .name = outputName,
    .description = outputDescription,
};

fn surfaceEnter(
    data: ?*anyopaque,
    surface: ?*c.wl_surface,
    wl_output: ?*c.wl_output,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const surface_ptr = surface orelse return;
    const output_ptr = wl_output orelse return;
    const owned_window = findWindowBySurface(state, surface_ptr) orelse return;
    owned_window.noteOutputEnter(state.allocator, @intFromPtr(output_ptr)) catch return;
    applyCurrentCursor(state, owned_window);
    presentWindowIfConfigured(state, owned_window);
}

fn surfaceLeave(
    data: ?*anyopaque,
    surface: ?*c.wl_surface,
    wl_output: ?*c.wl_output,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const surface_ptr = surface orelse return;
    const output_ptr = wl_output orelse return;
    const owned_window = findWindowBySurface(state, surface_ptr) orelse return;
    owned_window.noteOutputLeave(@intFromPtr(output_ptr));
    presentWindowIfConfigured(state, owned_window);
}

fn surfacePreferredBufferScale(
    data: ?*anyopaque,
    surface: ?*c.wl_surface,
    factor: i32,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const surface_ptr = surface orelse return;
    const owned_window = findWindowBySurface(state, surface_ptr) orelse return;
    owned_window.setPreferredBufferScale(factor);
    presentWindowIfConfigured(state, owned_window);
}

fn surfacePreferredBufferTransform(
    data: ?*anyopaque,
    surface: ?*c.wl_surface,
    transform: u32,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const surface_ptr = surface orelse return;
    const owned_window = findWindowBySurface(state, surface_ptr) orelse return;
    owned_window.setPreferredBufferTransform(transform);
    presentWindowIfConfigured(state, owned_window);
}

const surface_listener = c.wl_surface_listener{
    .enter = surfaceEnter,
    .leave = surfaceLeave,
    .preferred_buffer_scale = surfacePreferredBufferScale,
    .preferred_buffer_transform = surfacePreferredBufferTransform,
};

fn fractionalScalePreferred(
    data: ?*anyopaque,
    surface_fractional_scale: ?*c.wp_fractional_scale_v1,
    scale_120: u32,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const fractional_scale_ptr = surface_fractional_scale orelse return;
    const owned_window = findWindowByFractionalScale(state, fractional_scale_ptr) orelse return;
    owned_window.setPreferredFractionalScale(scale_120);
    applyCurrentCursor(state, owned_window);
    presentWindowIfConfigured(state, owned_window);
}

const fractional_scale_listener = c.wp_fractional_scale_v1_listener{
    .preferred_scale = fractionalScalePreferred,
};

fn decorationConfigure(
    data: ?*anyopaque,
    decoration: ?*c.zxdg_toplevel_decoration_v1,
    mode: u32,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const decoration_ptr = decoration orelse return;
    const owned_window = findWindowByDecoration(state, decoration_ptr) orelse return;
    owned_window.handleDecorationConfigure(mode);
    presentWindowIfConfigured(state, owned_window);
}

const decoration_listener = c.zxdg_toplevel_decoration_v1_listener{
    .configure = decorationConfigure,
};

fn xdgSurfaceConfigure(
    data: ?*anyopaque,
    xdg_surface: ?*c.xdg_surface,
    serial: u32,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const xdg_surface_ptr = xdg_surface orelse return;
    const owned_window = findWindowByXdgSurface(state, xdg_surface_ptr) orelse return;
    const shm = state.globals.shm orelse return;
    owned_window.onConfigure(serial, shm, &state.outputs) catch {
        state.running = false;
    };
}

const xdg_surface_listener = c.xdg_surface_listener{
    .configure = xdgSurfaceConfigure,
};

fn xdgToplevelConfigure(
    data: ?*anyopaque,
    xdg_toplevel: ?*c.xdg_toplevel,
    width: i32,
    height: i32,
    states: ?*c.wl_array,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const xdg_toplevel_ptr = xdg_toplevel orelse return;
    const owned_window = findWindowByToplevel(state, xdg_toplevel_ptr) orelse return;
    owned_window.onToplevelConfigure(
        width,
        height,
        toplevelStatesContain(states, c.XDG_TOPLEVEL_STATE_MAXIMIZED),
        toplevelStatesContain(states, c.XDG_TOPLEVEL_STATE_FULLSCREEN),
        toplevelStatesContain(states, c.XDG_TOPLEVEL_STATE_ACTIVATED),
        toplevelStatesContain(states, c.XDG_TOPLEVEL_STATE_TILED_LEFT),
        toplevelStatesContain(states, c.XDG_TOPLEVEL_STATE_TILED_RIGHT),
        toplevelStatesContain(states, c.XDG_TOPLEVEL_STATE_TILED_TOP),
        toplevelStatesContain(states, c.XDG_TOPLEVEL_STATE_TILED_BOTTOM),
    );
    pushWindowEvent(state, .{
        .window_id = @intFromPtr(owned_window.surface),
        .kind = .resize,
        .width = owned_window.width,
        .height = owned_window.height,
        .scale_factor = @as(f32, @floatFromInt(owned_window.preferredScale120(&state.outputs))) / 120.0,
    });
}

fn handleDecorationPointerButton(
    state: *WaylandState,
    owned_window: *window.WaylandWindow,
    serial_value: u32,
    button: u32,
    state_value: u32,
) bool {
    const hit = owned_window.decorationHitTest(
        state.input_state.pointer.surface_x,
        state.input_state.pointer.surface_y,
    );
    switch (hit) {
        .content => return false,
        else => {},
    }

    if (state_value != c.WL_POINTER_BUTTON_STATE_PRESSED) return true;

    if (button == 0x111 and hit == .titlebar) {
        const seat = state.globals.seat orelse return true;
        c.xdg_toplevel_show_window_menu(
            owned_window.xdg_toplevel,
            seat,
            serial_value,
            @intFromFloat(state.input_state.pointer.surface_x),
            @intFromFloat(state.input_state.pointer.surface_y),
        );
        state.display.flush() catch {};
        return true;
    }

    if (button != 0x110) return true;

    switch (hit) {
        .titlebar => {
            const seat = state.globals.seat orelse return true;
            c.xdg_toplevel_move(owned_window.xdg_toplevel, seat, serial_value);
            state.display.flush() catch {};
        },
        .resize => |edge| {
            const seat = state.globals.seat orelse return true;
            c.xdg_toplevel_resize(owned_window.xdg_toplevel, seat, serial_value, edge);
            state.display.flush() catch {};
        },
        .minimize => {
            c.xdg_toplevel_set_minimized(owned_window.xdg_toplevel);
            state.display.flush() catch {};
        },
        .maximize => {
            if (owned_window.maximized) {
                c.xdg_toplevel_unset_maximized(owned_window.xdg_toplevel);
            } else {
                c.xdg_toplevel_set_maximized(owned_window.xdg_toplevel);
            }
            state.display.flush() catch {};
        },
        .close => {
            pushWindowEvent(state, .{
                .window_id = @intFromPtr(owned_window.surface),
                .kind = .close_requested,
            });
            owned_window.close_requested = true;
            closeTrackedWindow(state, owned_window.surface);
            state.display.flush() catch {};
        },
        .content => return false,
    }

    return true;
}

fn xdgToplevelClose(
    data: ?*anyopaque,
    xdg_toplevel: ?*c.xdg_toplevel,
) callconv(.c) void {
    const state: *WaylandState = @ptrCast(@alignCast(data.?));
    const xdg_toplevel_ptr = xdg_toplevel orelse return;
    const owned_window = findWindowByToplevel(state, xdg_toplevel_ptr) orelse return;
    pushWindowEvent(state, .{
        .window_id = @intFromPtr(owned_window.surface),
        .kind = .close_requested,
    });
    owned_window.close_requested = true;
    closeTrackedWindow(state, owned_window.surface);
}

const xdg_toplevel_listener = c.xdg_toplevel_listener{
    .configure = xdgToplevelConfigure,
    .close = xdgToplevelClose,
    .configure_bounds = null,
    .wm_capabilities = null,
};

test "wayland client requires a shell display to initialize" {
    const allocator = std.testing.allocator;
    const result = WaylandClient.init(allocator, .{
        .title = "zigui-test",
        .width = 320,
        .height = 240,
    });
    if (result) |client| {
        var owned = client;
        owned.deinit();
    } else |err| {
        try std.testing.expect(
            err == error.DisplayUnavailable or
                err == error.MissingCompositor or
                err == error.MissingSharedMemory or
                err == error.MissingShell or
                err == error.NativeBackendNotImplemented,
        );
    }
}

test "clipboard state reports empty text when selection is absent" {
    var state = WaylandState{
        .allocator = std.testing.allocator,
        .display = undefined,
        .registry = undefined,
        .input_state = input.WaylandInputState.init(std.testing.allocator),
    };
    defer state.input_state.deinit();
    var client = WaylandClient{
        .allocator = std.testing.allocator,
        .state = &state,
    };
    try std.testing.expectError(error.NoClipboardText, client.readClipboardTextAlloc(std.testing.allocator));
}

test "primary selection reports empty text when selection is absent" {
    var state = WaylandState{
        .allocator = std.testing.allocator,
        .display = undefined,
        .registry = undefined,
        .input_state = input.WaylandInputState.init(std.testing.allocator),
    };
    defer state.input_state.deinit();
    var client = WaylandClient{
        .allocator = std.testing.allocator,
        .state = &state,
    };
    try std.testing.expectError(error.NoPrimarySelectionText, client.readPrimarySelectionTextAlloc(std.testing.allocator));
}

test "clipboard writes fall back to locally owned text" {
    var state = WaylandState{
        .allocator = std.testing.allocator,
        .display = undefined,
        .registry = undefined,
        .input_state = input.WaylandInputState.init(std.testing.allocator),
    };
    defer state.input_state.deinit();
    defer if (state.owned_clipboard_text) |text| std.testing.allocator.free(text);

    var client = WaylandClient{
        .allocator = std.testing.allocator,
        .state = &state,
    };
    try client.writeTextToClipboard(.clipboard, "hello");

    const text = try client.readClipboardTextAlloc(std.testing.allocator);
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("hello", text);
    try std.testing.expect(client.snapshot().clipboard.has_text);
}

test "primary selection writes fall back to locally owned text" {
    var state = WaylandState{
        .allocator = std.testing.allocator,
        .display = undefined,
        .registry = undefined,
        .input_state = input.WaylandInputState.init(std.testing.allocator),
    };
    defer state.input_state.deinit();
    defer if (state.owned_primary_selection_text) |text| std.testing.allocator.free(text);

    var client = WaylandClient{
        .allocator = std.testing.allocator,
        .state = &state,
    };
    try client.writeTextToClipboard(.primary, "selection");

    const text = try client.readPrimarySelectionTextAlloc(std.testing.allocator);
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("selection", text);
    try std.testing.expect(client.snapshot().primary_selection.has_text);
}

test "window snapshots track multiple wayland surfaces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var state = WaylandState{
        .allocator = allocator,
        .display = undefined,
        .registry = undefined,
        .input_state = input.WaylandInputState.init(allocator),
    };
    defer state.input_state.deinit();
    defer state.windows.deinit(allocator);

    const first = try allocator.create(window.WaylandWindow);
    first.* = .{
        .allocator = allocator,
        .surface = @ptrFromInt(0x1000),
        .xdg_surface = @ptrFromInt(0x2000),
        .xdg_toplevel = @ptrFromInt(0x3000),
        .title_z = try allocator.dupeZ(u8, "one"),
        .width = 800,
        .height = 600,
        .resizable = true,
        .decorations = .server,
    };

    const second = try allocator.create(window.WaylandWindow);
    second.* = .{
        .allocator = allocator,
        .surface = @ptrFromInt(0x4000),
        .xdg_surface = @ptrFromInt(0x5000),
        .xdg_toplevel = @ptrFromInt(0x6000),
        .title_z = try allocator.dupeZ(u8, "two"),
        .width = 640,
        .height = 480,
        .resizable = false,
        .decorations = .server,
        .fullscreen = true,
    };

    try state.windows.append(allocator, first);
    try state.windows.append(allocator, second);
    state.input_state.keyboard.focused_surface = second.surface;
    state.input_state.pointer.entered = true;
    state.input_state.pointer.focused_surface = first.surface;

    const client = WaylandClient{
        .allocator = allocator,
        .state = &state,
    };

    const snapshot = client.snapshot();
    try std.testing.expectEqual(@as(usize, 2), snapshot.window_count);
    try std.testing.expect(snapshot.active_window != null);
    try std.testing.expectEqual(@as(usize, @intFromPtr(second.surface)), snapshot.active_window.?.id);
    try std.testing.expect(snapshot.active_window.?.fullscreen);

    const infos = try client.windowInfosAlloc(std.testing.allocator);
    defer std.testing.allocator.free(infos);
    try std.testing.expectEqual(@as(usize, 2), infos.len);
}

test "activation fails cleanly when compositor support is absent" {
    var state = WaylandState{
        .allocator = std.testing.allocator,
        .display = undefined,
        .registry = undefined,
        .input_state = input.WaylandInputState.init(std.testing.allocator),
    };
    defer state.input_state.deinit();

    var client = WaylandClient{
        .allocator = std.testing.allocator,
        .state = &state,
    };
    try std.testing.expectError(error.ActivationUnsupported, client.activateFromToken("startup-token"));
}

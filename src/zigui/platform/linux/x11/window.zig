const std = @import("std");
const common = @import("../../common.zig");
const display = @import("display.zig");
const event = @import("event.zig");
const types = @import("../types.zig");

pub const X11Window = struct {
    allocator: std.mem.Allocator,
    handle: display.c.Window,
    wm_delete_window: display.c.Atom,
    options: common.WindowOptions,
    title_z: [:0]u8,
    width: u32,
    height: u32,
    close_requested: bool = false,
    active: bool = true,
    hovered: bool = false,
    fullscreen: bool = false,
    current_cursor: ?display.c.Cursor = null,

    pub fn create(allocator: std.mem.Allocator, x11: *display.X11Display, options: common.WindowOptions) !X11Window {
        const handle = display.c.XCreateSimpleWindow(
            x11.handle,
            x11.root,
            0,
            0,
            options.width,
            options.height,
            0,
            x11.black_pixel,
            x11.white_pixel,
        );
        if (handle == 0) return error.WindowCreationFailed;
        errdefer _ = display.c.XDestroyWindow(x11.handle, handle);

        const event_mask = display.c.ExposureMask |
            display.c.KeyPressMask |
            display.c.KeyReleaseMask |
            display.c.ButtonPressMask |
            display.c.ButtonReleaseMask |
            display.c.PointerMotionMask |
            display.c.StructureNotifyMask |
            display.c.FocusChangeMask |
            display.c.EnterWindowMask |
            display.c.LeaveWindowMask;
        _ = display.c.XSelectInput(x11.handle, handle, event_mask);

        const title = try allocator.dupeZ(u8, options.title);
        errdefer allocator.free(title);
        _ = display.c.XStoreName(x11.handle, handle, title.ptr);

        const wm_delete_window = display.c.XInternAtom(x11.handle, "WM_DELETE_WINDOW", display.c.False);
        var protocols = [_]display.c.Atom{wm_delete_window};
        _ = display.c.XSetWMProtocols(x11.handle, handle, &protocols, 1);

        _ = display.c.XMapWindow(x11.handle, handle);
        x11.flush();

        return .{
            .allocator = allocator,
            .handle = handle,
            .wm_delete_window = wm_delete_window,
            .options = options,
            .title_z = title,
            .width = options.width,
            .height = options.height,
        };
    }

    pub fn destroy(self: *X11Window, x11: *display.X11Display) void {
        if (self.current_cursor) |cursor| _ = display.c.XFreeCursor(x11.handle, cursor);
        self.allocator.free(self.title_z);
        _ = display.c.XDestroyWindow(x11.handle, self.handle);
    }

    pub fn run(self: *X11Window, x11: *display.X11Display) !void {
        var raw_event: display.c.XEvent = undefined;
        while (true) {
            _ = display.c.XNextEvent(x11.handle, &raw_event);
            const decoded = event.decode(&raw_event);
            if (event.requestsClose(decoded, self.wm_delete_window)) {
                self.close_requested = true;
                return;
            }
            switch (decoded) {
                .configure => |configure| {
                    self.width = configure.width;
                    self.height = configure.height;
                },
                else => {},
            }
        }
    }

    pub fn applyCursor(self: *X11Window, x11: *display.X11Display, cursor_kind: common.Cursor) void {
        const glyph = switch (cursor_kind) {
            .arrow => display.c.XC_left_ptr,
            .ibeam => display.c.XC_xterm,
            .pointing_hand => display.c.XC_hand2,
            .resize_left_right => display.c.XC_sb_h_double_arrow,
            .resize_up_down => display.c.XC_sb_v_double_arrow,
        };

        const cursor = display.c.XCreateFontCursor(x11.handle, glyph);
        if (cursor == 0) return;

        if (self.current_cursor) |previous| _ = display.c.XFreeCursor(x11.handle, previous);
        self.current_cursor = cursor;
        _ = display.c.XDefineCursor(x11.handle, self.handle, cursor);
        x11.flush();
    }

    pub fn snapshot(self: *const X11Window) types.LinuxWindowInfo {
        return .{
            .id = self.handle,
            .title = self.title_z,
            .width = self.width,
            .height = self.height,
            .scale_factor = 1.0,
            .active = self.active,
            .hovered = self.hovered,
            .fullscreen = self.fullscreen,
            .decorated = self.options.decorations,
            .resizable = self.options.resizable,
            .visible = !self.close_requested,
        };
    }

    pub fn setActive(self: *X11Window, active: bool) void {
        self.active = active;
    }

    pub fn setHovered(self: *X11Window, hovered: bool) void {
        self.hovered = hovered;
    }
};

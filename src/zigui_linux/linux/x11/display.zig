const builtin = @import("builtin");
const std = @import("std");
const types = @import("../types.zig");

const has_x11 = builtin.os.tag == .linux or builtin.os.tag == .freebsd;
pub const c = if (has_x11) @cImport({
    @cInclude("X11/Xatom.h");
    @cInclude("X11/cursorfont.h");
    @cInclude("X11/Xlib.h");
}) else struct {};

pub const X11Display = struct {
    handle: *c.Display,
    screen: c_int,
    root: c.Window,
    black_pixel: c_ulong,
    white_pixel: c_ulong,

    pub fn open(display_name: ?[*:0]const u8) !X11Display {
        if (!has_x11) return error.UnsupportedPlatform;

        const handle = c.XOpenDisplay(display_name) orelse return error.DisplayUnavailable;
        errdefer _ = c.XCloseDisplay(handle);

        const screen = c.XDefaultScreen(handle);
        return .{
            .handle = handle,
            .screen = screen,
            .root = c.XRootWindow(handle, screen),
            .black_pixel = c.XBlackPixel(handle, screen),
            .white_pixel = c.XWhitePixel(handle, screen),
        };
    }

    pub fn close(self: *X11Display) void {
        _ = c.XCloseDisplay(self.handle);
    }

    pub fn flush(self: *X11Display) void {
        _ = c.XFlush(self.handle);
    }

    pub fn pixelSize(self: *const X11Display) struct { width: i32, height: i32 } {
        return .{
            .width = c.XDisplayWidth(self.handle, self.screen),
            .height = c.XDisplayHeight(self.handle, self.screen),
        };
    }

    pub fn screenName(self: *const X11Display) []const u8 {
        _ = self;
        return "screen-0";
    }

    pub fn description(self: *const X11Display) []const u8 {
        return std.mem.span(c.XDisplayString(self.handle));
    }

    pub fn snapshot(self: *const X11Display) types.LinuxDisplayInfo {
        const size = self.pixelSize();
        return .{
            .id = self.root,
            .name = self.screenName(),
            .description = self.description(),
            .width = size.width,
            .height = size.height,
            .is_primary = true,
        };
    }
};

test "screen name stays on the first screen by default" {
    const fake_display = X11Display{
        .handle = @as(*c.Display, @ptrFromInt(1)),
        .screen = 0,
        .root = 0,
        .black_pixel = 0,
        .white_pixel = 0,
    };

    try std.testing.expectEqualStrings("screen-0", fake_display.screenName());
}

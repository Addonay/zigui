const std = @import("std");
const c = @import("c.zig").c;

pub const WaylandDisplay = struct {
    handle: *c.wl_display,
    server_name: []const u8,
    scale_factor: f32 = 1.0,

    pub fn connect(server_name: ?[]const u8) !WaylandDisplay {
        const handle = if (server_name) |name|
            blk: {
                var buffer: [256:0]u8 = undefined;
                if (name.len >= buffer.len) return error.NameTooLong;
                @memcpy(buffer[0..name.len], name);
                buffer[name.len] = 0;
                break :blk c.wl_display_connect(&buffer[0]);
            }
        else
            c.wl_display_connect(null);

        if (handle == null) return error.DisplayUnavailable;

        return .{
            .handle = handle.?,
            .server_name = server_name orelse "wayland-0",
        };
    }

    pub fn disconnect(self: *WaylandDisplay) void {
        c.wl_display_disconnect(self.handle);
    }

    pub fn dispatch(self: *WaylandDisplay) !void {
        const result = c.wl_display_dispatch(self.handle);
        if (result < 0) return error.DispatchFailed;
    }

    pub fn roundtrip(self: *WaylandDisplay) !void {
        const result = c.wl_display_roundtrip(self.handle);
        if (result < 0) return error.DispatchFailed;
    }

    pub fn flush(self: *WaylandDisplay) !void {
        const result = c.wl_display_flush(self.handle);
        if (result < 0) return error.DispatchFailed;
    }
};

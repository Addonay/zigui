const display = @import("display.zig");

pub const EventKind = enum {
    expose,
    key_press,
    configure,
    client_message,
    destroy,
    focus_in,
    focus_out,
    enter,
    leave,
    unknown,
};

pub const ConfigureEvent = struct {
    width: u32 = 0,
    height: u32 = 0,
};

pub const DecodedEvent = union(EventKind) {
    expose,
    key_press,
    configure: ConfigureEvent,
    client_message: c_long,
    destroy,
    focus_in,
    focus_out,
    enter,
    leave,
    unknown,
};

pub fn decode(raw: *const display.c.XEvent) DecodedEvent {
    return switch (raw.type) {
        display.c.Expose => .expose,
        display.c.KeyPress => .key_press,
        display.c.ConfigureNotify => .{ .configure = .{
            .width = @intCast(raw.xconfigure.width),
            .height = @intCast(raw.xconfigure.height),
        } },
        display.c.ClientMessage => .{ .client_message = raw.xclient.data.l[0] },
        display.c.DestroyNotify => .destroy,
        display.c.FocusIn => .focus_in,
        display.c.FocusOut => .focus_out,
        display.c.EnterNotify => .enter,
        display.c.LeaveNotify => .leave,
        else => .unknown,
    };
}

pub fn windowHandle(raw: *const display.c.XEvent) display.c.Window {
    return raw.xany.window;
}

pub fn requestsClose(decoded: DecodedEvent, wm_delete_window: display.c.Atom) bool {
    return switch (decoded) {
        .client_message => |atom| atom == @as(c_long, @intCast(wm_delete_window)),
        .destroy => true,
        else => false,
    };
}

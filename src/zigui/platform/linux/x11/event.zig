const display = @import("display.zig");

pub const EventKind = enum {
    expose,
    key_press,
    key_release,
    button_press,
    button_release,
    motion,
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

pub const KeyEvent = struct {
    key_code: u32 = 0,
    state: u32 = 0,
    time_ms: u32 = 0,
};

pub const ButtonEvent = struct {
    button: u32 = 0,
    x: f32 = 0,
    y: f32 = 0,
    state: u32 = 0,
    time_ms: u32 = 0,
};

pub const MotionEvent = struct {
    x: f32 = 0,
    y: f32 = 0,
    state: u32 = 0,
    time_ms: u32 = 0,
};

pub const DecodedEvent = union(EventKind) {
    expose,
    key_press: KeyEvent,
    key_release: KeyEvent,
    button_press: ButtonEvent,
    button_release: ButtonEvent,
    motion: MotionEvent,
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
        display.c.KeyPress => .{ .key_press = .{
            .key_code = @intCast(raw.xkey.keycode),
            .state = @intCast(raw.xkey.state),
            .time_ms = @intCast(raw.xkey.time),
        } },
        display.c.KeyRelease => .{ .key_release = .{
            .key_code = @intCast(raw.xkey.keycode),
            .state = @intCast(raw.xkey.state),
            .time_ms = @intCast(raw.xkey.time),
        } },
        display.c.ButtonPress => .{ .button_press = .{
            .button = @intCast(raw.xbutton.button),
            .x = @floatFromInt(raw.xbutton.x),
            .y = @floatFromInt(raw.xbutton.y),
            .state = @intCast(raw.xbutton.state),
            .time_ms = @intCast(raw.xbutton.time),
        } },
        display.c.ButtonRelease => .{ .button_release = .{
            .button = @intCast(raw.xbutton.button),
            .x = @floatFromInt(raw.xbutton.x),
            .y = @floatFromInt(raw.xbutton.y),
            .state = @intCast(raw.xbutton.state),
            .time_ms = @intCast(raw.xbutton.time),
        } },
        display.c.MotionNotify => .{ .motion = .{
            .x = @floatFromInt(raw.xmotion.x),
            .y = @floatFromInt(raw.xmotion.y),
            .state = @intCast(raw.xmotion.state),
            .time_ms = @intCast(raw.xmotion.time),
        } },
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

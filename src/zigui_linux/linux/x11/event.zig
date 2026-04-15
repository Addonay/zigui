const std = @import("std");
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

test "decode extracts configure and client message events" {
    var raw: display.c.XEvent = std.mem.zeroes(display.c.XEvent);

    raw.type = display.c.ConfigureNotify;
    raw.xconfigure.width = 1280;
    raw.xconfigure.height = 720;

    const configured = decode(&raw);
    try std.testing.expectEqual(@as(u32, 1280), configured.configure.width);
    try std.testing.expectEqual(@as(u32, 720), configured.configure.height);

    raw = std.mem.zeroes(display.c.XEvent);
    raw.type = display.c.ClientMessage;
    raw.xclient.data.l[0] = @as(c_long, 23);

    const client_message = decode(&raw);
    try std.testing.expectEqual(@as(c_long, 23), client_message.client_message);
}

test "requestsClose matches wm delete and destroy notifications" {
    try std.testing.expect(requestsClose(.destroy, 0));
    try std.testing.expect(requestsClose(.{ .client_message = 17 }, 17));
    try std.testing.expect(!requestsClose(.{ .client_message = 17 }, 18));
}

test "windowHandle returns the event target window" {
    var raw: display.c.XEvent = std.mem.zeroes(display.c.XEvent);
    raw.xany.window = @as(display.c.Window, 42);

    try std.testing.expectEqual(@as(display.c.Window, 42), windowHandle(&raw));
}

const std = @import("std");
const common = @import("../../zigui/common.zig");
const input = @import("../../zigui/input.zig");

pub const NativeEventKind = enum {
    flags_changed,
    key_down,
    key_up,
    text_input,
    mouse_enter,
    mouse_exit,
    mouse_move,
    mouse_down,
    mouse_up,
    scroll_wheel,
    pressure,
    magnify,
    swipe,
};

pub const NativeEvent = struct {
    kind: NativeEventKind,
    window_id: ?usize = null,
    window_height: ?f32 = null,
    x: f32 = 0,
    y: f32 = 0,
    button_number: u8 = 0,
    click_count: u32 = 1,
    key_code: u32 = 0,
    text: ?[]const u8 = null,
    modifiers: common.ModifierMask = .{},
    caps_lock: bool = false,
    repeat: bool = false,
    scroll_x: f32 = 0,
    scroll_y: f32 = 0,
    continuous: bool = false,
    pressure_stage: u8 = 0,
    pressure: f32 = 0,
    magnification: f32 = 0,
    delta_x: f32 = 0,
};

pub fn keyToNativeCodepoint(key: []const u8) ?u21 {
    if (std.mem.eql(u8, key, "space")) return ' ';
    if (std.mem.eql(u8, key, "backspace")) return 0x7f;
    if (std.mem.eql(u8, key, "escape")) return 0x1b;
    if (std.mem.eql(u8, key, "tab")) return 0x09;
    if (std.mem.eql(u8, key, "enter")) return 0x0d;
    if (std.mem.eql(u8, key, "return")) return 0x0d;
    if (std.mem.eql(u8, key, "delete")) return 0xf728;
    if (std.mem.eql(u8, key, "insert")) return 0xf727;
    if (std.mem.eql(u8, key, "up")) return 0xf700;
    if (std.mem.eql(u8, key, "down")) return 0xf701;
    if (std.mem.eql(u8, key, "left")) return 0xf702;
    if (std.mem.eql(u8, key, "right")) return 0xf703;
    if (std.mem.eql(u8, key, "pageup")) return 0xf72c;
    if (std.mem.eql(u8, key, "pagedown")) return 0xf72d;
    if (std.mem.eql(u8, key, "home")) return 0xf729;
    if (std.mem.eql(u8, key, "end")) return 0xf72b;

    if (key.len == 2 and key[0] == 'f') {
        const digit = key[1];
        if (digit >= '1' and digit <= '9') {
            return 0xf703 + @as(u21, @intCast(digit - '0'));
        }
    }

    if (key.len == 3 and key[0] == 'f') {
        const value = std.fmt.parseInt(u8, key[1..], 10) catch return null;
        if (value >= 10 and value <= 35) {
            return 0xf703 + @as(u21, value);
        }
    }

    return null;
}

pub fn keyToNativeAlloc(allocator: std.mem.Allocator, key: []const u8) ![]u8 {
    if (keyToNativeCodepoint(key)) |codepoint| {
        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(codepoint, &buf);
        return try allocator.dupe(u8, buf[0..len]);
    }

    return try allocator.dupe(u8, key);
}

pub fn platformInputFromNative(native_event: NativeEvent) ?input.InputEvent {
    const window_height = native_event.window_height;

    switch (native_event.kind) {
        .flags_changed => return null,
        .key_down => {
            return .{ .key = .{
                .window_id = native_event.window_id,
                .key_code = native_event.key_code,
                .pressed = true,
                .modifiers = native_event.modifiers,
                .time_ms = 0,
            } };
        },
        .key_up => {
            return .{ .key = .{
                .window_id = native_event.window_id,
                .key_code = native_event.key_code,
                .pressed = false,
                .modifiers = native_event.modifiers,
                .time_ms = 0,
            } };
        },
        .text_input => return if (native_event.text) |text| .{ .text = text } else null,
        .mouse_enter, .mouse_exit, .mouse_move, .mouse_down, .mouse_up, .scroll_wheel, .pressure, .magnify, .swipe => {
            const phase: input.PointerPhase = switch (native_event.kind) {
                .mouse_enter => .enter,
                .mouse_exit => .leave,
                .mouse_move => .move,
                .mouse_down, .mouse_up, .pressure => .button,
                .scroll_wheel, .magnify, .swipe => .scroll,
                .flags_changed, .key_down, .key_up, .text_input => .move,
            };

            const button: ?input.PointerButton = switch (native_event.button_number) {
                0 => .left,
                1 => .right,
                2 => .middle,
                else => .other,
            };

            const y = if (window_height) |height| height - native_event.y else native_event.y;

            return .{ .pointer = .{
                .window_id = native_event.window_id,
                .phase = phase,
                .x = native_event.x,
                .y = y,
                .button = if (native_event.kind == .mouse_move or native_event.kind == .mouse_enter or native_event.kind == .mouse_exit) null else button,
                .pressed = native_event.kind == .mouse_down or (native_event.kind == .pressure and native_event.pressure_stage != 0),
                .scroll_x = native_event.scroll_x,
                .scroll_y = if (native_event.kind == .magnify) native_event.magnification else native_event.scroll_y,
                .continuous = native_event.continuous,
                .time_ms = 0,
            } };
        },
    }
}

pub const EventState = struct {
    tracks_appkit_events: bool = true,
    queue: input.EventQueue = .{},

    pub fn deinit(self: *EventState, allocator: std.mem.Allocator) void {
        self.queue.deinit(allocator);
    }

    pub fn push(self: *EventState, allocator: std.mem.Allocator, event: input.InputEvent) !void {
        try self.queue.push(allocator, event);
    }

    pub fn pushWindowEvent(self: *EventState, allocator: std.mem.Allocator, event: input.WindowEvent) !void {
        try self.queue.push(allocator, .{ .window = event });
    }

    pub fn pushPointerEvent(self: *EventState, allocator: std.mem.Allocator, event: input.PointerEvent) !void {
        try self.queue.push(allocator, .{ .pointer = event });
    }

    pub fn pushKeyEvent(self: *EventState, allocator: std.mem.Allocator, event: input.KeyEvent) !void {
        try self.queue.push(allocator, .{ .key = event });
    }

    pub fn drainAlloc(self: *EventState, allocator: std.mem.Allocator) ![]input.InputEvent {
        return try self.queue.drainAlloc(allocator);
    }
};

test "key to native codepoint covers common keys" {
    try std.testing.expectEqual(@as(u21, 0x1b), keyToNativeCodepoint("escape").?);
    try std.testing.expectEqual(@as(u21, 0xf704), keyToNativeCodepoint("f1").?);
}

test "platform input maps pointer coordinates with flipped y" {
    const native = NativeEvent{
        .kind = .mouse_move,
        .window_id = 1,
        .window_height = 800,
        .x = 10,
        .y = 20,
    };

    const event = platformInputFromNative(native).?;
    try std.testing.expectEqual(@as(f32, 10), event.pointer.x);
    try std.testing.expectEqual(@as(f32, 780), event.pointer.y);
    try std.testing.expectEqual(input.PointerPhase.move, event.pointer.phase);
}

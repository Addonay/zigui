const std = @import("std");

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

pub const PointerButton = enum {
    left,
    right,
    middle,
    other,
};

pub const PointerPhase = enum {
    enter,
    leave,
    move,
    button,
    scroll,
};

pub const PointerEvent = struct {
    window_id: ?usize = null,
    phase: PointerPhase = .move,
    x: f32 = 0,
    y: f32 = 0,
    button: ?PointerButton = null,
    pressed: bool = false,
    scroll_x: f32 = 0,
    scroll_y: f32 = 0,
    continuous: bool = false,
    time_ms: u32 = 0,
};

pub const KeyEvent = struct {
    window_id: ?usize = null,
    key_code: u32 = 0,
    pressed: bool = false,
    modifiers: ModifierMask = .{},
    time_ms: u32 = 0,
};

pub const WindowEventKind = enum {
    focus,
    hover,
    resize,
    close_requested,
};

pub const WindowEvent = struct {
    window_id: usize,
    kind: WindowEventKind,
    focused: bool = false,
    hovered: bool = false,
    width: u32 = 0,
    height: u32 = 0,
    scale_factor: f32 = 1.0,
};

pub const InputEvent = union(enum) {
    pointer: PointerEvent,
    key: KeyEvent,
    text: []const u8,
    window: WindowEvent,
};

pub const EventQueue = struct {
    events: std.ArrayListUnmanaged(InputEvent) = .empty,

    pub fn push(self: *EventQueue, allocator: std.mem.Allocator, event: InputEvent) !void {
        try self.events.append(allocator, event);
    }

    pub fn drainAlloc(self: *EventQueue, allocator: std.mem.Allocator) ![]InputEvent {
        const owned = try allocator.alloc(InputEvent, self.events.items.len);
        @memcpy(owned, self.events.items);
        self.events.clearRetainingCapacity();
        return owned;
    }

    pub fn deinit(self: *EventQueue, allocator: std.mem.Allocator) void {
        self.events.deinit(allocator);
    }
};

test "event queue drains stored events in insertion order" {
    var queue = EventQueue{};
    defer queue.deinit(std.testing.allocator);

    try queue.push(std.testing.allocator, .{ .window = .{ .window_id = 1, .kind = .focus, .focused = true } });
    try queue.push(std.testing.allocator, .{ .pointer = .{ .window_id = 1, .phase = .move, .x = 10, .y = 20 } });

    const drained = try queue.drainAlloc(std.testing.allocator);
    defer std.testing.allocator.free(drained);

    try std.testing.expectEqual(@as(usize, 2), drained.len);
    try std.testing.expectEqual(@as(usize, 1), drained[0].window.window_id);
    try std.testing.expectEqual(@as(f32, 10), drained[1].pointer.x);
}

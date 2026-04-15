const std = @import("std");
const input = @import("../../zigui/input.zig");

pub const EventState = struct {
    tracks_win32_messages: bool = true,
    queue: input.EventQueue = .{},

    pub fn deinit(self: *EventState, allocator: std.mem.Allocator) void {
        self.queue.deinit(allocator);
    }

    pub fn drainAlloc(self: *EventState, allocator: std.mem.Allocator) ![]input.InputEvent {
        return self.queue.drainAlloc(allocator);
    }

    pub fn pushWindowEvent(
        self: *EventState,
        allocator: std.mem.Allocator,
        event: input.WindowEvent,
    ) !void {
        try self.queue.push(allocator, .{ .window = event });
    }

    pub fn pushPointerEvent(
        self: *EventState,
        allocator: std.mem.Allocator,
        event: input.PointerEvent,
    ) !void {
        try self.queue.push(allocator, .{ .pointer = event });
    }

    pub fn pushKeyEvent(
        self: *EventState,
        allocator: std.mem.Allocator,
        event: input.KeyEvent,
    ) !void {
        try self.queue.push(allocator, .{ .key = event });
    }
};

pub const WindowsEventState = EventState;

test "event state drains queued window events" {
    var instance = EventState{};
    defer instance.deinit(std.testing.allocator);

    try instance.pushWindowEvent(std.testing.allocator, .{
        .window_id = 1,
        .kind = .focus,
        .focused = true,
    });
    const drained = try instance.drainAlloc(std.testing.allocator);
    defer std.testing.allocator.free(drained);

    try std.testing.expectEqual(@as(usize, 1), drained.len);
    try std.testing.expect(drained[0].window.focused);
}

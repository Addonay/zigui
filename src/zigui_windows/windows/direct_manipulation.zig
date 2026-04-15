const std = @import("std");

pub const GestureKind = enum {
    none,
    scroll,
    pinch,
};

pub const PendingGesture = union(enum) {
    scroll: struct {
        delta_x: f32,
        delta_y: f32,
    },
    pinch: struct {
        scale_delta: f32,
    },
};

pub const DirectManipulationHandler = struct {
    scale_factor: f32 = 1.0,
    gesture_kind: GestureKind = .none,
    pending: std.ArrayListUnmanaged(PendingGesture) = .empty,

    pub fn init(scale_factor: f32) DirectManipulationHandler {
        return .{
            .scale_factor = scale_factor,
        };
    }

    pub fn deinit(self: *DirectManipulationHandler, allocator: std.mem.Allocator) void {
        self.pending.deinit(allocator);
    }

    pub fn setScaleFactor(self: *DirectManipulationHandler, scale_factor: f32) void {
        self.scale_factor = scale_factor;
    }

    pub fn recordScroll(
        self: *DirectManipulationHandler,
        allocator: std.mem.Allocator,
        delta_x: f32,
        delta_y: f32,
    ) !void {
        self.gesture_kind = .scroll;
        try self.pending.append(allocator, .{
            .scroll = .{
                .delta_x = delta_x,
                .delta_y = delta_y,
            },
        });
    }

    pub fn recordPinch(
        self: *DirectManipulationHandler,
        allocator: std.mem.Allocator,
        scale_delta: f32,
    ) !void {
        self.gesture_kind = .pinch;
        try self.pending.append(allocator, .{
            .pinch = .{
                .scale_delta = scale_delta,
            },
        });
    }

    pub fn drainAlloc(
        self: *DirectManipulationHandler,
        allocator: std.mem.Allocator,
    ) ![]PendingGesture {
        const drained = try allocator.alloc(PendingGesture, self.pending.items.len);
        @memcpy(drained, self.pending.items);
        self.pending.clearRetainingCapacity();
        return drained;
    }
};

test "direct manipulation handler records gestures" {
    var handler = DirectManipulationHandler.init(1.0);
    defer handler.deinit(std.testing.allocator);

    try handler.recordScroll(std.testing.allocator, 12.5, -3.0);
    try handler.recordPinch(std.testing.allocator, 1.2);

    const drained = try handler.drainAlloc(std.testing.allocator);
    defer std.testing.allocator.free(drained);

    try std.testing.expectEqual(@as(usize, 2), drained.len);
    try std.testing.expectEqual(GestureKind.pinch, handler.gesture_kind);
    switch (drained[0]) {
        .scroll => |scroll| {
            try std.testing.expectEqual(@as(f32, 12.5), scroll.delta_x);
            try std.testing.expectEqual(@as(f32, -3.0), scroll.delta_y);
        },
        else => return error.TestExpectedScrollGesture,
    }
    switch (drained[1]) {
        .pinch => |pinch| try std.testing.expectEqual(@as(f32, 1.2), pinch.scale_delta),
        else => return error.TestExpectedPinchGesture,
    }
}

const std = @import("std");

pub const FrameCallback = *const fn (*anyopaque) void;

pub const DisplayLink = struct {
    display_id: u64 = 0,
    running: bool = false,
    frame_requests: usize = 0,
    data: ?*anyopaque = null,
    callback: ?FrameCallback = null,

    pub fn new(display_id: u64, data: ?*anyopaque, callback: ?FrameCallback) !DisplayLink {
        return .{
            .display_id = display_id,
            .data = data,
            .callback = callback,
        };
    }

    pub fn start(self: *DisplayLink) !void {
        self.running = true;
    }

    pub fn stop(self: *DisplayLink) !void {
        self.running = false;
    }

    pub fn requestFrame(self: *DisplayLink) void {
        self.frame_requests += 1;
        if (self.running and self.callback) |callback| {
            if (self.data) |data| callback(data);
        }
    }

    pub fn deinit(self: *DisplayLink) void {
        self.running = false;
        self.callback = null;
        self.data = null;
    }
};

test "display link tracks start stop and frame requests" {
    var calls: usize = 0;
    const cb = struct {
        fn invoke(data: *anyopaque) void {
            const counter: *usize = @ptrCast(@alignCast(data));
            counter.* += 1;
        }
    }.invoke;

    var link = try DisplayLink.new(1, &calls, cb);
    defer link.deinit();

    try link.start();
    link.requestFrame();
    try std.testing.expectEqual(@as(usize, 1), calls);
    try std.testing.expectEqual(@as(usize, 1), link.frame_requests);

    try link.stop();
    link.requestFrame();
    try std.testing.expectEqual(@as(usize, 2), link.frame_requests);
    try std.testing.expect(!link.running);
}

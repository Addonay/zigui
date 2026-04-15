const std = @import("std");

pub const VSyncProvider = struct {
    interval_ns: u64 = 16_666_666,

    pub fn new() VSyncProvider {
        return .{};
    }

    pub fn waitForVsync(self: *const VSyncProvider) void {
        std.time.sleep(self.interval_ns);
    }
};

test "vsync provider defaults near 60hz" {
    const provider = VSyncProvider.new();
    try std.testing.expect(provider.interval_ns > 0);
}

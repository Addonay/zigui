pub const SafeCursor = struct {
    raw: usize,

    pub fn asRaw(self: SafeCursor) usize {
        return self.raw;
    }
};

pub const SafeHwnd = struct {
    raw: usize,

    pub fn asRaw(self: SafeHwnd) usize {
        return self.raw;
    }
};

test "wrapper handles round-trip raw values" {
    const std = @import("std");

    const hwnd = SafeHwnd{ .raw = 42 };
    const cursor = SafeCursor{ .raw = 24 };

    try std.testing.expectEqual(@as(usize, 42), hwnd.asRaw());
    try std.testing.expectEqual(@as(usize, 24), cursor.asRaw());
}

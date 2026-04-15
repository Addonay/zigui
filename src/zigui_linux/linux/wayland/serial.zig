const std = @import("std");

pub const SerialKind = enum {
    pointer_enter,
    pointer_button,
    keyboard_enter,
};

pub const SerialTracker = struct {
    last_pointer_serial: u32 = 0,
    last_keyboard_serial: u32 = 0,

    pub fn record(self: *SerialTracker, kind: SerialKind, serial: u32) void {
        switch (kind) {
            .pointer_enter, .pointer_button => self.last_pointer_serial = serial,
            .keyboard_enter => self.last_keyboard_serial = serial,
        }
    }

    pub fn latestPointer(self: SerialTracker) u32 {
        return self.last_pointer_serial;
    }

    pub fn latestKeyboard(self: SerialTracker) u32 {
        return self.last_keyboard_serial;
    }
};

test "serial tracker separates pointer and keyboard serials" {
    var tracker = SerialTracker{};
    tracker.record(.pointer_enter, 11);
    tracker.record(.keyboard_enter, 17);
    try std.testing.expectEqual(@as(u32, 11), tracker.latestPointer());
    try std.testing.expectEqual(@as(u32, 17), tracker.latestKeyboard());
}

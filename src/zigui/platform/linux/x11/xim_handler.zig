const std = @import("std");

pub const XimAvailability = enum {
    unavailable,
    basic,
    preedit,
};

pub const XimStyle = enum {
    callbacks,
    nothing,
    preedit_position,
};

pub const XimState = struct {
    availability: XimAvailability = .unavailable,
    style: XimStyle = .nothing,
    locale_name: []const u8 = "C",

    pub fn enableBasic(self: *XimState, locale_name: []const u8) void {
        self.availability = .basic;
        self.style = .callbacks;
        self.locale_name = locale_name;
    }

    pub fn enablePreedit(self: *XimState, locale_name: []const u8) void {
        self.availability = .preedit;
        self.style = .preedit_position;
        self.locale_name = locale_name;
    }

    pub fn disable(self: *XimState) void {
        self.* = .{};
    }

    pub fn supportsPreedit(self: XimState) bool {
        return self.availability == .preedit;
    }
};

test "xim handler tracks preedit support" {
    var state = XimState{};
    try std.testing.expect(!state.supportsPreedit());
    state.enablePreedit("en_US.UTF-8");
    try std.testing.expect(state.supportsPreedit());
}

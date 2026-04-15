const std = @import("std");
const common = @import("../../zigui/common.zig");

pub const KeyRepeatConfig = common.KeyRepeatConfig;
pub const ModifierMask = common.ModifierMask;
pub const KeyboardLayout = common.KeyboardLayout;
pub const KeyboardInfo = common.KeyboardInfo;

pub const KeyboardState = struct {
    repeat: KeyRepeatConfig = .{},
    has_hardware_layout: bool = false,
    active_modifiers: ModifierMask = .{},
    layout: KeyboardLayout = .unknown,

    pub fn snapshot(self: KeyboardState) KeyboardInfo {
        return .{
            .layout = self.layout,
            .repeat = self.repeat,
            .modifiers = self.active_modifiers,
            .compose_enabled = self.has_hardware_layout,
        };
    }
};

test "keyboard snapshot reflects active modifiers" {
    const state = KeyboardState{
        .has_hardware_layout = true,
        .active_modifiers = .{ .shift = true },
        .layout = .xkb,
    };
    const info = state.snapshot();
    try std.testing.expectEqual(KeyboardLayout.xkb, info.layout);
    try std.testing.expect(info.hasAnyModifier());
}

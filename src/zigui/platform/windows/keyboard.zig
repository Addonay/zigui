const std = @import("std");
const common = @import("../common.zig");

pub const KeyRepeatConfig = common.KeyRepeatConfig;
pub const ModifierMask = common.ModifierMask;
pub const KeyboardLayout = common.KeyboardLayout;
pub const KeyboardInfo = common.KeyboardInfo;

pub const KeyboardState = struct {
    uses_text_services_framework: bool = true,
    repeat: KeyRepeatConfig = .{},
    active_modifiers: ModifierMask = .{},
    layout: KeyboardLayout = .windows,

    pub fn snapshot(self: KeyboardState) KeyboardInfo {
        return .{
            .layout = self.layout,
            .repeat = self.repeat,
            .modifiers = self.active_modifiers,
            .compose_enabled = self.uses_text_services_framework,
        };
    }
};

test "keyboard snapshot reports the Windows layout" {
    const info = (KeyboardState{}).snapshot();
    try std.testing.expectEqual(KeyboardLayout.windows, info.layout);
    try std.testing.expect(info.compose_enabled);
}

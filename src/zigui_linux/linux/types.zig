const std = @import("std");
const common = @import("../../zigui/common.zig");

pub const LinuxClipboardKind = common.ClipboardKind;
pub const LinuxClipboardSnapshot = common.ClipboardSnapshot;
pub const LinuxDisplayInfo = common.DisplayInfo;
pub const LinuxWindowInfo = common.WindowInfo;
pub const LinuxWindowAppearance = common.WindowAppearance;
pub const LinuxWindowButtonLayout = common.WindowButtonLayout;
pub const LinuxPathPromptOptions = common.PathPromptOptions;
pub const LinuxPathList = common.PathList;
pub const LinuxPortalSettings = common.DesktopSettings;
pub const LinuxRuntimeSnapshot = common.RuntimeSnapshot;

test "runtime snapshot defaults to an empty runtime state" {
    const snapshot = LinuxRuntimeSnapshot{};
    try std.testing.expectEqualStrings("unknown", snapshot.compositor_name);
    try std.testing.expectEqual(@as(usize, 0), snapshot.display_count);
    try std.testing.expectEqual(@as(?LinuxWindowInfo, null), snapshot.active_window);
}

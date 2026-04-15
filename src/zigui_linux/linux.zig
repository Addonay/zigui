pub const dispatcher = @import("linux/dispatcher.zig");
pub const headless = @import("linux/headless.zig");
pub const keyboard = @import("linux/keyboard.zig");
pub const platform = @import("linux/platform.zig");
pub const text_system = @import("linux/text_system.zig");
pub const types = @import("linux/types.zig");
pub const wayland = @import("linux/wayland.zig");
pub const x11 = @import("linux/x11.zig");
pub const xdg_desktop_portal = @import("linux/xdg_desktop_portal.zig");

pub const LinuxBackend = platform.LinuxBackend;
pub const LinuxClipboardKind = types.LinuxClipboardKind;
pub const LinuxClipboardSnapshot = types.LinuxClipboardSnapshot;
pub const LinuxDisplayInfo = types.LinuxDisplayInfo;
pub const LinuxPathList = types.LinuxPathList;
pub const LinuxPathPromptOptions = types.LinuxPathPromptOptions;
pub const LinuxPlatform = platform.LinuxPlatform;
pub const LinuxPortalSettings = types.LinuxPortalSettings;
pub const DesktopEnvironment = platform.DesktopEnvironment;
pub const LinuxWaylandBackend = platform.LinuxWaylandBackend;
pub const LinuxRuntimeSnapshot = types.LinuxRuntimeSnapshot;
pub const LinuxRuntimeKind = platform.LinuxRuntimeKind;
pub const LinuxWindowAppearance = types.LinuxWindowAppearance;
pub const LinuxWindowButtonLayout = types.LinuxWindowButtonLayout;
pub const WaylandClient = wayland.WaylandClient;
pub const X11Backend = x11.X11Backend;
pub const HeadlessBackend = headless.HeadlessBackend;
pub const LinuxWindowInfo = types.LinuxWindowInfo;
pub const desktopEnvironment = platform.desktopEnvironment;
pub const guessRuntimeKind = platform.guessRuntimeKind;
pub const createRuntime = platform.createRuntime;

test "linux root exports backend modules and runtime helpers" {
    const std = @import("std");

    try std.testing.expect(@hasDecl(@This(), "dispatcher"));
    try std.testing.expect(@hasDecl(@This(), "headless"));
    try std.testing.expect(@hasDecl(@This(), "keyboard"));
    try std.testing.expect(@hasDecl(@This(), "platform"));
    try std.testing.expect(@hasDecl(@This(), "wayland"));
    try std.testing.expect(@hasDecl(@This(), "x11"));
    try std.testing.expect(@hasDecl(@This(), "LinuxBackend"));
    try std.testing.expect(@hasDecl(@This(), "LinuxRuntimeKind"));
    try std.testing.expect(@hasDecl(@This(), "WaylandClient"));
    try std.testing.expect(@hasDecl(@This(), "X11Backend"));
    try std.testing.expect(@hasDecl(@This(), "HeadlessBackend"));
    try std.testing.expect(@hasDecl(@This(), "guessRuntimeKind"));
    try std.testing.expect(@hasDecl(@This(), "createRuntime"));
}

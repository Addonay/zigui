pub const clipboard = @import("windows/clipboard.zig");
pub const destination_list = @import("windows/destination_list.zig");
pub const direct_manipulation = @import("windows/direct_manipulation.zig");
pub const direct_write = @import("windows/direct_write.zig");
pub const directx_atlas = @import("windows/directx_atlas.zig");
pub const directx_devices = @import("windows/directx_devices.zig");
pub const directx_renderer = @import("windows/directx_renderer.zig");
pub const dispatcher = @import("windows/dispatcher.zig");
pub const display = @import("windows/display.zig");
pub const events = @import("windows/events.zig");
pub const keyboard = @import("windows/keyboard.zig");
pub const platform = @import("windows/platform.zig");
pub const system_settings = @import("windows/system_settings.zig");
pub const util = @import("windows/util.zig");
pub const vsync = @import("windows/vsync.zig");
pub const window = @import("windows/window.zig");
pub const wrapper = @import("windows/wrapper.zig");

pub const WindowsPlatform = platform.WindowsPlatform;
pub const WindowsBackend = WindowsPlatform;
pub const DirectXRenderer = directx_renderer.DirectXRenderer;
pub const DirectXRendererDevices = directx_renderer.DirectXRendererDevices;
pub const DrawReport = directx_renderer.DrawReport;
pub const GpuSpecs = directx_renderer.GpuSpecs;
pub const createRuntime = platform.createRuntime;
pub const SafeCursor = wrapper.SafeCursor;
pub const SafeHwnd = wrapper.SafeHwnd;

test "windows root exports the expected backend slices" {
    const std = @import("std");

    try std.testing.expect(@hasDecl(@This(), "clipboard"));
    try std.testing.expect(@hasDecl(@This(), "destination_list"));
    try std.testing.expect(@hasDecl(@This(), "direct_manipulation"));
    try std.testing.expect(@hasDecl(@This(), "direct_write"));
    try std.testing.expect(@hasDecl(@This(), "directx_atlas"));
    try std.testing.expect(@hasDecl(@This(), "directx_devices"));
    try std.testing.expect(@hasDecl(@This(), "dispatcher"));
    try std.testing.expect(@hasDecl(@This(), "display"));
    try std.testing.expect(@hasDecl(@This(), "directx_renderer"));
    try std.testing.expect(@hasDecl(@This(), "events"));
    try std.testing.expect(@hasDecl(@This(), "keyboard"));
    try std.testing.expect(@hasDecl(@This(), "platform"));
    try std.testing.expect(@hasDecl(@This(), "system_settings"));
    try std.testing.expect(@hasDecl(@This(), "util"));
    try std.testing.expect(@hasDecl(@This(), "vsync"));
    try std.testing.expect(@hasDecl(@This(), "window"));
    try std.testing.expect(@hasDecl(@This(), "wrapper"));
    try std.testing.expect(@hasDecl(@This(), "WindowsPlatform"));
    try std.testing.expect(@hasDecl(@This(), "WindowsBackend"));
    try std.testing.expect(@hasDecl(@This(), "DirectXRenderer"));
    try std.testing.expect(@hasDecl(@This(), "DirectXRendererDevices"));
    try std.testing.expect(@hasDecl(@This(), "DrawReport"));
    try std.testing.expect(@hasDecl(@This(), "GpuSpecs"));
    try std.testing.expect(@hasDecl(@This(), "createRuntime"));
    try std.testing.expect(@hasDecl(@This(), "SafeCursor"));
    try std.testing.expect(@hasDecl(@This(), "SafeHwnd"));
}

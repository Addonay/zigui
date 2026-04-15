const builtin = @import("builtin");
const common = @import("common.zig");
const linux_backend = @import("../zigui_linux/linux.zig");
const macos_backend = @import("../zigui_macos/macos.zig");
const windows_backend = @import("../zigui_windows/windows.zig");
pub const layer_shell = @import("layer_shell.zig");

pub const linux = linux_backend;
pub const macos = macos_backend;
pub const windows = windows_backend;

pub const BackendKind = common.BackendKind;
pub const ClipboardKind = common.ClipboardKind;
pub const ClipboardSnapshot = common.ClipboardSnapshot;
pub const Cursor = common.Cursor;
pub const Decorations = common.Decorations;
pub const DesktopSettings = common.DesktopSettings;
pub const DisplayInfo = common.DisplayInfo;
pub const Diagnostics = common.Diagnostics;
pub const KeyboardInfo = common.KeyboardInfo;
pub const PathList = common.PathList;
pub const PathPromptOptions = common.PathPromptOptions;
pub const PlatformServices = common.PlatformServices;
pub const ResizeEdge = common.ResizeEdge;
pub const Runtime = common.Runtime;
pub const RuntimeSnapshot = common.RuntimeSnapshot;
pub const Tiling = common.Tiling;
pub const RuntimeVTable = common.RuntimeVTable;
pub const WindowAppearance = common.WindowAppearance;
pub const WindowButtonLayout = common.WindowButtonLayout;
pub const WindowControls = common.WindowControls;
pub const WindowDecorations = common.WindowDecorations;
pub const WindowInfo = common.WindowInfo;
pub const WindowOptions = common.WindowOptions;
pub const Layer = layer_shell.Layer;
pub const Anchor = layer_shell.Anchor;
pub const KeyboardInteractivity = layer_shell.KeyboardInteractivity;
pub const LayerShellOptions = layer_shell.LayerShellOptions;
pub const LayerShellNotSupportedError = layer_shell.LayerShellNotSupportedError;

pub fn defaultBackendKind() BackendKind {
    return switch (builtin.os.tag) {
        .linux, .freebsd => .linux_wayland,
        .windows => .windows_native,
        .macos => .macos_native,
        else => .unsupported,
    };
}

pub fn createRuntime(allocator: std.mem.Allocator, options: WindowOptions) !Runtime {
    return switch (builtin.os.tag) {
        .linux, .freebsd => linux_backend.createRuntime(allocator, options),
        .windows => windows_backend.createRuntime(allocator, options),
        .macos => macos_backend.createRuntime(allocator, options),
        else => error.UnsupportedPlatform,
    };
}

const std = @import("std");

test "platform root exports platform selectors and layer shell types" {
    const kind: BackendKind = defaultBackendKind();
    _ = kind;

    try std.testing.expect(@hasDecl(@This(), "linux"));
    try std.testing.expect(@hasDecl(@This(), "macos"));
    try std.testing.expect(@hasDecl(@This(), "windows"));
    try std.testing.expect(@hasDecl(@This(), "layer_shell"));
    try std.testing.expect(@hasDecl(@This(), "Layer"));
    try std.testing.expect(@hasDecl(@This(), "Anchor"));
    try std.testing.expect(@hasDecl(@This(), "KeyboardInteractivity"));
    try std.testing.expect(@hasDecl(@This(), "LayerShellOptions"));
    try std.testing.expect(@hasDecl(@This(), "LayerShellNotSupportedError"));
}

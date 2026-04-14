const builtin = @import("builtin");
const common = @import("platform/common.zig");
const linux_backend = @import("platform/linux/root.zig");
const macos_backend = @import("platform/macos/root.zig");
const windows_backend = @import("platform/windows/root.zig");

pub const linux = linux_backend;
pub const macos = macos_backend;
pub const windows = windows_backend;

pub const BackendKind = common.BackendKind;
pub const ClipboardKind = common.ClipboardKind;
pub const ClipboardSnapshot = common.ClipboardSnapshot;
pub const Cursor = common.Cursor;
pub const DesktopSettings = common.DesktopSettings;
pub const DisplayInfo = common.DisplayInfo;
pub const Diagnostics = common.Diagnostics;
pub const KeyboardInfo = common.KeyboardInfo;
pub const PathList = common.PathList;
pub const PathPromptOptions = common.PathPromptOptions;
pub const PlatformServices = common.PlatformServices;
pub const Runtime = common.Runtime;
pub const RuntimeSnapshot = common.RuntimeSnapshot;
pub const RuntimeVTable = common.RuntimeVTable;
pub const WindowAppearance = common.WindowAppearance;
pub const WindowButtonLayout = common.WindowButtonLayout;
pub const WindowInfo = common.WindowInfo;
pub const WindowOptions = common.WindowOptions;

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

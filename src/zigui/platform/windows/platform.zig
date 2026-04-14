const std = @import("std");
const common = @import("../common.zig");
const dispatcher = @import("dispatcher.zig");
const display = @import("display.zig");
const directx_renderer = @import("directx_renderer.zig");
const events = @import("events.zig");
const keyboard = @import("keyboard.zig");
const text_system = @import("text_system.zig");
const window = @import("window.zig");

pub const WindowsBackend = struct {
    allocator: std.mem.Allocator,
    options: common.WindowOptions,
    dispatcher: dispatcher.Dispatcher = .{},
    display: display.Display = .{},
    events: events.EventState = .{},
    keyboard: keyboard.KeyboardState = .{},
    renderer: directx_renderer.DirectXRendererConfig = .{},
    text: text_system.TextSystemConfig = .{},
    window: window.WindowState = .{},

    pub fn run(self: *WindowsBackend) !void {
        _ = self;
        return error.NativeBackendNotImplemented;
    }

    pub fn name(self: *const WindowsBackend) []const u8 {
        _ = self;
        return "windows-native";
    }

    pub fn services(self: *const WindowsBackend) common.PlatformServices {
        _ = self;
        return .{
            .backend = .windows_native,
            .supports_ime = true,
            .supports_clipboard = true,
            .supports_gpu_rendering = false,
            .supports_multiple_windows = true,
        };
    }

    pub fn diagnostics(self: *const WindowsBackend) common.Diagnostics {
        _ = self;
        return .{
            .backend_name = "windows-native",
            .window_system = "Win32",
            .renderer = "unbound",
            .note = "The Windows backend is split into dispatcher, display, events, window, text, and DirectX renderer modules. The real runtime is still pending.",
        };
    }
};

pub fn createRuntime(allocator: std.mem.Allocator, options: common.WindowOptions) !common.Runtime {
    _ = allocator;
    _ = options;
    return error.NativeBackendNotImplemented;
}

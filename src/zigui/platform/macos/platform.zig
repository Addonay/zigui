const std = @import("std");
const common = @import("../common.zig");
const dispatcher = @import("dispatcher.zig");
const display = @import("display.zig");
const events = @import("events.zig");
const keyboard = @import("keyboard.zig");
const metal_renderer = @import("metal_renderer.zig");
const text_system = @import("text_system.zig");
const window = @import("window.zig");

pub const MacOSBackend = struct {
    allocator: std.mem.Allocator,
    options: common.WindowOptions,
    dispatcher: dispatcher.Dispatcher = .{},
    display: display.Display = .{},
    events: events.EventState = .{},
    keyboard: keyboard.KeyboardState = .{},
    renderer: metal_renderer.MetalRendererConfig = .{},
    text: text_system.TextSystemConfig = .{},
    window: window.WindowState = .{},

    pub fn run(self: *MacOSBackend) !void {
        _ = self;
        return error.NativeBackendNotImplemented;
    }

    pub fn name(self: *const MacOSBackend) []const u8 {
        _ = self;
        return "macos-native";
    }

    pub fn services(self: *const MacOSBackend) common.PlatformServices {
        _ = self;
        return .{
            .backend = .macos_native,
            .supports_ime = true,
            .supports_clipboard = true,
            .supports_gpu_rendering = false,
            .supports_multiple_windows = true,
        };
    }

    pub fn diagnostics(self: *const MacOSBackend) common.Diagnostics {
        _ = self;
        return .{
            .backend_name = "macos-native",
            .window_system = "AppKit",
            .renderer = "unbound",
            .note = "The macOS backend is split into dispatcher, display, events, window, text, and Metal renderer modules. The real runtime is still pending.",
        };
    }
};

pub fn createRuntime(allocator: std.mem.Allocator, options: common.WindowOptions) !common.Runtime {
    _ = allocator;
    _ = options;
    return error.NativeBackendNotImplemented;
}

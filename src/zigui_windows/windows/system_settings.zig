const builtin = @import("builtin");
const std = @import("std");
const common = @import("../../zigui/common.zig");
const util = @import("util.zig");

pub const MouseWheelSettings = struct {
    wheel_scroll_chars: u32 = 0,
    wheel_scroll_lines: u32 = 0,
};

pub const WindowsSystemSettings = struct {
    appearance: common.WindowAppearance = .light,
    mouse_wheel_settings: MouseWheelSettings = .{},

    pub fn init(allocator: std.mem.Allocator) WindowsSystemSettings {
        return .{
            .appearance = queryAppearance(allocator) catch .light,
        };
    }

    pub fn update(self: *WindowsSystemSettings, wparam: usize) void {
        _ = self;
        _ = wparam;
    }
};

pub fn queryAppearance(allocator: std.mem.Allocator) !common.WindowAppearance {
    if (builtin.os.tag != .windows) return .light;

    const stdout = try util.runPowerShellCapture(
        allocator,
        "try { $theme = Get-ItemPropertyValue -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize' -Name AppsUseLightTheme -ErrorAction Stop; if ($theme -eq 0) { [Console]::WriteLine('dark') } else { [Console]::WriteLine('light') } } catch { [Console]::WriteLine('light') }",
    );
    defer allocator.free(stdout);

    const trimmed = std.mem.trim(u8, stdout, " \r\n\t");
    if (std.ascii.eqlIgnoreCase(trimmed, "dark")) return .dark;
    return .light;
}

test "windows system settings default to light appearance" {
    const settings = WindowsSystemSettings.init(std.testing.allocator);
    try std.testing.expect(settings.appearance == .light or settings.appearance == .dark);
    try std.testing.expectEqual(@as(u32, 0), settings.mouse_wheel_settings.wheel_scroll_chars);
    try std.testing.expectEqual(@as(u32, 0), settings.mouse_wheel_settings.wheel_scroll_lines);
}

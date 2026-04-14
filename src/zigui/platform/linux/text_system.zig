const std = @import("std");

pub const FontDescriptor = struct {
    family: []const u8,
    size_px: f32 = 14,
    weight: u16 = 400,
    italic: bool = false,
};

pub const TextSystemConfig = struct {
    default_font_family: []const u8 = "Inter",
    prefer_subpixel_rasterization: bool = true,
    enable_color_emoji: bool = true,
    default_font_size_px: f32 = 14,

    pub fn defaultFont(self: TextSystemConfig) FontDescriptor {
        return .{
            .family = self.default_font_family,
            .size_px = self.default_font_size_px,
        };
    }
};

pub const TextSystemCapabilities = struct {
    has_shaping: bool = false,
    has_font_fallback: bool = false,
    has_color_emoji: bool = false,
};

pub const LinuxTextSystem = struct {
    config: TextSystemConfig = .{},
    capabilities: TextSystemCapabilities = .{
        .has_color_emoji = true,
    },

    pub fn describe(self: LinuxTextSystem) []const u8 {
        _ = self;
        return "linux-text-system";
    }
};

test "text system exposes a default font descriptor" {
    const config = TextSystemConfig{};
    const font = config.defaultFont();
    try std.testing.expectEqualStrings("Inter", font.family);
    try std.testing.expectEqual(@as(f32, 14), font.size_px);
}

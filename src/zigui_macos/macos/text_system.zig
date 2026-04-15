const std = @import("std");
const open_type = @import("open_type.zig");

pub const FontDescriptor = struct {
    family: []const u8,
    size_px: f32 = 14,
    weight: u16 = 400,
    italic: bool = false,
};

pub const TextSystemConfig = struct {
    uses_core_text: bool = true,
    default_font_family: []const u8 = ".AppleSystemUIFont",
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
    has_shaping: bool = true,
    has_font_fallback: bool = true,
    has_color_emoji: bool = true,
};

pub const MacTextSystem = struct {
    config: TextSystemConfig = .{},
    capabilities: TextSystemCapabilities = .{},
    open_type_settings: open_type.OpenTypeSettings = .{},

    pub fn deinit(self: *MacTextSystem, allocator: std.mem.Allocator) void {
        self.open_type_settings.deinit(allocator);
    }

    pub fn describe(self: MacTextSystem) []const u8 {
        _ = self;
        return "macos-coretext";
    }

    pub fn defaultFont(self: MacTextSystem) FontDescriptor {
        return self.config.defaultFont();
    }

    pub fn applyFeaturesAndFallbacks(
        self: *MacTextSystem,
        allocator: std.mem.Allocator,
        features: []const open_type.OpenTypeFeature,
        fallback_families: []const []const u8,
    ) !void {
        try self.open_type_settings.applyFeaturesAndFallbacks(allocator, features, fallback_families);
    }
};

test "text system exposes a default font descriptor" {
    const text_system = TextSystemConfig{};
    const font = text_system.defaultFont();
    try std.testing.expectEqualStrings(".AppleSystemUIFont", font.family);
    try std.testing.expectEqual(@as(f32, 14), font.size_px);
}

test "mac text system keeps core text capabilities enabled" {
    const text_system = MacTextSystem{};
    try std.testing.expect(text_system.capabilities.has_shaping);
    try std.testing.expect(text_system.capabilities.has_font_fallback);
    try std.testing.expect(text_system.capabilities.has_color_emoji);
    try std.testing.expectEqualStrings("macos-coretext", text_system.describe());
}

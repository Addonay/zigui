const std = @import("std");
const common = @import("../../zigui/common.zig");

pub const MacWindowAppearance = enum {
    aqua,
    dark_aqua,
    vibrant_light,
    vibrant_dark,

    pub fn fromNativeName(name: []const u8) MacWindowAppearance {
        if (std.mem.eql(u8, name, "NSAppearanceNameDarkAqua") or std.mem.eql(u8, name, "dark-aqua")) {
            return .dark_aqua;
        }
        if (std.mem.eql(u8, name, "NSAppearanceNameVibrantDark") or std.mem.eql(u8, name, "vibrant-dark")) {
            return .vibrant_dark;
        }
        if (std.mem.eql(u8, name, "NSAppearanceNameVibrantLight") or std.mem.eql(u8, name, "vibrant-light")) {
            return .vibrant_light;
        }
        return .aqua;
    }

    pub fn nativeName(self: MacWindowAppearance) []const u8 {
        return switch (self) {
            .aqua => "NSAppearanceNameAqua",
            .dark_aqua => "NSAppearanceNameDarkAqua",
            .vibrant_light => "NSAppearanceNameVibrantLight",
            .vibrant_dark => "NSAppearanceNameVibrantDark",
        };
    }

    pub fn toCommon(self: MacWindowAppearance) common.WindowAppearance {
        return switch (self) {
            .dark_aqua, .vibrant_dark => .dark,
            .aqua, .vibrant_light => .light,
        };
    }

    pub fn isDark(self: MacWindowAppearance) bool {
        return switch (self) {
            .dark_aqua, .vibrant_dark => true,
            .aqua, .vibrant_light => false,
        };
    }
};

test "window appearance maps native names and common values" {
    try std.testing.expectEqual(MacWindowAppearance.dark_aqua, MacWindowAppearance.fromNativeName("NSAppearanceNameDarkAqua"));
    try std.testing.expectEqual(MacWindowAppearance.vibrant_dark, MacWindowAppearance.fromNativeName("vibrant-dark"));
    try std.testing.expectEqual(common.WindowAppearance.dark, MacWindowAppearance.dark_aqua.toCommon());
    try std.testing.expect(MacWindowAppearance.dark_aqua.isDark());
}

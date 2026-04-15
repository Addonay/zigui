pub const TextSystemConfig = struct {
    uses_direct_write: bool = true,
    supports_color_fonts: bool = true,
    supports_ime: bool = true,
};

pub const DirectWriteTextSystemConfig = TextSystemConfig;
pub const DirectWriteTextSystem = TextSystemConfig;

test "text system uses direct write and ime by default" {
    const std = @import("std");

    const text_system = TextSystemConfig{};
    try std.testing.expect(text_system.uses_direct_write);
    try std.testing.expect(text_system.supports_color_fonts);
    try std.testing.expect(text_system.supports_ime);
}

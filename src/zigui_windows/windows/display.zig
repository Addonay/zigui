const std = @import("std");
const common = @import("../../zigui/common.zig");

pub const Display = struct {
    uses_dpi_awareness: bool = true,
    width: i32 = 1920,
    height: i32 = 1080,
    scale_factor: f32 = 1.0,

    pub fn count(self: *const Display) usize {
        _ = self;
        return 1;
    }

    pub fn primaryInfo(self: *const Display) common.DisplayInfo {
        return .{
            .id = 1,
            .name = "DISPLAY1",
            .description = "Primary display",
            .width = self.width,
            .height = self.height,
            .scale_factor = self.scale_factor,
            .is_primary = true,
        };
    }

    pub fn infosAlloc(self: *const Display, allocator: std.mem.Allocator) ![]common.DisplayInfo {
        const infos = try allocator.alloc(common.DisplayInfo, self.count());
        infos[0] = self.primaryInfo();
        return infos;
    }
};

pub const WindowsDisplay = Display;

test "display exposes a primary screen snapshot" {
    const instance = Display{};
    const info = instance.primaryInfo();
    try std.testing.expectEqual(@as(usize, 1), info.id);
    try std.testing.expect(info.is_primary);
}

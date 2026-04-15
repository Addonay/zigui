const std = @import("std");
const common = @import("../../zigui/common.zig");

pub const MacDisplay = struct {
    id: usize = 1,
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    x: i32 = 0,
    y: i32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    scale_factor: f32 = 1.0,
    is_primary: bool = true,
    uses_display_link: bool = true,

    pub fn info(self: *const MacDisplay) common.DisplayInfo {
        return .{
            .id = self.id,
            .name = self.name,
            .description = self.description,
            .x = self.x,
            .y = self.y,
            .width = @intCast(self.width),
            .height = @intCast(self.height),
            .scale_factor = self.scale_factor,
            .is_primary = self.is_primary,
        };
    }
};

pub const DisplayState = struct {
    uses_display_link: bool = true,
    primary_display: MacDisplay = .{},
    extra_displays: std.ArrayListUnmanaged(MacDisplay) = .empty,

    pub fn init(options: common.WindowOptions) DisplayState {
        return .{
            .uses_display_link = true,
            .primary_display = .{
                .id = 1,
                .width = options.width,
                .height = options.height,
                .is_primary = true,
                .uses_display_link = true,
            },
        };
    }

    pub fn deinit(self: *DisplayState, allocator: std.mem.Allocator) void {
        self.extra_displays.deinit(allocator);
    }

    pub fn count(self: *const DisplayState) usize {
        return 1 + self.extra_displays.items.len;
    }

    pub fn primaryDisplay(self: *const DisplayState) *const MacDisplay {
        return &self.primary_display;
    }

    pub fn primaryInfo(self: *const DisplayState) common.DisplayInfo {
        return self.primary_display.info();
    }

    pub fn addDisplay(self: *DisplayState, allocator: std.mem.Allocator, display: MacDisplay) !void {
        try self.extra_displays.append(allocator, display);
    }

    pub fn findById(self: *const DisplayState, id: usize) ?*const MacDisplay {
        if (self.primary_display.id == id) {
            return &self.primary_display;
        }

        for (self.extra_displays.items) |*display| {
            if (display.id == id) return display;
        }

        return null;
    }

    pub fn infosAlloc(self: *const DisplayState, allocator: std.mem.Allocator) ![]common.DisplayInfo {
        const infos = try allocator.alloc(common.DisplayInfo, self.count());
        infos[0] = self.primary_display.info();
        for (self.extra_displays.items, 0..) |display, index| {
            infos[index + 1] = display.info();
        }
        return infos;
    }
};

pub const Display = DisplayState;
pub const MacDisplayState = DisplayState;

test "display exposes a primary screen snapshot" {
    const state = DisplayState.init(.{ .width = 1600, .height = 900 });
    const info = state.primaryInfo();
    try std.testing.expectEqual(@as(usize, 1), info.id);
    try std.testing.expect(info.is_primary);
    try std.testing.expectEqual(@as(u32, 1600), @as(u32, @intCast(info.width)));
    try std.testing.expectEqual(@as(u32, 900), @as(u32, @intCast(info.height)));
}

test "display infos allocate the configured displays" {
    var state = DisplayState.init(.{});
    defer state.deinit(std.testing.allocator);

    try state.addDisplay(std.testing.allocator, .{
        .id = 2,
        .name = "External",
        .description = "external display",
        .width = 1920,
        .height = 1080,
        .scale_factor = 2.0,
        .is_primary = false,
        .uses_display_link = true,
    });

    const infos = try state.infosAlloc(std.testing.allocator);
    defer std.testing.allocator.free(infos);

    try std.testing.expectEqual(@as(usize, 2), infos.len);
    try std.testing.expectEqualStrings("External", infos[1].name.?);
}

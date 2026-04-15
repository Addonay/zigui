const std = @import("std");

pub const OpenTypeFeature = struct {
    tag: [4]u8,
    value: i32,
};

pub const OpenTypeSettings = struct {
    features: std.ArrayListUnmanaged(OpenTypeFeature) = .empty,
    fallbacks: std.ArrayListUnmanaged([]u8) = .empty,

    pub fn deinit(self: *OpenTypeSettings, allocator: std.mem.Allocator) void {
        self.clear(allocator);
    }

    pub fn clear(self: *OpenTypeSettings, allocator: std.mem.Allocator) void {
        for (self.fallbacks.items) |fallback| allocator.free(fallback);
        self.features.clearRetainingCapacity();
        self.fallbacks.clearRetainingCapacity();
    }

    pub fn applyFeaturesAndFallbacks(
        self: *OpenTypeSettings,
        allocator: std.mem.Allocator,
        features: []const OpenTypeFeature,
        fallback_families: []const []const u8,
    ) !void {
        self.clear(allocator);
        try self.features.appendSlice(allocator, features);
        for (fallback_families) |family| {
            try self.fallbacks.append(allocator, try allocator.dupe(u8, family));
        }
    }

    pub fn featureCount(self: *const OpenTypeSettings) usize {
        return self.features.items.len;
    }

    pub fn fallbackCount(self: *const OpenTypeSettings) usize {
        return self.fallbacks.items.len;
    }
};

test "open type settings store features and fallbacks" {
    var settings = OpenTypeSettings{};
    defer settings.deinit(std.testing.allocator);

    try settings.applyFeaturesAndFallbacks(
        std.testing.allocator,
        &.{
            .{ .tag = .{ 's', 'm', 'c', 'p' }, .value = 1 },
        },
        &.{
            "Avenir",
            "Helvetica Neue",
        },
    );

    try std.testing.expectEqual(@as(usize, 1), settings.featureCount());
    try std.testing.expectEqual(@as(usize, 2), settings.fallbackCount());
    try std.testing.expectEqualStrings("Avenir", settings.fallbacks.items[0]);
}

const std = @import("std");

pub const FeatureLevel = enum {
    unknown,
    feature_10_1,
    feature_11_0,
    feature_11_1,
};

pub const RendererDeviceSnapshot = struct {
    adapter_name: ?[]const u8 = null,
    feature_level: FeatureLevel = .unknown,
    debug_layer_available: bool = false,
    supports_bgra_support: bool = true,
    supports_compute_shaders: bool = true,

    pub fn supportsGpuRendering(self: *const RendererDeviceSnapshot) bool {
        return self.feature_level != .unknown and self.supports_compute_shaders;
    }
};

pub const DirectXDevices = struct {
    adapter_name: ?[]u8 = null,
    feature_level: FeatureLevel = .unknown,
    debug_layer_available: bool = false,
    supports_bgra_support: bool = true,
    supports_compute_shaders: bool = true,

    pub fn init(allocator: std.mem.Allocator) !DirectXDevices {
        _ = allocator;
        return .{};
    }

    pub fn deinit(self: *DirectXDevices, allocator: std.mem.Allocator) void {
        if (self.adapter_name) |name| allocator.free(name);
        self.* = .{};
    }

    pub fn isAvailable(self: *const DirectXDevices) bool {
        return self.feature_level != .unknown;
    }

    pub fn snapshot(self: *const DirectXDevices) RendererDeviceSnapshot {
        return .{
            .adapter_name = self.adapter_name,
            .feature_level = self.feature_level,
            .debug_layer_available = self.debug_layer_available,
            .supports_bgra_support = self.supports_bgra_support,
            .supports_compute_shaders = self.supports_compute_shaders,
        };
    }

    pub fn setAdapterName(self: *DirectXDevices, allocator: std.mem.Allocator, name: []const u8) !void {
        if (self.adapter_name) |existing| allocator.free(existing);
        self.adapter_name = try allocator.dupe(u8, name);
    }
};

test "directx devices stores adapter metadata" {
    var devices = try DirectXDevices.init(std.testing.allocator);
    defer devices.deinit(std.testing.allocator);

    try std.testing.expect(!devices.isAvailable());
    try devices.setAdapterName(std.testing.allocator, "NVIDIA");
    try std.testing.expectEqualStrings("NVIDIA", devices.adapter_name.?);
    try std.testing.expect(!devices.isAvailable());

    const snapshot = devices.snapshot();
    try std.testing.expectEqualStrings("NVIDIA", snapshot.adapter_name.?);
    try std.testing.expect(!snapshot.supportsGpuRendering());
}

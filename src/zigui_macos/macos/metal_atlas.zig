const std = @import("std");

pub const AtlasTextureKind = enum {
    monochrome,
    polychrome,
    subpixel,
};

pub const AtlasTextureId = struct {
    index: u32 = 0,
    kind: AtlasTextureKind = .monochrome,
};

pub const AtlasTile = struct {
    texture_id: AtlasTextureId = .{},
    width: u32 = 0,
    height: u32 = 0,
};

pub const MetalAtlas = struct {
    tiles: std.AutoHashMapUnmanaged(u64, AtlasTile) = .{},
    next_texture_index: u32 = 0,

    pub fn deinit(self: *MetalAtlas, allocator: std.mem.Allocator) void {
        self.tiles.deinit(allocator);
        self.* = .{};
    }

    pub fn getOrInsert(
        self: *MetalAtlas,
        allocator: std.mem.Allocator,
        key: u64,
        width: u32,
        height: u32,
        kind: AtlasTextureKind,
    ) !AtlasTile {
        if (self.tiles.get(key)) |tile| return tile;

        const tile = AtlasTile{
            .texture_id = .{
                .index = self.next_texture_index,
                .kind = kind,
            },
            .width = width,
            .height = height,
        };

        self.next_texture_index += 1;
        try self.tiles.put(allocator, key, tile);
        return tile;
    }

    pub fn remove(self: *MetalAtlas, key: u64) void {
        _ = self.tiles.remove(key);
    }

    pub fn handleDeviceLost(self: *MetalAtlas) void {
        self.tiles.clearRetainingCapacity();
        self.next_texture_index = 0;
    }

    pub fn count(self: *const MetalAtlas) usize {
        return self.tiles.count();
    }
};

test "metal atlas caches tiles by key" {
    var atlas = MetalAtlas{};
    defer atlas.deinit(std.testing.allocator);

    const first = try atlas.getOrInsert(std.testing.allocator, 0xdead_beef, 128, 64, .polychrome);
    const second = try atlas.getOrInsert(std.testing.allocator, 0xdead_beef, 256, 256, .subpixel);

    try std.testing.expectEqual(@as(u32, 0), first.texture_id.index);
    try std.testing.expectEqual(first.texture_id.index, second.texture_id.index);
    try std.testing.expectEqual(@as(usize, 1), atlas.count());

    atlas.remove(0xdead_beef);
    try std.testing.expectEqual(@as(usize, 0), atlas.count());
}

test "metal atlas resets after device loss" {
    var atlas = MetalAtlas{};
    defer atlas.deinit(std.testing.allocator);

    _ = try atlas.getOrInsert(std.testing.allocator, 1, 8, 8, .monochrome);
    _ = try atlas.getOrInsert(std.testing.allocator, 2, 16, 16, .polychrome);

    atlas.handleDeviceLost();
    try std.testing.expectEqual(@as(usize, 0), atlas.count());
    try std.testing.expectEqual(@as(u32, 0), atlas.next_texture_index);
}

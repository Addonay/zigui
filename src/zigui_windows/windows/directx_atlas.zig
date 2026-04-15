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

pub const DirectXAtlas = struct {
    tiles: std.AutoHashMapUnmanaged(u64, AtlasTile) = .{},
    next_texture_index: u32 = 0,

    pub fn deinit(self: *DirectXAtlas, allocator: std.mem.Allocator) void {
        self.tiles.deinit(allocator);
        self.* = .{};
    }

    pub fn getOrInsert(
        self: *DirectXAtlas,
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

    pub fn remove(self: *DirectXAtlas, key: u64) void {
        _ = self.tiles.remove(key);
    }

    pub fn handleDeviceLost(self: *DirectXAtlas) void {
        self.tiles.clearRetainingCapacity();
        self.next_texture_index = 0;
    }

    pub fn count(self: *const DirectXAtlas) usize {
        return self.tiles.count();
    }
};

test "directx atlas caches tiles by key" {
    var atlas = DirectXAtlas{};
    defer atlas.deinit(std.testing.allocator);

    const first = try atlas.getOrInsert(std.testing.allocator, 0xdead_beef, 128, 64, .polychrome);
    const second = try atlas.getOrInsert(std.testing.allocator, 0xdead_beef, 256, 256, .subpixel);

    try std.testing.expectEqual(@as(u32, 0), first.texture_id.index);
    try std.testing.expectEqual(first.texture_id.index, second.texture_id.index);
    try std.testing.expectEqual(@as(usize, 1), atlas.count());

    atlas.remove(0xdead_beef);
    try std.testing.expectEqual(@as(usize, 0), atlas.count());
}

test "directx atlas resets after device loss" {
    var atlas_instance = DirectXAtlas{};
    defer atlas_instance.deinit(std.testing.allocator);

    _ = try atlas_instance.getOrInsert(std.testing.allocator, 1, 8, 8, .monochrome);
    _ = try atlas_instance.getOrInsert(std.testing.allocator, 2, 16, 16, .polychrome);

    atlas_instance.handleDeviceLost();
    try std.testing.expectEqual(@as(usize, 0), atlas_instance.count());
    try std.testing.expectEqual(@as(u32, 0), atlas_instance.next_texture_index);
}

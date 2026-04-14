const std = @import("std");

pub const EntityId = enum(u64) {
    _,
};

pub const EntityRecord = struct {
    id: EntityId,
    type_name: []const u8,
};

pub const EntityStore = struct {
    next_id: u64 = 1,
    records: std.ArrayList(EntityRecord) = .empty,

    pub fn init() EntityStore {
        return .{};
    }

    pub fn deinit(self: *EntityStore, allocator: std.mem.Allocator) void {
        self.records.deinit(allocator);
    }

    pub fn create(self: *EntityStore, allocator: std.mem.Allocator, type_name: []const u8) !EntityId {
        const id: EntityId = @enumFromInt(self.next_id);
        self.next_id += 1;
        try self.records.append(allocator, .{
            .id = id,
            .type_name = type_name,
        });
        return id;
    }

    pub fn count(self: *const EntityStore) usize {
        return self.records.items.len;
    }
};

test "entity store assigns stable incremental identifiers" {
    var store = EntityStore.init();
    defer store.deinit(std.testing.allocator);

    const a = try store.create(std.testing.allocator, "Counter");
    const b = try store.create(std.testing.allocator, "WindowState");
    try std.testing.expect(@intFromEnum(a) == 1);
    try std.testing.expect(@intFromEnum(b) == 2);
    try std.testing.expectEqual(@as(usize, 2), store.count());
}

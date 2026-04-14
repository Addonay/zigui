const std = @import("std");

const HeapString = struct {
    allocator: std.mem.Allocator,
    refs: usize = 1,
    bytes: []u8,
};

pub const SharedString = union(enum) {
    static: []const u8,
    heap: *HeapString,

    pub fn initStatic(value: []const u8) SharedString {
        return .{ .static = value };
    }

    pub fn initOwned(allocator: std.mem.Allocator, value: []const u8) !SharedString {
        const bytes = try allocator.dupe(u8, value);
        errdefer allocator.free(bytes);

        const heap = try allocator.create(HeapString);
        heap.* = .{
            .allocator = allocator,
            .bytes = bytes,
        };
        return .{ .heap = heap };
    }

    pub fn clone(self: SharedString) SharedString {
        return switch (self) {
            .static => |value| .{ .static = value },
            .heap => |heap| blk: {
                heap.refs += 1;
                break :blk .{ .heap = heap };
            },
        };
    }

    pub fn slice(self: SharedString) []const u8 {
        return switch (self) {
            .static => |value| value,
            .heap => |heap| heap.bytes,
        };
    }

    pub fn deinit(self: *SharedString) void {
        switch (self.*) {
            .static => {},
            .heap => |heap| {
                heap.refs -= 1;
                if (heap.refs == 0) {
                    heap.allocator.free(heap.bytes);
                    heap.allocator.destroy(heap);
                }
            },
        }
        self.* = .{ .static = "" };
    }
};

test "shared strings clone cheaply and free once" {
    var owned = try SharedString.initOwned(std.testing.allocator, "zigui");
    var clone = owned.clone();
    defer clone.deinit();
    defer owned.deinit();

    try std.testing.expectEqualStrings("zigui", owned.slice());
    try std.testing.expectEqualStrings("zigui", clone.slice());
}

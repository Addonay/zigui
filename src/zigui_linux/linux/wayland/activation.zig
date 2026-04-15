const std = @import("std");

pub fn loadEnvironmentTokenAlloc(allocator: std.mem.Allocator) !?[]u8 {
    const token = std.c.getenv("XDG_ACTIVATION_TOKEN") orelse return null;
    return try allocator.dupe(u8, std.mem.span(token));
}

pub fn clearEnvironmentToken() void {
    // Best-effort no-op on Zig stdlib snapshots where `unsetenv` is not exposed.
}

pub fn dupTokenZ(allocator: std.mem.Allocator, token: []const u8) ![:0]u8 {
    return try allocator.dupeZ(u8, token);
}

test "dup token produces a sentinel-terminated string" {
    const token = try dupTokenZ(std.testing.allocator, "token");
    defer std.testing.allocator.free(token);
    try std.testing.expectEqual(@as(u8, 0), token[token.len]);
}

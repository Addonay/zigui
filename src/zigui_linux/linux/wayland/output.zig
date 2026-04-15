const std = @import("std");

pub const OutputId = usize;

pub const InProgressOutput = struct {
    name: ?[]u8 = null,
    description: ?[]u8 = null,
    x: ?i32 = null,
    y: ?i32 = null,
    width: ?i32 = null,
    height: ?i32 = null,
    scale: i32 = 1,

    pub fn deinit(self: *InProgressOutput, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
        if (self.description) |description| allocator.free(description);
        self.* = .{};
    }

    pub fn complete(self: *const InProgressOutput, id: OutputId) ?OutputInfo {
        const x = self.x orelse return null;
        const y = self.y orelse return null;
        const width = self.width orelse return null;
        const height = self.height orelse return null;
        return .{
            .id = id,
            .name = self.name,
            .description = self.description,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .scale = @max(self.scale, 1),
        };
    }
};

pub const OutputInfo = struct {
    id: OutputId,
    name: ?[]u8 = null,
    description: ?[]u8 = null,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    scale: i32 = 1,

    pub fn clone(self: OutputInfo, allocator: std.mem.Allocator) !OutputInfo {
        return .{
            .id = self.id,
            .name = if (self.name) |name| try allocator.dupe(u8, name) else null,
            .description = if (self.description) |description| try allocator.dupe(u8, description) else null,
            .x = self.x,
            .y = self.y,
            .width = self.width,
            .height = self.height,
            .scale = self.scale,
        };
    }

    pub fn deinit(self: *OutputInfo, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
        if (self.description) |description| allocator.free(description);
        self.* = undefined;
    }
};

test "in progress output completes once geometry and size exist" {
    var pending = InProgressOutput{
        .x = 0,
        .y = 20,
        .width = 1920,
        .height = 1080,
        .scale = 2,
    };
    const complete = pending.complete(17) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(OutputId, 17), complete.id);
    try std.testing.expectEqual(@as(i32, 2), complete.scale);
}

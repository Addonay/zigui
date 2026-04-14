const std = @import("std");
const shared_string = @import("shared_string.zig");
const style = @import("style.zig");
const text = @import("text.zig");

pub const RectCommand = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    color: style.Color,
    radius: f32 = 0,
};

pub const TextCommand = struct {
    x: f32,
    y: f32,
    content: shared_string.SharedString,
    style: text.TextStyle = .{},
    color: style.Color = style.Color.white,
};

pub const Command = union(enum) {
    clear: style.Color,
    fill_rect: RectCommand,
    text: TextCommand,
};

pub const Scene = struct {
    commands: std.ArrayListUnmanaged(Command) = .empty,

    pub fn deinit(self: *Scene, allocator: std.mem.Allocator) void {
        self.clearRetainingCapacity();
        self.commands.deinit(allocator);
    }

    pub fn clearRetainingCapacity(self: *Scene) void {
        for (self.commands.items) |*command| {
            switch (command.*) {
                .text => |*text_command| text_command.content.deinit(),
                else => {},
            }
        }
        self.commands.clearRetainingCapacity();
    }

    pub fn appendClear(self: *Scene, allocator: std.mem.Allocator, color: style.Color) !void {
        try self.commands.append(allocator, .{ .clear = color });
    }

    pub fn appendRect(self: *Scene, allocator: std.mem.Allocator, rect: RectCommand) !void {
        try self.commands.append(allocator, .{ .fill_rect = rect });
    }

    pub fn appendText(self: *Scene, allocator: std.mem.Allocator, text_command: TextCommand) !void {
        try self.commands.append(allocator, .{ .text = text_command });
    }

    pub fn appendLabel(
        self: *Scene,
        allocator: std.mem.Allocator,
        x: f32,
        y: f32,
        label: []const u8,
        text_style: text.TextStyle,
        color: style.Color,
    ) !void {
        try self.appendText(allocator, .{
            .x = x,
            .y = y,
            .content = try shared_string.SharedString.initOwned(allocator, label),
            .style = text_style,
            .color = color,
        });
    }

    pub fn count(self: *const Scene) usize {
        return self.commands.items.len;
    }

    pub fn isEmpty(self: *const Scene) bool {
        return self.commands.items.len == 0;
    }
};

test "scene owns appended text commands" {
    var scene = Scene{};
    defer scene.deinit(std.testing.allocator);

    try scene.appendLabel(std.testing.allocator, 12, 18, "hello", .{}, style.Color.white);
    try std.testing.expectEqual(@as(usize, 1), scene.count());
}

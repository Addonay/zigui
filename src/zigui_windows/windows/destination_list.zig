const std = @import("std");

pub const DockMenuItem = struct {
    name: []const u8 = "",
    description: []const u8 = "",
};

pub const JumpList = struct {
    dock_menus: std.ArrayListUnmanaged(DockMenuItem) = .empty,
    recent_workspaces: std.ArrayListUnmanaged([]const []const u8) = .empty,

    pub fn deinit(self: *JumpList, allocator: std.mem.Allocator) void {
        self.dock_menus.deinit(allocator);
        self.recent_workspaces.deinit(allocator);
    }

    pub fn addDockMenu(self: *JumpList, allocator: std.mem.Allocator, item: DockMenuItem) !void {
        try self.dock_menus.append(allocator, item);
    }

    pub fn addRecentWorkspace(
        self: *JumpList,
        allocator: std.mem.Allocator,
        paths: []const []const u8,
    ) !void {
        try self.recent_workspaces.append(allocator, paths);
    }
};

test "jump list stores dock menus and recent workspaces" {
    var jump_list = JumpList{};
    defer jump_list.deinit(std.testing.allocator);

    try jump_list.addDockMenu(std.testing.allocator, .{
        .name = "New Window",
        .description = "Open a new window",
    });

    const workspace = [_][]const u8{ "C:\\Projects\\zigui", "D:\\Archive\\zigui" };
    try jump_list.addRecentWorkspace(std.testing.allocator, workspace[0..]);

    try std.testing.expectEqual(@as(usize, 1), jump_list.dock_menus.items.len);
    try std.testing.expectEqualStrings("New Window", jump_list.dock_menus.items[0].name);
    try std.testing.expectEqual(@as(usize, 1), jump_list.recent_workspaces.items.len);
    try std.testing.expectEqual(@as(usize, 2), jump_list.recent_workspaces.items[0].len);
    try std.testing.expectEqualStrings("D:\\Archive\\zigui", jump_list.recent_workspaces.items[0][1]);
}

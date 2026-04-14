const std = @import("std");
const platform = @import("platform.zig");
const scene = @import("scene.zig");
const shared_string = @import("shared_string.zig");
const theme = @import("theme.zig");

pub const WindowId = enum(u64) {
    _,
};

pub const WindowState = enum {
    created,
    visible,
    closed,
};

pub const Window = struct {
    id: WindowId,
    options: platform.WindowOptions,
    title_text: shared_string.SharedString,
    native_handle: ?usize = null,
    scene: scene.Scene = .{},
    theme: theme.Theme = .{},
    state: WindowState = .created,

    pub fn init(allocator: std.mem.Allocator, id: WindowId, options: platform.WindowOptions) !Window {
        var owned_title = try shared_string.SharedString.initOwned(allocator, options.title);
        errdefer owned_title.deinit();

        var stored_options = options;
        stored_options.title = owned_title.slice();

        return .{
            .id = id,
            .options = stored_options,
            .title_text = owned_title,
        };
    }

    pub fn deinit(self: *Window, allocator: std.mem.Allocator) void {
        self.title_text.deinit();
        self.scene.deinit(allocator);
    }

    pub fn title(self: *const Window) []const u8 {
        return self.title_text.slice();
    }

    pub fn nativeHandle(self: *const Window) ?usize {
        return self.native_handle;
    }

    pub fn setTitle(self: *Window, allocator: std.mem.Allocator, next_title: []const u8) !void {
        const owned_title = try shared_string.SharedString.initOwned(allocator, next_title);
        self.title_text.deinit();
        self.title_text = owned_title;
        self.options.title = self.title_text.slice();
    }

    pub fn replaceScene(self: *Window, allocator: std.mem.Allocator, next_scene: scene.Scene) void {
        self.scene.deinit(allocator);
        self.scene = next_scene;
    }
};

test "window stores an owned title string" {
    var win = try Window.init(std.testing.allocator, @enumFromInt(1), .{ .title = "demo" });
    defer win.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("demo", win.title());
}

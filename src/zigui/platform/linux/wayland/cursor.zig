const std = @import("std");
const common = @import("../../common.zig");
const c = @import("c.zig").c;

pub const CursorManager = struct {
    allocator: std.mem.Allocator,
    shm: *c.wl_shm,
    surface: *c.wl_surface,
    theme: ?*c.wl_cursor_theme = null,
    theme_name: ?[:0]u8 = null,
    size: u32 = 24,
    scale: u32 = 1,

    pub fn init(
        allocator: std.mem.Allocator,
        compositor: *c.wl_compositor,
        shm: *c.wl_shm,
    ) !CursorManager {
        const surface = c.wl_compositor_create_surface(compositor) orelse return error.SurfaceCreationFailed;
        var manager = CursorManager{
            .allocator = allocator,
            .shm = shm,
            .surface = surface,
        };
        try manager.reloadTheme();
        return manager;
    }

    pub fn deinit(self: *CursorManager) void {
        self.unloadTheme();
        c.wl_surface_destroy(self.surface);
    }

    pub fn setTheme(self: *CursorManager, theme_name: ?[]const u8) !void {
        if (self.theme_name) |existing| {
            if (theme_name) |incoming| {
                if (std.mem.eql(u8, existing, incoming)) return;
            } else return;
        } else if (theme_name == null) return;

        self.unloadThemeName();
        if (theme_name) |name| {
            self.theme_name = try self.allocator.dupeZ(u8, name);
        }
        try self.reloadTheme();
    }

    pub fn setSize(self: *CursorManager, size: u32) !void {
        if (self.size == size) return;
        self.size = @max(size, 1);
        try self.reloadTheme();
    }

    pub fn apply(
        self: *CursorManager,
        pointer: *c.wl_pointer,
        serial: u32,
        cursor_kind: common.Cursor,
        scale: i32,
    ) !void {
        if (scale > 0 and self.scale != @as(u32, @intCast(scale))) {
            self.scale = @intCast(scale);
            try self.reloadTheme();
        }

        const theme = self.theme orelse return error.ThemeUnavailable;
        const cursor_object = findCursor(theme, cursorNames(cursor_kind)) orelse return error.CursorUnavailable;
        if (cursor_object.image_count == 0 or cursor_object.images == null) return error.CursorUnavailable;

        const image = cursor_object.images[0] orelse return error.CursorUnavailable;
        const buffer = c.wl_cursor_image_get_buffer(image) orelse return error.CursorUnavailable;
        c.wl_surface_set_buffer_scale(self.surface, @intCast(self.scale));
        c.wl_pointer_set_cursor(
            pointer,
            serial,
            self.surface,
            @intCast(@divTrunc(image[0].hotspot_x, self.scale)),
            @intCast(@divTrunc(image[0].hotspot_y, self.scale)),
        );
        c.wl_surface_attach(self.surface, buffer, 0, 0);
        c.wl_surface_damage_buffer(self.surface, 0, 0, @intCast(image[0].width), @intCast(image[0].height));
        c.wl_surface_commit(self.surface);
    }

    fn reloadTheme(self: *CursorManager) !void {
        if (self.theme) |theme| c.wl_cursor_theme_destroy(theme);
        self.theme = null;

        const scaled_size = @max(self.size * self.scale, 1);
        const name_ptr = if (self.theme_name) |name| name.ptr else null;
        self.theme = c.wl_cursor_theme_load(name_ptr, @intCast(scaled_size), self.shm) orelse return error.ThemeLoadFailed;
    }

    fn unloadTheme(self: *CursorManager) void {
        if (self.theme) |theme| c.wl_cursor_theme_destroy(theme);
        self.theme = null;
        self.unloadThemeName();
    }

    fn unloadThemeName(self: *CursorManager) void {
        if (self.theme_name) |name| self.allocator.free(name);
        self.theme_name = null;
    }
};

fn findCursor(theme: *c.wl_cursor_theme, names: []const [*:0]const u8) ?*c.wl_cursor {
    for (names) |name| {
        if (c.wl_cursor_theme_get_cursor(theme, name)) |cursor_object| return cursor_object;
    }
    return null;
}

fn cursorNames(cursor_kind: common.Cursor) []const [*:0]const u8 {
    return switch (cursor_kind) {
        .arrow => &.{ "left_ptr", "default", "arrow" },
        .ibeam => &.{ "text", "xterm" },
        .pointing_hand => &.{ "pointer", "hand2", "hand1" },
        .resize_left_right => &.{ "ew-resize", "sb_h_double_arrow" },
        .resize_up_down => &.{ "ns-resize", "sb_v_double_arrow" },
    };
}

test "cursor name mapping provides a fallback chain" {
    try std.testing.expect(cursorNames(.arrow).len >= 2);
    try std.testing.expect(cursorNames(.ibeam).len >= 1);
}

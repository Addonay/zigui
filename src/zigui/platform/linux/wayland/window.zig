const std = @import("std");
const common = @import("../../common.zig");
const c = @import("c.zig").c;
const fractional = @import("fractional_scale.zig");
const output = @import("output.zig");
const types = @import("../types.zig");

pub const SharedMemoryBuffer = struct {
    buffer: *c.wl_buffer,
    memory: []align(std.heap.page_size_min) u8,
    width: u32,
    height: u32,
    stride: u32,

    pub fn create(shm: *c.wl_shm, width: u32, height: u32) !SharedMemoryBuffer {
        const safe_width = @max(width, 1);
        const safe_height = @max(height, 1);
        const stride = safe_width * 4;
        const size = stride * safe_height;

        const fd = try std.posix.memfd_create("zigui-wayland-buffer", 0);
        defer std.posix.close(fd);

        const truncate_result = std.c.ftruncate(fd, @intCast(size));
        if (truncate_result != 0) return error.ResizeFailed;

        const memory = try std.posix.mmap(
            null,
            size,
            std.posix.PROT{ .READ = true, .WRITE = true },
            std.posix.MAP{ .TYPE = .SHARED },
            fd,
            0,
        );
        errdefer std.posix.munmap(memory);

        const pixels = std.mem.bytesAsSlice(u32, memory);
        for (pixels) |*pixel| {
            pixel.* = 0xff202830;
        }

        const pool = c.wl_shm_create_pool(shm, fd, @intCast(size));
        if (pool == null) return error.PoolCreationFailed;
        defer c.wl_shm_pool_destroy(pool);

        const buffer = c.wl_shm_pool_create_buffer(
            pool,
            0,
            @intCast(safe_width),
            @intCast(safe_height),
            @intCast(stride),
            c.WL_SHM_FORMAT_XRGB8888,
        );
        if (buffer == null) return error.BufferCreationFailed;

        return .{
            .buffer = buffer,
            .memory = memory,
            .width = safe_width,
            .height = safe_height,
            .stride = stride,
        };
    }

    pub fn deinit(self: *SharedMemoryBuffer) void {
        c.wl_buffer_destroy(self.buffer);
        std.posix.munmap(self.memory);
    }
};

pub const WaylandWindow = struct {
    allocator: std.mem.Allocator,
    surface: *c.wl_surface,
    xdg_surface: *c.xdg_surface,
    xdg_toplevel: *c.xdg_toplevel,
    decoration: ?*c.zxdg_toplevel_decoration_v1 = null,
    viewport: ?*c.wp_viewport = null,
    fractional_scale: ?*c.wp_fractional_scale_v1 = null,
    title_z: [:0]u8,
    width: u32,
    height: u32,
    resizable: bool,
    decorations: bool,
    server_side_decorations: ?bool = null,
    configured: bool = false,
    close_requested: bool = false,
    fullscreen: bool = false,
    last_configure_serial: u32 = 0,
    preferred_buffer_scale: i32 = 1,
    preferred_fractional_scale_120: u32 = fractional.denominator,
    preferred_buffer_transform: u32 = 0,
    entered_outputs: std.AutoHashMapUnmanaged(output.OutputId, void) = .empty,
    buffer: ?SharedMemoryBuffer = null,

    pub fn create(
        allocator: std.mem.Allocator,
        compositor: *c.wl_compositor,
        wm_base: *c.xdg_wm_base,
        decoration_manager: ?*c.zxdg_decoration_manager_v1,
        viewporter: ?*c.wp_viewporter,
        fractional_scale_manager: ?*c.wp_fractional_scale_manager_v1,
        options: common.WindowOptions,
    ) !WaylandWindow {
        const surface = c.wl_compositor_create_surface(compositor) orelse return error.SurfaceCreationFailed;
        errdefer c.wl_surface_destroy(surface);

        const xdg_surface = c.xdg_wm_base_get_xdg_surface(wm_base, surface) orelse return error.SurfaceCreationFailed;
        errdefer c.xdg_surface_destroy(xdg_surface);

        const xdg_toplevel = c.xdg_surface_get_toplevel(xdg_surface) orelse return error.SurfaceCreationFailed;
        errdefer c.xdg_toplevel_destroy(xdg_toplevel);

        const title_z = try allocator.dupeZ(u8, options.title);
        errdefer allocator.free(title_z);
        const app_id = "zigui";

        var viewport: ?*c.wp_viewport = null;
        if (viewporter) |manager| {
            viewport = c.wp_viewporter_get_viewport(manager, surface) orelse return error.SurfaceCreationFailed;
        }

        var surface_fractional_scale: ?*c.wp_fractional_scale_v1 = null;
        if (fractional_scale_manager) |manager| {
            surface_fractional_scale = c.wp_fractional_scale_manager_v1_get_fractional_scale(manager, surface) orelse return error.SurfaceCreationFailed;
        }

        var decoration: ?*c.zxdg_toplevel_decoration_v1 = null;
        if (decoration_manager) |manager| {
            decoration = c.zxdg_decoration_manager_v1_get_toplevel_decoration(manager, xdg_toplevel) orelse return error.SurfaceCreationFailed;
            if (options.decorations) {
                c.zxdg_toplevel_decoration_v1_set_mode(decoration.?, c.ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
            } else {
                c.zxdg_toplevel_decoration_v1_set_mode(decoration.?, c.ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE);
            }
        }

        c.xdg_toplevel_set_title(xdg_toplevel, title_z.ptr);
        c.xdg_toplevel_set_app_id(xdg_toplevel, app_id);

        return .{
            .allocator = allocator,
            .surface = surface,
            .xdg_surface = xdg_surface,
            .xdg_toplevel = xdg_toplevel,
            .decoration = decoration,
            .viewport = viewport,
            .fractional_scale = surface_fractional_scale,
            .title_z = title_z,
            .width = options.width,
            .height = options.height,
            .resizable = options.resizable,
            .decorations = options.decorations,
        };
    }

    pub fn deinit(self: *WaylandWindow) void {
        if (self.buffer) |*buffer| buffer.deinit();
        self.buffer = null;
        self.entered_outputs.deinit(self.allocator);
        self.allocator.free(self.title_z);
        if (self.fractional_scale) |surface_fractional_scale| c.wp_fractional_scale_v1_destroy(surface_fractional_scale);
        if (self.viewport) |viewport| c.wp_viewport_destroy(viewport);
        if (self.decoration) |decoration| c.zxdg_toplevel_decoration_v1_destroy(decoration);
        c.xdg_toplevel_destroy(self.xdg_toplevel);
        c.xdg_surface_destroy(self.xdg_surface);
        c.wl_surface_destroy(self.surface);
    }

    pub fn commitInitial(self: *WaylandWindow) void {
        c.wl_surface_commit(self.surface);
    }

    pub fn present(
        self: *WaylandWindow,
        shm: *c.wl_shm,
        outputs: *const std.AutoHashMapUnmanaged(output.OutputId, output.OutputInfo),
    ) !void {
        const scale = fractional.FractionalScale.init(self.preferredScale120(outputs));
        const integer_scale = if (scale.isFractional()) 1 else scale.integerScale();
        const buffer_width = scale.scaleDimension(self.width);
        const buffer_height = scale.scaleDimension(self.height);

        if (self.buffer) |*buffer| buffer.deinit();
        self.buffer = try SharedMemoryBuffer.create(shm, buffer_width, buffer_height);
        c.wl_surface_set_buffer_scale(self.surface, integer_scale);
        c.wl_surface_set_buffer_transform(self.surface, self.preferred_buffer_transform);
        if (self.viewport) |viewport| {
            if (scale.isFractional()) {
                c.wp_viewport_set_destination(viewport, @intCast(self.width), @intCast(self.height));
            } else {
                c.wp_viewport_set_destination(viewport, -1, -1);
            }
        }
        c.xdg_surface_set_window_geometry(self.xdg_surface, 0, 0, @intCast(self.width), @intCast(self.height));
        c.wl_surface_attach(self.surface, self.buffer.?.buffer, 0, 0);
        c.wl_surface_damage_buffer(self.surface, 0, 0, @intCast(buffer_width), @intCast(buffer_height));
        c.wl_surface_commit(self.surface);
    }

    pub fn onConfigure(
        self: *WaylandWindow,
        serial: u32,
        shm: *c.wl_shm,
        outputs: *const std.AutoHashMapUnmanaged(output.OutputId, output.OutputInfo),
    ) !void {
        self.last_configure_serial = serial;
        c.xdg_surface_ack_configure(self.xdg_surface, serial);
        self.configured = true;
        try self.present(shm, outputs);
    }

    pub fn onToplevelConfigure(self: *WaylandWindow, width: i32, height: i32, fullscreen: bool) void {
        if (width > 0) self.width = @intCast(width);
        if (height > 0) self.height = @intCast(height);
        self.fullscreen = fullscreen;
    }

    pub fn noteOutputEnter(
        self: *WaylandWindow,
        allocator: std.mem.Allocator,
        id: output.OutputId,
    ) !void {
        try self.entered_outputs.put(allocator, id, {});
    }

    pub fn noteOutputLeave(self: *WaylandWindow, id: output.OutputId) void {
        _ = self.entered_outputs.remove(id);
    }

    pub fn setPreferredBufferScale(self: *WaylandWindow, factor: i32) void {
        self.preferred_buffer_scale = @max(factor, 1);
    }

    pub fn setPreferredFractionalScale(self: *WaylandWindow, scale_120: u32) void {
        self.preferred_fractional_scale_120 = @max(scale_120, fractional.denominator);
    }

    pub fn setPreferredBufferTransform(self: *WaylandWindow, transform: u32) void {
        self.preferred_buffer_transform = transform;
    }

    pub fn handleDecorationConfigure(self: *WaylandWindow, mode: u32) void {
        self.server_side_decorations = switch (mode) {
            c.ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE => true,
            c.ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE => false,
            else => self.server_side_decorations,
        };
    }

    pub fn snapshot(
        self: *const WaylandWindow,
        outputs: *const std.AutoHashMapUnmanaged(output.OutputId, output.OutputInfo),
        active: bool,
        hovered: bool,
    ) types.LinuxWindowInfo {
        return .{
            .id = @intFromPtr(self.surface),
            .title = self.title_z,
            .width = self.width,
            .height = self.height,
            .scale_factor = @as(f32, @floatFromInt(self.preferredScale120(outputs))) / fractional.denominator,
            .active = active,
            .hovered = hovered,
            .fullscreen = self.fullscreen,
            .decorated = self.server_side_decorations orelse self.decorations,
            .resizable = self.resizable,
            .visible = !self.close_requested,
        };
    }

    pub fn primaryOutputScale(
        self: *const WaylandWindow,
        outputs: *const std.AutoHashMapUnmanaged(output.OutputId, output.OutputInfo),
    ) i32 {
        return fractional.FractionalScale.init(self.preferredScale120(outputs)).cursorScale();
    }

    pub fn preferredScale120(
        self: *const WaylandWindow,
        outputs: *const std.AutoHashMapUnmanaged(output.OutputId, output.OutputInfo),
    ) u32 {
        var scale_120 = @max(@as(u32, @intCast(self.preferred_buffer_scale)), 1) * fractional.denominator;
        scale_120 = @max(scale_120, self.preferred_fractional_scale_120);
        var iterator = self.entered_outputs.iterator();
        while (iterator.next()) |entry| {
            if (outputs.get(entry.key_ptr.*)) |display| {
                scale_120 = @max(scale_120, @as(u32, @intCast(display.scale)) * fractional.denominator);
            }
        }
        return @max(scale_120, fractional.denominator);
    }
};

test "window primary scale prefers the largest entered output scale" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var outputs: std.AutoHashMapUnmanaged(output.OutputId, output.OutputInfo) = .empty;
    defer {
        var iterator = outputs.valueIterator();
        while (iterator.next()) |display| display.deinit(allocator);
        outputs.deinit(allocator);
    }

    try outputs.put(allocator, 1, .{ .id = 1, .x = 0, .y = 0, .width = 1920, .height = 1080, .scale = 1 });
    try outputs.put(allocator, 2, .{ .id = 2, .x = 1920, .y = 0, .width = 2560, .height = 1440, .scale = 2 });

    var window = WaylandWindow{
        .allocator = allocator,
        .surface = undefined,
        .xdg_surface = undefined,
        .xdg_toplevel = undefined,
        .title_z = undefined,
        .width = 800,
        .height = 600,
        .resizable = true,
        .decorations = true,
    };
    try window.noteOutputEnter(allocator, 1);
    try window.noteOutputEnter(allocator, 2);
    defer window.entered_outputs.deinit(allocator);

    try std.testing.expectEqual(@as(i32, 2), window.primaryOutputScale(&outputs));
    try std.testing.expectEqual(@as(u32, 240), window.preferredScale120(&outputs));
}

test "window stores negotiated decoration mode" {
    var window = WaylandWindow{
        .allocator = std.testing.allocator,
        .surface = undefined,
        .xdg_surface = undefined,
        .xdg_toplevel = undefined,
        .title_z = undefined,
        .width = 640,
        .height = 480,
        .resizable = true,
        .decorations = true,
    };
    window.handleDecorationConfigure(c.ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
    try std.testing.expectEqual(@as(?bool, true), window.server_side_decorations);
    window.handleDecorationConfigure(c.ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE);
    try std.testing.expectEqual(@as(?bool, false), window.server_side_decorations);
}

test "fractional scale affects preferred scale and cursor scale" {
    var window = WaylandWindow{
        .allocator = std.testing.allocator,
        .surface = undefined,
        .xdg_surface = undefined,
        .xdg_toplevel = undefined,
        .title_z = undefined,
        .width = 800,
        .height = 600,
        .resizable = true,
        .decorations = true,
    };
    window.setPreferredFractionalScale(180);

    const outputs: std.AutoHashMapUnmanaged(output.OutputId, output.OutputInfo) = .empty;
    try std.testing.expectEqual(@as(u32, 180), window.preferredScale120(&outputs));
    try std.testing.expectEqual(@as(i32, 2), window.primaryOutputScale(&outputs));
}

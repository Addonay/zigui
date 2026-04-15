const std = @import("std");
const common = @import("../../../zigui/common.zig");
const c = @import("c.zig").c;
const fractional = @import("fractional_scale.zig");
const output = @import("output.zig");
const types = @import("../types.zig");

const body_background = argb(0xff, 0x1c, 0x24, 0x2d);
const header_background_active = argb(0xff, 0x2a, 0x33, 0x40);
const header_background_inactive = argb(0xff, 0x33, 0x3b, 0x48);
const frame_border_active = argb(0xff, 0x57, 0x65, 0x78);
const frame_border_inactive = argb(0xff, 0x4a, 0x56, 0x68);
const header_separator = argb(0xff, 0x47, 0x52, 0x61);
const accent_strip = argb(0xff, 0xc1, 0x64, 0x4b);
const title_color = argb(0xff, 0xf2, 0xf5, 0xf8);
const body_title_color = argb(0xff, 0x8a, 0x9c, 0xb1);
const control_fill = argb(0xff, 0x3d, 0x48, 0x58);
const control_close_fill = argb(0xff, 0xd4, 0x66, 0x57);
const control_icon = argb(0xff, 0xf3, 0xf6, 0xf8);
const control_close_icon = argb(0xff, 0x18, 0x1b, 0x20);

pub const DecorationHit = union(enum) {
    content,
    titlebar,
    minimize,
    maximize,
    close,
    resize: u32,
};

const Rect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    fn contains(self: Rect, px: f64, py: f64) bool {
        const left = @as(f64, @floatFromInt(self.x));
        const top = @as(f64, @floatFromInt(self.y));
        const right = @as(f64, @floatFromInt(self.x + self.w));
        const bottom = @as(f64, @floatFromInt(self.y + self.h));
        return px >= left and px < right and py >= top and py < bottom;
    }
};

const DecorationLayout = struct {
    border: i32,
    titlebar_height: i32,
    radius: i32,
    resize_margin: i32,
    button_size: i32,
    button_gap: i32,
    button_padding: i32,
    body_padding: i32,
    accent_height: i32,

    fn init(window: *const WaylandWindow) DecorationLayout {
        return .{
            .border = if (window.usesClientSideDecorations()) 1 else 0,
            .titlebar_height = if (window.usesClientSideDecorations()) 44 else 0,
            .radius = if (window.hasRoundedCorners()) 14 else 0,
            .resize_margin = if (window.usesClientSideDecorations() and window.canInteractiveResize()) 6 else 0,
            .button_size = if (window.usesClientSideDecorations()) 28 else 0,
            .button_gap = if (window.usesClientSideDecorations()) 8 else 0,
            .button_padding = if (window.usesClientSideDecorations()) 12 else 0,
            .body_padding = if (window.usesClientSideDecorations()) 28 else 24,
            .accent_height = if (window.usesClientSideDecorations()) 3 else 0,
        };
    }

    fn scaled(self: DecorationLayout, scale: fractional.FractionalScale) DecorationLayout {
        return .{
            .border = scaleMetric(scale, self.border),
            .titlebar_height = scaleMetric(scale, self.titlebar_height),
            .radius = scaleMetric(scale, self.radius),
            .resize_margin = scaleMetric(scale, self.resize_margin),
            .button_size = scaleMetric(scale, self.button_size),
            .button_gap = scaleMetric(scale, self.button_gap),
            .button_padding = scaleMetric(scale, self.button_padding),
            .body_padding = scaleMetric(scale, self.body_padding),
            .accent_height = scaleMetric(scale, self.accent_height),
        };
    }

    fn innerRect(self: DecorationLayout, width: i32, height: i32) Rect {
        return .{
            .x = self.border,
            .y = self.border,
            .w = @max(width - (self.border * 2), 1),
            .h = @max(height - (self.border * 2), 1),
        };
    }

    fn buttonY(self: DecorationLayout) i32 {
        if (self.button_size == 0) return 0;
        return @max(@divTrunc(self.titlebar_height - self.button_size, 2), self.border);
    }

    fn closeRect(self: DecorationLayout, width: i32) Rect {
        return .{
            .x = width - self.button_padding - self.button_size,
            .y = self.buttonY(),
            .w = self.button_size,
            .h = self.button_size,
        };
    }

    fn maximizeRect(self: DecorationLayout, width: i32) Rect {
        const close = self.closeRect(width);
        return .{
            .x = close.x - self.button_gap - self.button_size,
            .y = close.y,
            .w = self.button_size,
            .h = self.button_size,
        };
    }

    fn minimizeRect(self: DecorationLayout, width: i32) Rect {
        const maximize = self.maximizeRect(width);
        return .{
            .x = maximize.x - self.button_gap - self.button_size,
            .y = maximize.y,
            .w = self.button_size,
            .h = self.button_size,
        };
    }

    fn headerTextRect(self: DecorationLayout, width: i32) Rect {
        const left = self.border + self.body_padding;
        const right = self.minimizeRect(width).x - self.body_padding;
        return .{
            .x = left,
            .y = self.border,
            .w = @max(right - left, 1),
            .h = @max(self.titlebar_height, 1),
        };
    }

    fn bodyTextRect(self: DecorationLayout, width: i32, height: i32) Rect {
        const inner = self.innerRect(width, height);
        return .{
            .x = inner.x + self.body_padding,
            .y = inner.y + self.titlebar_height + self.body_padding,
            .w = @max(inner.w - (self.body_padding * 2), 1),
            .h = @max(inner.h - self.titlebar_height - (self.body_padding * 2), 1),
        };
    }
};

const Canvas = struct {
    pixels: []u32,
    width: i32,
    height: i32,
    stride: i32,

    fn init(buffer: *SharedMemoryBuffer) Canvas {
        return .{
            .pixels = std.mem.bytesAsSlice(u32, buffer.memory),
            .width = @intCast(buffer.width),
            .height = @intCast(buffer.height),
            .stride = @intCast(buffer.stride / 4),
        };
    }

    fn clear(self: *Canvas, color: u32) void {
        for (self.pixels) |*pixel| pixel.* = color;
    }

    fn setPixel(self: *Canvas, x: i32, y: i32, color: u32) void {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) return;
        const offset = @as(usize, @intCast(y * self.stride + x));
        self.pixels[offset] = color;
    }

    fn fillRect(self: *Canvas, rect: Rect, color: u32) void {
        const clamped = clampRect(rect, self.width, self.height);
        if (clamped.w <= 0 or clamped.h <= 0) return;

        var y = clamped.y;
        while (y < clamped.y + clamped.h) : (y += 1) {
            var x = clamped.x;
            while (x < clamped.x + clamped.w) : (x += 1) {
                self.setPixel(x, y, color);
            }
        }
    }

    fn fillRoundedRect(self: *Canvas, rect: Rect, radius: i32, color: u32) void {
        self.fillRoundedRectClipped(rect, radius, rect, color);
    }

    fn fillRoundedRectClipped(self: *Canvas, rect: Rect, radius: i32, clip: Rect, color: u32) void {
        const clipped = clampRect(intersectRect(rect, clip), self.width, self.height);
        if (clipped.w <= 0 or clipped.h <= 0) return;

        var y = clipped.y;
        while (y < clipped.y + clipped.h) : (y += 1) {
            var x = clipped.x;
            while (x < clipped.x + clipped.w) : (x += 1) {
                if (pointInsideRoundedRect(x, y, rect, radius)) {
                    self.setPixel(x, y, color);
                }
            }
        }
    }

    fn drawHorizontalLine(self: *Canvas, x: i32, y: i32, width: i32, color: u32) void {
        if (width <= 0) return;
        self.fillRect(.{ .x = x, .y = y, .w = width, .h = 1 }, color);
    }

    fn drawVerticalLine(self: *Canvas, x: i32, y: i32, height: i32, color: u32) void {
        if (height <= 0) return;
        self.fillRect(.{ .x = x, .y = y, .w = 1, .h = height }, color);
    }

    fn drawRectOutline(self: *Canvas, rect: Rect, color: u32) void {
        if (rect.w <= 0 or rect.h <= 0) return;
        self.drawHorizontalLine(rect.x, rect.y, rect.w, color);
        self.drawHorizontalLine(rect.x, rect.y + rect.h - 1, rect.w, color);
        self.drawVerticalLine(rect.x, rect.y, rect.h, color);
        self.drawVerticalLine(rect.x + rect.w - 1, rect.y, rect.h, color);
    }

    fn drawDiagonal(self: *Canvas, rect: Rect, ascending: bool, color: u32) void {
        const span = @max(@min(rect.w, rect.h), 1);
        const thickness = @max(@divTrunc(span, 7), 1);

        var step: i32 = 0;
        while (step < span) : (step += 1) {
            const x = rect.x + step;
            const y = if (ascending)
                rect.y + rect.h - 1 - step
            else
                rect.y + step;

            var offset: i32 = 0;
            while (offset < thickness) : (offset += 1) {
                self.setPixel(x, y + offset - @divTrunc(thickness, 2), color);
                self.setPixel(x + offset - @divTrunc(thickness, 2), y, color);
            }
        }
    }

    fn drawGlyph(self: *Canvas, x: i32, y: i32, scale: i32, color: u32, glyph: [7]u8) void {
        if (scale <= 0) return;
        for (glyph, 0..) |row_bits, row_index| {
            var col: u3 = 0;
            while (col < 5) : (col += 1) {
                const shift = 4 - col;
                if (((row_bits >> shift) & 1) == 0) continue;
                self.fillRect(.{
                    .x = x + (@as(i32, col) * scale),
                    .y = y + (@as(i32, @intCast(row_index)) * scale),
                    .w = scale,
                    .h = scale,
                }, color);
            }
        }
    }

    fn drawText(self: *Canvas, x: i32, y: i32, scale: i32, color: u32, text: []const u8) void {
        if (text.len == 0 or scale <= 0) return;
        var cursor_x = x;
        for (text) |char| {
            self.drawGlyph(cursor_x, y, scale, color, glyphFor(char));
            cursor_x += glyphAdvance(scale);
        }
    }
};

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
        defer _ = std.c.close(fd);

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
            pixel.* = 0x00000000;
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
            c.WL_SHM_FORMAT_ARGB8888,
        ) orelse return error.BufferCreationFailed;

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
    title_z: [:0]const u8,
    width: u32,
    height: u32,
    resizable: bool,
    decorations: common.WindowDecorations,
    server_side_decorations: ?bool = null,
    configured: bool = false,
    close_requested: bool = false,
    fullscreen: bool = false,
    maximized: bool = false,
    activated: bool = true,
    tiled_left: bool = false,
    tiled_right: bool = false,
    tiled_top: bool = false,
    tiled_bottom: bool = false,
    last_configure_serial: u32 = 0,
    preferred_buffer_scale: i32 = 1,
    preferred_fractional_scale_120: u32 = fractional.denominator,
    preferred_buffer_transform: u32 = 0,
    entered_outputs: std.AutoHashMapUnmanaged(output.OutputId, void) = .empty,
    buffer: ?SharedMemoryBuffer = null,
    client_inset: u32 = 0,
    window_controls: common.WindowControls = .{},

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
            if (options.decorations == .server) {
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
        self.renderSharedMemorySurface(&self.buffer.?, scale);
        c.wl_surface_set_buffer_scale(self.surface, integer_scale);
        c.wl_surface_set_buffer_transform(self.surface, @intCast(self.preferred_buffer_transform));
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

    pub fn onToplevelConfigure(
        self: *WaylandWindow,
        width: i32,
        height: i32,
        maximized: bool,
        fullscreen: bool,
        activated: bool,
        tiled_left: bool,
        tiled_right: bool,
        tiled_top: bool,
        tiled_bottom: bool,
    ) void {
        if (width > 0) self.width = @intCast(width);
        if (height > 0) self.height = @intCast(height);
        self.maximized = maximized;
        self.fullscreen = fullscreen;
        self.activated = activated;
        self.tiled_left = tiled_left;
        self.tiled_right = tiled_right;
        self.tiled_top = tiled_top;
        self.tiled_bottom = tiled_bottom;
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

    pub fn usesClientSideDecorations(self: *const WaylandWindow) bool {
        return self.decorations == .client or
            (self.decorations == .server and !self.fullscreen and self.server_side_decorations != true);
    }

    pub fn canInteractiveResize(self: *const WaylandWindow) bool {
        return self.resizable and !self.fullscreen and !self.maximized and !self.isTiled();
    }

    pub fn decorationHitTest(self: *const WaylandWindow, x: f64, y: f64) DecorationHit {
        if (!self.usesClientSideDecorations()) return .content;

        const layout = DecorationLayout.init(self);
        const outer = Rect{
            .x = 0,
            .y = 0,
            .w = @intCast(self.width),
            .h = @intCast(self.height),
        };
        if (!pointInsideRoundedRectFloat(x, y, outer, layout.radius)) return .content;

        if (self.canInteractiveResize()) {
            if (resizeEdgeForPosition(self, layout, x, y)) |edge| {
                return .{ .resize = edge };
            }
        }

        if (y < @as(f64, @floatFromInt(layout.titlebar_height))) {
            const width_i: i32 = @intCast(self.width);
            if (layout.closeRect(width_i).contains(x, y)) return .close;
            if (layout.maximizeRect(width_i).contains(x, y)) return .maximize;
            if (layout.minimizeRect(width_i).contains(x, y)) return .minimize;
            return .titlebar;
        }

        return .content;
    }

    pub fn decorationCursor(self: *const WaylandWindow, x: f64, y: f64) ?common.Cursor {
        return switch (self.decorationHitTest(x, y)) {
            .content => null,
            .titlebar, .minimize, .maximize, .close => .arrow,
            .resize => |edge| switch (edge) {
                c.XDG_TOPLEVEL_RESIZE_EDGE_TOP,
                c.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM,
                => .resize_up_down,
                c.XDG_TOPLEVEL_RESIZE_EDGE_LEFT,
                c.XDG_TOPLEVEL_RESIZE_EDGE_RIGHT,
                => .resize_left_right,
                c.XDG_TOPLEVEL_RESIZE_EDGE_TOP_LEFT,
                c.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_RIGHT,
                => .resize_up_left_down_right,
                c.XDG_TOPLEVEL_RESIZE_EDGE_TOP_RIGHT,
                c.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_LEFT,
                => .resize_up_right_down_left,
                else => .arrow,
            },
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
            .decorated = !self.fullscreen,
            .decorations = self.actualDecorations(),
            .resizable = self.resizable,
            .visible = !self.close_requested,
            .window_controls = self.window_controls,
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

    fn isTiled(self: *const WaylandWindow) bool {
        return self.tiled_left or self.tiled_right or self.tiled_top or self.tiled_bottom;
    }

    pub fn actualDecorations(self: *const WaylandWindow) common.Decorations {
        if (self.usesClientSideDecorations()) {
            return .{
                .client = .{
                    .top = self.tiled_top,
                    .left = self.tiled_left,
                    .right = self.tiled_right,
                    .bottom = self.tiled_bottom,
                },
            };
        }
        return .server;
    }

    pub fn requestDecorations(self: *WaylandWindow, decorations: common.WindowDecorations) void {
        self.decorations = decorations;
        if (self.decoration) |decoration| {
            c.zxdg_toplevel_decoration_v1_set_mode(decoration, switch (decorations) {
                .server => c.ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE,
                .client => c.ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE,
            });
        } else if (decorations == .client) {
            self.server_side_decorations = false;
        }
    }

    pub fn setTitle(self: *WaylandWindow, allocator: std.mem.Allocator, title: []const u8) !void {
        const title_z = try allocator.dupeZ(u8, title);
        errdefer allocator.free(title_z);

        allocator.free(self.title_z);
        self.title_z = title_z;
        c.xdg_toplevel_set_title(self.xdg_toplevel, self.title_z.ptr);
    }

    pub fn setClientInset(self: *WaylandWindow, inset: u32) void {
        self.client_inset = inset;
    }

    fn hasRoundedCorners(self: *const WaylandWindow) bool {
        return self.usesClientSideDecorations() and !self.maximized and !self.isTiled();
    }

    fn renderSharedMemorySurface(
        self: *const WaylandWindow,
        buffer: *SharedMemoryBuffer,
        scale: fractional.FractionalScale,
    ) void {
        var canvas = Canvas.init(buffer);
        canvas.clear(0x00000000);

        const width = @as(i32, @intCast(buffer.width));
        const height = @as(i32, @intCast(buffer.height));
        const outer = Rect{ .x = 0, .y = 0, .w = width, .h = height };

        if (self.usesClientSideDecorations()) {
            const layout = DecorationLayout.init(self).scaled(scale);
            const inner = layout.innerRect(width, height);
            const inner_radius = @max(layout.radius - layout.border, 0);
            const border_color = if (self.activated) frame_border_active else frame_border_inactive;
            const header_color = if (self.activated) header_background_active else header_background_inactive;

            canvas.fillRoundedRect(outer, layout.radius, border_color);
            canvas.fillRoundedRect(inner, inner_radius, body_background);
            canvas.fillRoundedRectClipped(
                inner,
                inner_radius,
                .{ .x = inner.x, .y = inner.y, .w = inner.w, .h = @min(layout.titlebar_height, inner.h) },
                header_color,
            );
            if (layout.accent_height > 0) {
                canvas.fillRoundedRectClipped(
                    inner,
                    inner_radius,
                    .{ .x = inner.x, .y = inner.y, .w = inner.w, .h = @min(layout.accent_height, inner.h) },
                    accent_strip,
                );
            }
            if (layout.titlebar_height > 0 and inner.h > layout.titlebar_height) {
                canvas.drawHorizontalLine(
                    inner.x,
                    inner.y + layout.titlebar_height,
                    inner.w,
                    header_separator,
                );
            }
            self.drawWindowControls(&canvas, layout, width);
            self.drawWindowTitles(&canvas, layout, width, height);
            return;
        }

        canvas.fillRect(outer, body_background);
        self.drawFallbackBodyTitle(&canvas, DecorationLayout.init(self).scaled(scale), width, height);
    }

    fn drawWindowControls(
        self: *const WaylandWindow,
        canvas: *Canvas,
        layout: DecorationLayout,
        width: i32,
    ) void {
        const close_rect = layout.closeRect(width);
        const maximize_rect = layout.maximizeRect(width);
        const minimize_rect = layout.minimizeRect(width);
        const corner_radius = @max(@divTrunc(layout.button_size, 2), 1);

        canvas.fillRoundedRect(close_rect, corner_radius, control_close_fill);
        canvas.fillRoundedRect(maximize_rect, corner_radius, control_fill);
        canvas.fillRoundedRect(minimize_rect, corner_radius, control_fill);

        drawControlCloseIcon(canvas, close_rect);
        drawControlMaximizeIcon(canvas, maximize_rect, self.maximized);
        drawControlMinimizeIcon(canvas, minimize_rect);
    }

    fn drawWindowTitles(
        self: *const WaylandWindow,
        canvas: *Canvas,
        layout: DecorationLayout,
        width: i32,
        height: i32,
    ) void {
        const header_rect = layout.headerTextRect(width);
        var header_scale: i32 = if (layout.titlebar_height >= 60) 3 else if (layout.titlebar_height >= 40) 2 else 1;
        while (header_scale > 1 and measureTextWidth(self.title_z, header_scale) > header_rect.w) {
            header_scale -= 1;
        }
        const fitting_header = textSliceToFit(self.title_z, header_scale, header_rect.w);
        if (fitting_header.len != 0) {
            const header_text_width = measureTextWidth(fitting_header, header_scale);
            canvas.drawText(
                header_rect.x + @divTrunc(header_rect.w - header_text_width, 2),
                header_rect.y + @divTrunc(header_rect.h - glyphHeight(header_scale), 2),
                header_scale,
                title_color,
                fitting_header,
            );
        }

        self.drawFallbackBodyTitle(canvas, layout, width, height);
    }

    fn drawFallbackBodyTitle(
        self: *const WaylandWindow,
        canvas: *Canvas,
        layout: DecorationLayout,
        width: i32,
        height: i32,
    ) void {
        const body_rect = layout.bodyTextRect(width, height);
        if (body_rect.w <= 0 or body_rect.h <= 0 or self.title_z.len == 0) return;

        var title_scale: i32 = if (body_rect.w >= 780) 5 else if (body_rect.w >= 520) 4 else if (body_rect.w >= 340) 3 else 2;
        while (title_scale > 1 and measureTextWidth(self.title_z, title_scale) > body_rect.w) {
            title_scale -= 1;
        }
        const fitting_title = textSliceToFit(self.title_z, title_scale, body_rect.w);
        if (fitting_title.len == 0) return;

        const title_width = measureTextWidth(fitting_title, title_scale);
        const title_height = glyphHeight(title_scale);
        const title_y = body_rect.y + @divTrunc(body_rect.h - title_height, 2);
        canvas.drawText(
            body_rect.x + @divTrunc(body_rect.w - title_width, 2),
            title_y,
            title_scale,
            body_title_color,
            fitting_title,
        );
    }
};

fn resizeEdgeForPosition(
    window: *const WaylandWindow,
    layout: DecorationLayout,
    x: f64,
    y: f64,
) ?u32 {
    const width = @as(f64, @floatFromInt(window.width));
    const height = @as(f64, @floatFromInt(window.height));
    const margin = @as(f64, @floatFromInt(layout.resize_margin));
    if (margin <= 0) return null;

    const near_left = x < margin;
    const near_right = x >= width - margin;
    const near_top = y < margin;
    const near_bottom = y >= height - margin;

    if (near_top and near_left) return c.XDG_TOPLEVEL_RESIZE_EDGE_TOP_LEFT;
    if (near_top and near_right) return c.XDG_TOPLEVEL_RESIZE_EDGE_TOP_RIGHT;
    if (near_bottom and near_left) return c.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_LEFT;
    if (near_bottom and near_right) return c.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_RIGHT;
    if (near_top) return c.XDG_TOPLEVEL_RESIZE_EDGE_TOP;
    if (near_bottom) return c.XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM;
    if (near_left) return c.XDG_TOPLEVEL_RESIZE_EDGE_LEFT;
    if (near_right) return c.XDG_TOPLEVEL_RESIZE_EDGE_RIGHT;
    return null;
}

fn scaleMetric(scale: fractional.FractionalScale, value: i32) i32 {
    if (value <= 0) return 0;
    return @intCast(scale.scaleDimension(@intCast(value)));
}

fn argb(a: u8, r: u8, g: u8, b: u8) u32 {
    return (@as(u32, a) << 24) | (@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b);
}

fn clampRect(rect: Rect, width: i32, height: i32) Rect {
    const x0 = @max(rect.x, 0);
    const y0 = @max(rect.y, 0);
    const x1 = @min(rect.x + rect.w, width);
    const y1 = @min(rect.y + rect.h, height);
    return .{
        .x = x0,
        .y = y0,
        .w = @max(x1 - x0, 0),
        .h = @max(y1 - y0, 0),
    };
}

fn intersectRect(a: Rect, b: Rect) Rect {
    const x0 = @max(a.x, b.x);
    const y0 = @max(a.y, b.y);
    const x1 = @min(a.x + a.w, b.x + b.w);
    const y1 = @min(a.y + a.h, b.y + b.h);
    return .{
        .x = x0,
        .y = y0,
        .w = @max(x1 - x0, 0),
        .h = @max(y1 - y0, 0),
    };
}

fn pointInsideRoundedRectFloat(px: f64, py: f64, rect: Rect, radius: i32) bool {
    if (!rect.contains(px, py)) return false;
    if (radius <= 0) return true;

    const rx = @as(f64, @floatFromInt(rect.x));
    const ry = @as(f64, @floatFromInt(rect.y));
    const rw = @as(f64, @floatFromInt(rect.w));
    const rh = @as(f64, @floatFromInt(rect.h));
    const radius_f = @as(f64, @floatFromInt(radius));
    const right = rx + rw - 1;
    const bottom = ry + rh - 1;

    if ((px >= rx + radius_f and px <= right - radius_f) or
        (py >= ry + radius_f and py <= bottom - radius_f))
    {
        return true;
    }

    const cx = if (px < rx + radius_f) rx + radius_f - 1 else right - radius_f + 1;
    const cy = if (py < ry + radius_f) ry + radius_f - 1 else bottom - radius_f + 1;
    const dx = px - cx;
    const dy = py - cy;
    const inner = @max(radius - 1, 0);
    const inner_f = @as(f64, @floatFromInt(inner));
    return (dx * dx) + (dy * dy) <= inner_f * inner_f;
}

fn pointInsideRoundedRect(px: i32, py: i32, rect: Rect, radius: i32) bool {
    return pointInsideRoundedRectFloat(@floatFromInt(px), @floatFromInt(py), rect, radius);
}

fn glyphAdvance(scale: i32) i32 {
    return (5 * scale) + scale;
}

fn glyphHeight(scale: i32) i32 {
    return 7 * scale;
}

fn measureTextWidth(text: []const u8, scale: i32) i32 {
    if (text.len == 0 or scale <= 0) return 0;
    return (@as(i32, @intCast(text.len)) * glyphAdvance(scale)) - scale;
}

fn textSliceToFit(text: []const u8, scale: i32, max_width: i32) []const u8 {
    if (scale <= 0 or max_width <= 0) return "";
    var len = text.len;
    while (len > 0 and measureTextWidth(text[0..len], scale) > max_width) : (len -= 1) {}
    return text[0..len];
}

fn drawControlMinimizeIcon(canvas: *Canvas, rect: Rect) void {
    const icon_width = @max(@divTrunc(rect.w * 3, 5), 6);
    const icon_x = rect.x + @divTrunc(rect.w - icon_width, 2);
    const icon_y = rect.y + @divTrunc(rect.h, 2) + @divTrunc(rect.h, 10);
    const thickness = @max(@divTrunc(rect.h, 10), 2);
    canvas.fillRect(.{
        .x = icon_x,
        .y = icon_y,
        .w = icon_width,
        .h = thickness,
    }, control_icon);
}

fn drawControlMaximizeIcon(canvas: *Canvas, rect: Rect, maximized: bool) void {
    const size = @max(@divTrunc(rect.w * 11, 20), 7);
    const outline = Rect{
        .x = rect.x + @divTrunc(rect.w - size, 2),
        .y = rect.y + @divTrunc(rect.h - size, 2),
        .w = size,
        .h = size,
    };
    if (maximized) {
        canvas.drawRectOutline(outline, control_icon);
        canvas.drawRectOutline(.{
            .x = outline.x + @max(@divTrunc(size, 4), 1),
            .y = outline.y - @max(@divTrunc(size, 5), 1),
            .w = size,
            .h = size,
        }, control_icon);
    } else {
        canvas.drawRectOutline(outline, control_icon);
    }
}

fn drawControlCloseIcon(canvas: *Canvas, rect: Rect) void {
    const inset = @max(@divTrunc(rect.w, 4), 4);
    const icon_rect = Rect{
        .x = rect.x + inset,
        .y = rect.y + inset,
        .w = @max(rect.w - (inset * 2), 4),
        .h = @max(rect.h - (inset * 2), 4),
    };
    canvas.drawDiagonal(icon_rect, false, control_close_icon);
    canvas.drawDiagonal(icon_rect, true, control_close_icon);
}

fn glyphFor(char: u8) [7]u8 {
    return switch (std.ascii.toUpper(char)) {
        'A' => .{ 0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11 },
        'B' => .{ 0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E },
        'C' => .{ 0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E },
        'D' => .{ 0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E },
        'E' => .{ 0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F },
        'F' => .{ 0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10 },
        'G' => .{ 0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F },
        'H' => .{ 0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11 },
        'I' => .{ 0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E },
        'J' => .{ 0x01, 0x01, 0x01, 0x01, 0x11, 0x11, 0x0E },
        'K' => .{ 0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11 },
        'L' => .{ 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F },
        'M' => .{ 0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11 },
        'N' => .{ 0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11 },
        'O' => .{ 0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E },
        'P' => .{ 0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10 },
        'Q' => .{ 0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D },
        'R' => .{ 0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11 },
        'S' => .{ 0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E },
        'T' => .{ 0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04 },
        'U' => .{ 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E },
        'V' => .{ 0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04 },
        'W' => .{ 0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A },
        'X' => .{ 0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11 },
        'Y' => .{ 0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04 },
        'Z' => .{ 0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F },
        '0' => .{ 0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E },
        '1' => .{ 0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E },
        '2' => .{ 0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F },
        '3' => .{ 0x1E, 0x01, 0x01, 0x0E, 0x01, 0x01, 0x1E },
        '4' => .{ 0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02 },
        '5' => .{ 0x1F, 0x10, 0x10, 0x1E, 0x01, 0x01, 0x1E },
        '6' => .{ 0x0E, 0x10, 0x10, 0x1E, 0x11, 0x11, 0x0E },
        '7' => .{ 0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08 },
        '8' => .{ 0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E },
        '9' => .{ 0x0E, 0x11, 0x11, 0x0F, 0x01, 0x01, 0x0E },
        '!' => .{ 0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04 },
        ':' => .{ 0x00, 0x04, 0x04, 0x00, 0x04, 0x04, 0x00 },
        '.' => .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C },
        '-' => .{ 0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00 },
        '_' => .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1F },
        '/' => .{ 0x01, 0x01, 0x02, 0x04, 0x08, 0x10, 0x10 },
        ' ' => .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        else => .{ 0x1F, 0x11, 0x05, 0x02, 0x04, 0x00, 0x04 },
    };
}

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
        .title_z = "scale-test",
        .width = 800,
        .height = 600,
        .resizable = true,
        .decorations = .server,
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
        .title_z = "decor-test",
        .width = 640,
        .height = 480,
        .resizable = true,
        .decorations = .server,
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
        .title_z = "fractional-test",
        .width = 800,
        .height = 600,
        .resizable = true,
        .decorations = .server,
    };
    window.setPreferredFractionalScale(180);

    const outputs: std.AutoHashMapUnmanaged(output.OutputId, output.OutputInfo) = .empty;
    try std.testing.expectEqual(@as(u32, 180), window.preferredScale120(&outputs));
    try std.testing.expectEqual(@as(i32, 2), window.primaryOutputScale(&outputs));
}

test "client-side decorations stay marked decorated" {
    var window = WaylandWindow{
        .allocator = std.testing.allocator,
        .surface = undefined,
        .xdg_surface = undefined,
        .xdg_toplevel = undefined,
        .title_z = "client-side",
        .width = 960,
        .height = 640,
        .resizable = true,
        .decorations = .server,
        .server_side_decorations = false,
    };

    const outputs: std.AutoHashMapUnmanaged(output.OutputId, output.OutputInfo) = .empty;
    const info = window.snapshot(&outputs, true, false);
    try std.testing.expect(info.decorated);
    try std.testing.expect(window.usesClientSideDecorations());
}

test "decoration hit test finds titlebar buttons and resize edges" {
    var window = WaylandWindow{
        .allocator = std.testing.allocator,
        .surface = undefined,
        .xdg_surface = undefined,
        .xdg_toplevel = undefined,
        .title_z = "hit-test",
        .width = 960,
        .height = 640,
        .resizable = true,
        .decorations = .server,
        .server_side_decorations = false,
    };

    try std.testing.expectEqualDeep(DecorationHit.titlebar, window.decorationHitTest(120, 20));
    try std.testing.expectEqualDeep(DecorationHit.close, window.decorationHitTest(940, 18));
    try std.testing.expectEqualDeep(DecorationHit{ .resize = c.XDG_TOPLEVEL_RESIZE_EDGE_TOP_LEFT }, window.decorationHitTest(2, 2));
}

const std = @import("std");
const scene = @import("../../zigui/scene.zig");
const style = @import("../../zigui/style.zig");
const atlas = @import("metal_atlas.zig");

pub const MetalRendererDevices = struct {
    adapter_name: ?[]const u8 = null,
    supports_gpu_rendering: bool = true,
    supports_layer_backing: bool = true,
    supports_present_wait: bool = true,

    pub fn supportsGpuRendering(self: *const MetalRendererDevices) bool {
        return self.supports_gpu_rendering;
    }
};

pub const MetalRendererConfig = MetalRendererDevices;

pub const MetalResources = struct {
    drawable_surface_ready: bool = false,
    command_queue_ready: bool = false,
    texture_cache_ready: bool = false,
    viewport_width: u32 = 1,
    viewport_height: u32 = 1,
};

pub const MetalGlobalElements = struct {
    shared_state_ready: bool = false,
    sampler_ready: bool = false,
};

pub const MetalRenderPipelines = struct {
    shadow: bool = false,
    quad: bool = false,
    path_rasterization: bool = false,
    path_sprite: bool = false,
    underline: bool = false,
    mono_sprites: bool = false,
    subpixel_sprites: bool = false,
    poly_sprites: bool = false,
};

pub const DrawReport = struct {
    frame_index: u64 = 0,
    command_count: usize = 0,
    clear_count: usize = 0,
    rect_count: usize = 0,
    text_count: usize = 0,
    skipped: bool = false,
    clear_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },
    viewport_width: u32 = 1,
    viewport_height: u32 = 1,
};

pub const GpuSpecs = struct {
    adapter_name: ?[]const u8 = null,
    supports_metal_rendering: bool = false,
    supports_layer_backing: bool = false,
    supports_present_wait: bool = false,
    supports_gpu_rendering: bool = false,
};

pub const MetalRenderer = struct {
    atlas: atlas.MetalAtlas = .{},
    devices: MetalRendererDevices = .{},
    resources: MetalResources = .{},
    globals: MetalGlobalElements = .{},
    pipelines: MetalRenderPipelines = .{},
    width: u32 = 1,
    height: u32 = 1,
    skip_draws: bool = false,
    drawable: bool = false,
    frame_index: u64 = 0,
    last_report: DrawReport = .{},
    last_clear_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },

    pub fn init(
        allocator: std.mem.Allocator,
        devices: MetalRendererDevices,
    ) !MetalRenderer {
        _ = allocator;
        var renderer = MetalRenderer{
            .devices = devices,
        };
        renderer.rebuildResources();
        renderer.rebuildPipelines();
        return renderer;
    }

    pub fn deinit(self: *MetalRenderer, allocator: std.mem.Allocator) void {
        self.atlas.deinit(allocator);
        self.* = .{};
    }

    pub fn spriteAtlas(self: *MetalRenderer) *atlas.MetalAtlas {
        return &self.atlas;
    }

    pub fn supportsGpuRendering(self: *const MetalRenderer) bool {
        return self.devices.supportsGpuRendering();
    }

    pub fn backendName(self: *const MetalRenderer) []const u8 {
        return if (self.supportsGpuRendering()) "metal" else "metal-pending";
    }

    pub fn gpuSpecs(self: *const MetalRenderer) GpuSpecs {
        return .{
            .adapter_name = self.devices.adapter_name,
            .supports_metal_rendering = self.supportsGpuRendering(),
            .supports_layer_backing = self.devices.supports_layer_backing,
            .supports_present_wait = self.devices.supports_present_wait,
            .supports_gpu_rendering = self.supportsGpuRendering(),
        };
    }

    pub fn markDrawable(self: *MetalRenderer) void {
        self.drawable = true;
        self.skip_draws = false;
    }

    pub fn resize(self: *MetalRenderer, width: u32, height: u32) !void {
        if (width == 0 or height == 0) return error.InvalidSize;
        self.width = width;
        self.height = height;
        self.rebuildResources();
        self.drawable = false;
    }

    pub fn handleDeviceLost(self: *MetalRenderer, devices: MetalRendererDevices) !void {
        self.devices = devices;
        self.atlas.handleDeviceLost();
        self.rebuildResources();
        self.rebuildPipelines();
        self.skip_draws = true;
        self.drawable = false;
    }

    pub fn draw(self: *MetalRenderer, scene_state: *const scene.Scene, clear_color: [4]f32) DrawReport {
        if (self.skip_draws) {
            self.skip_draws = false;
            self.last_report = .{
                .frame_index = self.frame_index,
                .skipped = true,
                .clear_color = clear_color,
                .viewport_width = self.resources.viewport_width,
                .viewport_height = self.resources.viewport_height,
            };
            return self.last_report;
        }

        var report = DrawReport{
            .frame_index = self.frame_index,
            .clear_color = clear_color,
            .viewport_width = self.resources.viewport_width,
            .viewport_height = self.resources.viewport_height,
        };

        for (scene_state.commands.items) |command| {
            report.command_count += 1;
            switch (command) {
                .clear => report.clear_count += 1,
                .fill_rect => report.rect_count += 1,
                .text => report.text_count += 1,
            }
        }

        self.frame_index += 1;
        self.drawable = true;
        self.last_clear_color = clear_color;
        self.last_report = report;
        return report;
    }

    fn rebuildResources(self: *MetalRenderer) void {
        const gpu_ready = self.supportsGpuRendering();
        self.resources = .{
            .drawable_surface_ready = gpu_ready,
            .command_queue_ready = gpu_ready,
            .texture_cache_ready = gpu_ready,
            .viewport_width = self.width,
            .viewport_height = self.height,
        };
        self.globals = .{
            .shared_state_ready = gpu_ready,
            .sampler_ready = gpu_ready,
        };
    }

    fn rebuildPipelines(self: *MetalRenderer) void {
        const gpu_ready = self.supportsGpuRendering();
        self.pipelines = .{
            .shadow = gpu_ready,
            .quad = gpu_ready,
            .path_rasterization = gpu_ready,
            .path_sprite = gpu_ready,
            .underline = gpu_ready,
            .mono_sprites = gpu_ready,
            .subpixel_sprites = gpu_ready,
            .poly_sprites = gpu_ready,
        };
    }
};

test "renderer reports gpu support and draw summaries" {
    var renderer = try MetalRenderer.init(std.testing.allocator, .{});
    defer renderer.deinit(std.testing.allocator);

    try std.testing.expect(renderer.supportsGpuRendering());
    try std.testing.expectEqualStrings("metal", renderer.backendName());

    var scene_state = scene.Scene{};
    defer scene_state.deinit(std.testing.allocator);
    try scene_state.appendClear(std.testing.allocator, style.Color.white);
    try scene_state.appendRect(std.testing.allocator, .{
        .x = 0,
        .y = 0,
        .width = 10,
        .height = 10,
        .color = style.Color.white,
    });

    const report = renderer.draw(&scene_state, .{ 1, 1, 1, 1 });
    try std.testing.expectEqual(@as(usize, 2), report.command_count);
    try std.testing.expectEqual(@as(usize, 1), report.clear_count);
    try std.testing.expectEqual(@as(usize, 1), report.rect_count);
}

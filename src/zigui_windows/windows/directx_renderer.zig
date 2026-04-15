const std = @import("std");
const scene = @import("../../zigui/scene.zig");
const atlas = @import("directx_atlas.zig");
const directx_devices = @import("directx_devices.zig");

pub const DirectXRendererDevices = directx_devices.RendererDeviceSnapshot;

pub const FontInfo = struct {
    gamma_ratios: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 },
    grayscale_enhanced_contrast: f32 = 1.0,
    subpixel_enhanced_contrast: f32 = 1.0,
};

pub const DirectComposition = struct {
    enabled: bool = true,
    swap_chain_bound: bool = false,
};

pub const DirectXResources = struct {
    swap_chain_present: bool = false,
    render_target_ready: bool = false,
    path_intermediate_ready: bool = false,
    path_intermediate_msaa_ready: bool = false,
    viewport_width: u32 = 1,
    viewport_height: u32 = 1,
};

pub const DirectXGlobalElements = struct {
    global_params_ready: bool = false,
    sampler_ready: bool = false,
};

pub const DirectXRenderPipelines = struct {
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
    feature_level: directx_devices.FeatureLevel = .unknown,
    supports_direct_composition: bool = false,
    supports_present_wait: bool = false,
    supports_gpu_rendering: bool = false,
};

pub const DirectXRenderer = struct {
    atlas: atlas.DirectXAtlas = .{},
    devices: DirectXRendererDevices = .{},
    resources: DirectXResources = .{},
    globals: DirectXGlobalElements = .{},
    pipelines: DirectXRenderPipelines = .{},
    direct_composition: ?DirectComposition = null,
    font_info: FontInfo = .{},
    width: u32 = 1,
    height: u32 = 1,
    skip_draws: bool = false,
    drawable: bool = false,
    frame_index: u64 = 0,
    last_report: DrawReport = .{},
    last_clear_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },

    pub fn init(
        allocator: std.mem.Allocator,
        devices: *const directx_devices.DirectXDevices,
        disable_direct_composition: bool,
    ) !DirectXRenderer {
        _ = allocator;
        var renderer = DirectXRenderer{
            .devices = devices.snapshot(),
            .direct_composition = if (disable_direct_composition)
                null
            else
                .{ .enabled = true, .swap_chain_bound = false },
        };
        renderer.rebuildResources();
        renderer.rebuildPipelines();
        return renderer;
    }

    pub fn deinit(self: *DirectXRenderer, allocator: std.mem.Allocator) void {
        self.atlas.deinit(allocator);
        self.* = .{};
    }

    pub fn spriteAtlas(self: *DirectXRenderer) *atlas.DirectXAtlas {
        return &self.atlas;
    }

    pub fn supportsGpuRendering(self: *const DirectXRenderer) bool {
        return self.devices.supportsGpuRendering();
    }

    pub fn backendName(self: *const DirectXRenderer) []const u8 {
        return if (self.supportsGpuRendering()) "d3d12" else "d3d12-pending";
    }

    pub fn gpuSpecs(self: *const DirectXRenderer) GpuSpecs {
        return .{
            .adapter_name = self.devices.adapter_name,
            .feature_level = self.devices.feature_level,
            .supports_direct_composition = self.direct_composition != null and
                self.direct_composition.?.enabled,
            .supports_present_wait = self.direct_composition != null and
                self.direct_composition.?.enabled,
            .supports_gpu_rendering = self.supportsGpuRendering(),
        };
    }

    pub fn markDrawable(self: *DirectXRenderer) void {
        self.drawable = true;
        self.skip_draws = false;
    }

    pub fn resize(self: *DirectXRenderer, width: u32, height: u32) !void {
        if (width == 0 or height == 0) return error.InvalidSize;
        self.width = width;
        self.height = height;
        self.rebuildResources();
        self.drawable = false;
    }

    pub fn handleDeviceLost(self: *DirectXRenderer, devices: *const directx_devices.DirectXDevices) !void {
        self.devices = devices.snapshot();
        self.atlas.handleDeviceLost();
        self.rebuildResources();
        self.rebuildPipelines();
        self.skip_draws = true;
        self.drawable = false;
    }

    pub fn draw(self: *DirectXRenderer, scene_state: *const scene.Scene, clear_color: [4]f32) DrawReport {
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

    fn rebuildResources(self: *DirectXRenderer) void {
        const gpu_ready = self.supportsGpuRendering();
        self.resources = .{
            .swap_chain_present = gpu_ready,
            .render_target_ready = gpu_ready,
            .path_intermediate_ready = gpu_ready,
            .path_intermediate_msaa_ready = gpu_ready,
            .viewport_width = self.width,
            .viewport_height = self.height,
        };
        self.globals = .{
            .global_params_ready = gpu_ready,
            .sampler_ready = gpu_ready,
        };
    }

    fn rebuildPipelines(self: *DirectXRenderer) void {
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

pub const DirectXRendererConfig = DirectXRenderer;

test "renderer reports pending gpu support by default" {
    const devices = directx_devices.DirectXDevices{};
    var renderer = try DirectXRenderer.init(std.testing.allocator, &devices, false);
    defer renderer.deinit(std.testing.allocator);

    try std.testing.expect(!renderer.supportsGpuRendering());
    try std.testing.expectEqualStrings("d3d12-pending", renderer.backendName());
    try std.testing.expect(!renderer.resources.swap_chain_present);
}

test "renderer tracks resize and draw summaries" {
    const style = @import("../../zigui/style.zig");
    const scene_mod = @import("../../zigui/scene.zig");

    var devices = directx_devices.DirectXDevices{};
    devices.feature_level = .feature_11_0;

    var renderer = try DirectXRenderer.init(std.testing.allocator, &devices, true);
    defer renderer.deinit(std.testing.allocator);

    try renderer.resize(1920, 1080);
    try std.testing.expectEqual(@as(u32, 1920), renderer.width);
    try std.testing.expectEqual(@as(u32, 1080), renderer.resources.viewport_height);

    var test_scene = scene_mod.Scene{};
    defer test_scene.deinit(std.testing.allocator);
    try test_scene.appendClear(std.testing.allocator, style.Color.black);
    try test_scene.appendRect(std.testing.allocator, .{
        .x = 10,
        .y = 12,
        .width = 30,
        .height = 40,
        .color = style.Color.white,
    });
    try test_scene.appendLabel(std.testing.allocator, 1, 2, "hello", .{}, style.Color.white);

    const report = renderer.draw(&test_scene, .{ 0.25, 0.5, 0.75, 1.0 });
    try std.testing.expectEqual(@as(usize, 3), report.command_count);
    try std.testing.expectEqual(@as(usize, 1), report.clear_count);
    try std.testing.expectEqual(@as(usize, 1), report.rect_count);
    try std.testing.expectEqual(@as(usize, 1), report.text_count);
    try std.testing.expect(!report.skipped);
}

test "renderer marks the first frame after device loss as skipped" {
    var devices = directx_devices.DirectXDevices{};
    devices.feature_level = .feature_11_1;

    var renderer = try DirectXRenderer.init(std.testing.allocator, &devices, false);
    defer renderer.deinit(std.testing.allocator);

    try renderer.handleDeviceLost(&devices);
    var test_scene = scene.Scene{};
    defer test_scene.deinit(std.testing.allocator);
    const report = renderer.draw(&test_scene, .{ 0.0, 0.0, 0.0, 1.0 });
    try std.testing.expect(report.skipped);
}

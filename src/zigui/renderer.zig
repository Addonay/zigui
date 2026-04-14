pub const Backend = enum {
    metal,
    vulkan,
    d3d12,
    opengl,
};

pub const RendererConfig = struct {
    preferred_backend: ?Backend = null,
    enable_vsync: bool = true,
    enable_msaa: bool = true,
};

pub const FrameStats = struct {
    frame_index: u64 = 0,
    cpu_ms: f32 = 0,
    gpu_ms: f32 = 0,
};

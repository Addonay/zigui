pub const DirectXRendererConfig = struct {
    enabled: bool = false,
    backend_name: []const u8 = "d3d12-pending",
    uses_swap_chain: bool = false,
    supports_present_wait: bool = false,
};

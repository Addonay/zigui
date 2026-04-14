const std = @import("std");
const zigui = @import("zigui");

pub fn main(init: std.process.Init) !void {
    _ = init;
    var platform = zigui.platform.linux.LinuxPlatform.init(std.heap.c_allocator);
    defer platform.deinit();
    const diagnostics = platform.diagnostics();
    const services = platform.services();

    std.debug.print(
        \\zigui Linux platform probe
        \\default native backend: {s}
        \\selected runtime: {s}
        \\window system: {s}
        \\clipboard: {}
        \\ime: {}
        \\note: {s}
        \\
    , .{
        @tagName(zigui.platform.defaultBackendKind()),
        diagnostics.backend_name,
        diagnostics.window_system,
        services.supports_clipboard,
        services.supports_ime,
        diagnostics.note,
    });
}

test "main imports zigui root module" {
    try std.testing.expect(@hasDecl(zigui, "Application"));
}

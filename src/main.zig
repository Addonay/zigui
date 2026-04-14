const builtin = @import("builtin");
const std = @import("std");
const zigui = @import("zigui");

pub fn main(init: std.process.Init) !void {
    _ = init;
    switch (builtin.os.tag) {
        .linux, .freebsd => {
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
        },
        else => {
            std.debug.print(
                \\zigui platform probe
                \\default native backend: {s}
                \\
            , .{
                @tagName(zigui.platform.defaultBackendKind()),
            });
        },
    }
}

test "main imports zigui root module" {
    try std.testing.expect(@hasDecl(zigui, "Application"));
}

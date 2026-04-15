pub const client = @import("wayland/client.zig");
pub const clipboard = @import("wayland/clipboard.zig");
pub const cursor = @import("wayland/cursor.zig");
pub const display = @import("wayland/display.zig");
pub const serial = @import("wayland/serial.zig");
pub const window = @import("wayland/window.zig");
pub const WaylandClient = client.WaylandClient;

test "wayland root exports the expected backend slices" {
    const std = @import("std");

    try std.testing.expect(@hasDecl(@This(), "client"));
    try std.testing.expect(@hasDecl(@This(), "clipboard"));
    try std.testing.expect(@hasDecl(@This(), "cursor"));
    try std.testing.expect(@hasDecl(@This(), "display"));
    try std.testing.expect(@hasDecl(@This(), "serial"));
    try std.testing.expect(@hasDecl(@This(), "window"));
    try std.testing.expect(@hasDecl(@This(), "WaylandClient"));
}

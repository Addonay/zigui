pub const client = @import("x11/client.zig");
pub const clipboard = @import("x11/clipboard.zig");
pub const display = @import("x11/display.zig");
pub const event = @import("x11/event.zig");
pub const xim_handler = @import("x11/xim_handler.zig");
pub const window = @import("x11/window.zig");

test "x11 root exports the expected backend slices" {
    const std = @import("std");

    try std.testing.expect(@hasDecl(@This(), "client"));
    try std.testing.expect(@hasDecl(@This(), "clipboard"));
    try std.testing.expect(@hasDecl(@This(), "display"));
    try std.testing.expect(@hasDecl(@This(), "event"));
    try std.testing.expect(@hasDecl(@This(), "window"));
    try std.testing.expect(@hasDecl(@This(), "xim_handler"));
    try std.testing.expect(@hasDecl(@This(), "X11Backend"));
    try std.testing.expect(@hasDecl(@This(), "createRuntime"));
}

pub const X11Backend = client.X11Backend;
pub const createRuntime = client.createRuntime;

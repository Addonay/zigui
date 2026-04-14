const std = @import("std");
const zigui = @import("zigui");

pub fn main() !void {
    var app = zigui.Application.init(std.heap.c_allocator, .{
        .name = "hello-world",
        .window = .{
            .title = "Hello World",
            .width = 960,
            .height = 640,
        },
    });
    defer app.deinit();

    try app.run();
}

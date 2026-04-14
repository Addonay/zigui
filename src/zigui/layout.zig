const std = @import("std");
const style = @import("style.zig");

pub const Axis = enum {
    horizontal,
    vertical,
};

pub const Size = struct {
    width: f32,
    height: f32,
};

pub const BoxConstraints = struct {
    min_width: f32 = 0,
    max_width: f32 = std.math.inf(f32),
    min_height: f32 = 0,
    max_height: f32 = std.math.inf(f32),
};

pub const LayoutNode = struct {
    axis: Axis = .vertical,
    gap: f32 = 0,
    flex: style.FlexStyle = .{},
};

test "constraints allow infinite maximums by default" {
    const constraints = BoxConstraints{};
    try std.testing.expect(std.math.isInf(constraints.max_width));
    try std.testing.expect(std.math.isInf(constraints.max_height));
}

const std = @import("std");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const white = Color.rgb(0xff, 0xff, 0xff);
    pub const black = Color.rgb(0x00, 0x00, 0x00);

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = 255 };
    }

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }
};

pub const Length = union(enum) {
    auto,
    px: f32,
    percent: f32,

    pub fn toPixels(self: Length, basis: f32) ?f32 {
        return switch (self) {
            .auto => null,
            .px => |value| value,
            .percent => |value| basis * (value / 100.0),
        };
    }
};

pub const FlexStyle = struct {
    grow: f32 = 0.0,
    shrink: f32 = 1.0,
    basis: Length = .auto,
};

pub const Spacing = struct {
    top: f32 = 0,
    right: f32 = 0,
    bottom: f32 = 0,
    left: f32 = 0,

    pub fn all(value: f32) Spacing {
        return .{
            .top = value,
            .right = value,
            .bottom = value,
            .left = value,
        };
    }
};

pub const Corners = struct {
    top_left: f32 = 0,
    top_right: f32 = 0,
    bottom_right: f32 = 0,
    bottom_left: f32 = 0,

    pub fn all(value: f32) Corners {
        return .{
            .top_left = value,
            .top_right = value,
            .bottom_right = value,
            .bottom_left = value,
        };
    }
};

test "percentage lengths resolve against a basis" {
    try std.testing.expectEqual(@as(?f32, 50), (Length{ .percent = 25 }).toPixels(200));
}

const std = @import("std");

pub const denominator: u32 = 120;

pub const FractionalScale = struct {
    numerator: u32 = denominator,

    pub fn init(numerator: u32) FractionalScale {
        return .{ .numerator = @max(numerator, denominator) };
    }

    pub fn isFractional(self: FractionalScale) bool {
        return (self.numerator % denominator) != 0;
    }

    pub fn integerScale(self: FractionalScale) i32 {
        return @max(1, @as(i32, @intCast(self.numerator / denominator)));
    }

    pub fn cursorScale(self: FractionalScale) i32 {
        return @max(1, @as(i32, @intCast((self.numerator + (denominator - 1)) / denominator)));
    }

    pub fn scaleDimension(self: FractionalScale, logical_size: u32) u32 {
        const scaled = (@as(u64, logical_size) * self.numerator) + (denominator / 2);
        return @max(1, @as(u32, @intCast(scaled / denominator)));
    }
};

test "fractional scale rounds buffer dimensions half away from zero" {
    const scale = FractionalScale.init(180);
    try std.testing.expect(scale.isFractional());
    try std.testing.expectEqual(@as(u32, 150), scale.scaleDimension(100));
    try std.testing.expectEqual(@as(i32, 2), scale.cursorScale());
}

test "integer multiples keep integer buffer scale" {
    const scale = FractionalScale.init(240);
    try std.testing.expect(!scale.isFractional());
    try std.testing.expectEqual(@as(i32, 2), scale.integerScale());
    try std.testing.expectEqual(@as(u32, 200), scale.scaleDimension(100));
}

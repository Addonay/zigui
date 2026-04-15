const std = @import("std");

pub const Layer = enum {
    background,
    bottom,
    top,
    overlay,
};

pub const Anchor = struct {
    top: bool = false,
    bottom: bool = false,
    left: bool = false,
    right: bool = false,

    pub fn bits(self: Anchor) u32 {
        var value: u32 = 0;
        if (self.top) value |= 1 << 0;
        if (self.bottom) value |= 1 << 1;
        if (self.left) value |= 1 << 2;
        if (self.right) value |= 1 << 3;
        return value;
    }

    pub fn fromBitsTruncated(value: u32) Anchor {
        return .{
            .top = (value & (1 << 0)) != 0,
            .bottom = (value & (1 << 1)) != 0,
            .left = (value & (1 << 2)) != 0,
            .right = (value & (1 << 3)) != 0,
        };
    }

    pub fn contains(self: Anchor, other: Anchor) bool {
        return (self.bits() & other.bits()) == other.bits();
    }

    pub fn merge(self: Anchor, other: Anchor) Anchor {
        return fromBitsTruncated(self.bits() | other.bits());
    }
};

pub const KeyboardInteractivity = enum {
    none,
    exclusive,
    on_demand,
};

pub const Margin = struct {
    top: f32 = 0,
    right: f32 = 0,
    bottom: f32 = 0,
    left: f32 = 0,
};

pub const LayerShellOptions = struct {
    namespace: []const u8 = "",
    layer: Layer = .overlay,
    anchor: Anchor = .{},
    exclusive_zone: ?f32 = null,
    exclusive_edge: ?Anchor = null,
    margin: ?Margin = null,
    keyboard_interactivity: KeyboardInteractivity = .on_demand,
};

pub const LayerShellNotSupportedError = error{LayerShellNotSupported};

test "anchor bits round-trip through the helper API" {
    const anchor = Anchor{
        .top = true,
        .left = true,
    };

    try std.testing.expectEqual(@as(u32, 0b0101), anchor.bits());
    try std.testing.expect(anchor.contains(Anchor{ .top = true }));
    try std.testing.expectEqual(anchor, Anchor.fromBitsTruncated(0b0101));
}

test "layer shell options default to overlay and on-demand keyboard focus" {
    const options = LayerShellOptions{};

    try std.testing.expectEqual(Layer.overlay, options.layer);
    try std.testing.expectEqual(KeyboardInteractivity.on_demand, options.keyboard_interactivity);
    try std.testing.expectEqualStrings("", options.namespace);
    try std.testing.expectEqual(@as(?f32, null), options.exclusive_zone);
    try std.testing.expectEqual(@as(?Anchor, null), options.exclusive_edge);
    try std.testing.expectEqual(@as(?Margin, null), options.margin);
}

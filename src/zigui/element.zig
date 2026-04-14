const std = @import("std");

pub const Kind = enum {
    div,
    text,
    stack,
    row,
    button,
    input,
    canvas,
    custom,
};

pub const Element = struct {
    kind: Kind,
    label: []const u8 = "",
    children: []const Element = &.{},
};

pub fn IntoElement(comptime T: type) type {
    return struct {
        pub fn intoElement(value: T) Element {
            return T.intoElement(value);
        }
    };
}

pub fn text(label: []const u8) Element {
    return .{
        .kind = .text,
        .label = label,
    };
}

pub fn div(children: []const Element) Element {
    return .{
        .kind = .div,
        .children = children,
    };
}

test "text element keeps label" {
    const el = text("hello");
    try std.testing.expectEqualStrings("hello", el.label);
}

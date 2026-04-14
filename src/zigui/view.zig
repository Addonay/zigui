const element = @import("element.zig");

pub const ViewId = enum(u64) {
    _,
};

pub fn Render(comptime T: type) type {
    return struct {
        pub const View = T;

        pub fn render(self: *T) element.Element {
            return T.render(self);
        }
    };
}

pub const ViewSpec = struct {
    name: []const u8,
    build: *const fn () element.Element,
};

const std = @import("std");
const style = @import("style.zig");

pub const Theme = struct {
    background: style.Color = style.Color.rgb(0x11, 0x14, 0x1a),
    surface: style.Color = style.Color.rgb(0x19, 0x1e, 0x26),
    text: style.Color = style.Color.rgb(0xf1, 0xf5, 0xf9),
    muted_text: style.Color = style.Color.rgb(0x94, 0xa3, 0xb8),
    accent: style.Color = style.Color.rgb(0x3b, 0x82, 0xf6),
    corner_radius: f32 = 12,
    spacing: f32 = 8,
    font_size: f32 = 14,

    pub fn refine(self: *Theme, refinement: ThemeRefinement) void {
        if (refinement.background) |value| self.background = value;
        if (refinement.surface) |value| self.surface = value;
        if (refinement.text) |value| self.text = value;
        if (refinement.muted_text) |value| self.muted_text = value;
        if (refinement.accent) |value| self.accent = value;
        if (refinement.corner_radius) |value| self.corner_radius = value;
        if (refinement.spacing) |value| self.spacing = value;
        if (refinement.font_size) |value| self.font_size = value;
    }

    pub fn refined(self: Theme, refinement: ThemeRefinement) Theme {
        var next = self;
        next.refine(refinement);
        return next;
    }
};

pub const ThemeRefinement = struct {
    background: ?style.Color = null,
    surface: ?style.Color = null,
    text: ?style.Color = null,
    muted_text: ?style.Color = null,
    accent: ?style.Color = null,
    corner_radius: ?f32 = null,
    spacing: ?f32 = null,
    font_size: ?f32 = null,

    pub fn isEmpty(self: ThemeRefinement) bool {
        return self.background == null and
            self.surface == null and
            self.text == null and
            self.muted_text == null and
            self.accent == null and
            self.corner_radius == null and
            self.spacing == null and
            self.font_size == null;
    }

    pub fn refine(self: *ThemeRefinement, other: ThemeRefinement) void {
        if (other.background) |value| self.background = value;
        if (other.surface) |value| self.surface = value;
        if (other.text) |value| self.text = value;
        if (other.muted_text) |value| self.muted_text = value;
        if (other.accent) |value| self.accent = value;
        if (other.corner_radius) |value| self.corner_radius = value;
        if (other.spacing) |value| self.spacing = value;
        if (other.font_size) |value| self.font_size = value;
    }
};

pub const ThemeSlot = enum(usize) {
    base = 0,
    _,
};

pub const ThemeCascade = struct {
    base: ThemeRefinement = .{},
    layers: std.ArrayListUnmanaged(?ThemeRefinement) = .empty,

    pub fn deinit(self: *ThemeCascade, allocator: std.mem.Allocator) void {
        self.layers.deinit(allocator);
    }

    pub fn reserve(self: *ThemeCascade, allocator: std.mem.Allocator) !ThemeSlot {
        try self.layers.append(allocator, null);
        return @enumFromInt(self.layers.items.len);
    }

    pub fn set(self: *ThemeCascade, slot: ThemeSlot, refinement: ?ThemeRefinement) void {
        const index = @intFromEnum(slot);
        if (index == 0) {
            self.base = refinement orelse .{};
            return;
        }
        self.layers.items[index - 1] = refinement;
    }

    pub fn merged(self: *const ThemeCascade) ThemeRefinement {
        var combined = self.base;
        for (self.layers.items) |maybe_refinement| {
            if (maybe_refinement) |refinement| combined.refine(refinement);
        }
        return combined;
    }
};

test "theme cascade merges later refinements over the base" {
    var cascade = ThemeCascade{};
    defer cascade.deinit(std.testing.allocator);

    cascade.base = .{ .font_size = 14 };
    const slot = try cascade.reserve(std.testing.allocator);
    cascade.set(slot, .{ .font_size = 18 });

    const merged = cascade.merged();
    try std.testing.expectEqual(@as(?f32, 18), merged.font_size);
}

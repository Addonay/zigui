const std = @import("std");
const common = @import("../../zigui/common.zig");

pub const PasteboardKind = enum {
    general,
    find,
};

pub const Pasteboard = struct {
    kind: PasteboardKind,
    text: ?[]u8 = null,
    metadata: ?[]u8 = null,
    text_hash: ?u64 = null,
    paths: std.ArrayListUnmanaged([]u8) = .empty,
    image_bytes: std.ArrayListUnmanaged(u8) = .empty,

    pub fn general() Pasteboard {
        return .{ .kind = .general };
    }

    pub fn find() Pasteboard {
        return .{ .kind = .find };
    }

    pub fn deinit(self: *Pasteboard, allocator: std.mem.Allocator) void {
        self.clear(allocator);
        self.* = .{
            .kind = self.kind,
        };
    }

    pub fn clear(self: *Pasteboard, allocator: std.mem.Allocator) void {
        if (self.text) |text| allocator.free(text);
        if (self.metadata) |metadata| allocator.free(metadata);
        for (self.paths.items) |path| allocator.free(path);
        self.paths.deinit(allocator);
        self.image_bytes.deinit(allocator);
        self.paths = .empty;
        self.image_bytes = .empty;
        self.text = null;
        self.metadata = null;
        self.text_hash = null;
    }

    pub fn matchesClipboardKind(self: *const Pasteboard, kind: common.ClipboardKind) bool {
        return switch (self.kind) {
            .general => kind == .clipboard,
            .find => kind == .primary,
        };
    }

    pub fn hasData(self: *const Pasteboard) bool {
        return self.text != null or self.metadata != null or self.paths.items.len != 0 or self.image_bytes.items.len != 0;
    }

    pub fn snapshot(self: *const Pasteboard) common.ClipboardSnapshot {
        return .{
            .available = self.hasData(),
            .has_text = self.text != null,
            .mime_type = if (self.text != null)
                "text/plain;charset=utf-8"
            else if (self.paths.items.len != 0)
                "text/uri-list"
            else if (self.image_bytes.items.len != 0)
                "image/png"
            else
                null,
        };
    }

    pub fn writeTextToClipboard(
        self: *Pasteboard,
        allocator: std.mem.Allocator,
        kind: common.ClipboardKind,
        text: []const u8,
    ) !void {
        if (!self.matchesClipboardKind(kind)) return error.NoClipboardSupport;
        self.clear(allocator);
        self.text = try allocator.dupe(u8, text);
        self.text_hash = textHash(text);
    }

    pub fn readTextFromClipboardAlloc(
        self: *Pasteboard,
        allocator: std.mem.Allocator,
        kind: common.ClipboardKind,
        out_allocator: std.mem.Allocator,
    ) ![]u8 {
        if (!self.matchesClipboardKind(kind)) return error.NoClipboardSupport;
        const text = self.text orelse return error.NoClipboardText;
        _ = allocator;
        return try out_allocator.dupe(u8, text);
    }

    pub fn writePaths(
        self: *Pasteboard,
        allocator: std.mem.Allocator,
        kind: common.ClipboardKind,
        paths: []const []const u8,
    ) !void {
        if (!self.matchesClipboardKind(kind)) return error.NoClipboardSupport;
        var next_paths: std.ArrayListUnmanaged([]u8) = .empty;
        errdefer {
            for (next_paths.items) |path| allocator.free(path);
            next_paths.deinit(allocator);
        }

        try next_paths.ensureTotalCapacity(allocator, paths.len);
        for (paths) |path| {
            try next_paths.append(allocator, try allocator.dupe(u8, path));
        }

        self.clear(allocator);
        self.paths = next_paths;
    }

    pub fn readPathsAlloc(
        self: *Pasteboard,
        allocator: std.mem.Allocator,
        kind: common.ClipboardKind,
    ) !?common.PathList {
        if (!self.matchesClipboardKind(kind)) return error.NoClipboardSupport;
        if (self.paths.items.len == 0) return null;

        var list = common.PathList{
            .paths = try allocator.alloc([]u8, self.paths.items.len),
        };
        errdefer list.deinit(allocator);

        for (self.paths.items, 0..) |path, index| {
            list.paths[index] = try allocator.dupe(u8, path);
        }

        return list;
    }
};

fn textHash(text: []const u8) u64 {
    return std.hash.Wyhash.hash(0, text);
}

test "pasteboard tracks general and find boards separately" {
    var general = Pasteboard.general();
    defer general.deinit(std.testing.allocator);

    var find = Pasteboard.find();
    defer find.deinit(std.testing.allocator);

    try general.writeTextToClipboard(std.testing.allocator, .clipboard, "hello");
    try find.writeTextToClipboard(std.testing.allocator, .primary, "search");

    const general_text = try general.readTextFromClipboardAlloc(std.testing.allocator, .clipboard, std.testing.allocator);
    defer std.testing.allocator.free(general_text);
    const find_text = try find.readTextFromClipboardAlloc(std.testing.allocator, .primary, std.testing.allocator);
    defer std.testing.allocator.free(find_text);

    try std.testing.expectEqualStrings("hello", general_text);
    try std.testing.expectEqualStrings("search", find_text);
    try std.testing.expect(!general.matchesClipboardKind(.primary));
}

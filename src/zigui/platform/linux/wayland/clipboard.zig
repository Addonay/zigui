const std = @import("std");

pub const text_mime_types = [_][]const u8{
    "text/plain;charset=utf-8",
    "text/plain",
    "UTF8_STRING",
    "STRING",
};

pub const ClipboardOffer = struct {
    mime_types: std.ArrayListUnmanaged([]u8) = .empty,
    source_actions: u32 = 0,
    selected_action: u32 = 0,

    pub fn addMimeType(self: *ClipboardOffer, allocator: std.mem.Allocator, mime_type: []const u8) !void {
        for (self.mime_types.items) |existing| {
            if (std.mem.eql(u8, existing, mime_type)) return;
        }
        try self.mime_types.append(allocator, try allocator.dupe(u8, mime_type));
    }

    pub fn preferredTextMime(self: *const ClipboardOffer) ?[]const u8 {
        for (text_mime_types) |candidate| {
            for (self.mime_types.items) |existing| {
                if (std.mem.eql(u8, existing, candidate)) return existing;
            }
        }
        return null;
    }

    pub fn hasText(self: *const ClipboardOffer) bool {
        return self.preferredTextMime() != null;
    }

    pub fn deinit(self: *ClipboardOffer, allocator: std.mem.Allocator) void {
        for (self.mime_types.items) |mime_type| allocator.free(mime_type);
        self.mime_types.deinit(allocator);
        self.* = .{};
    }
};

pub const DragState = struct {
    offer_id: ?usize = null,
    surface_id: ?usize = null,
    preferred_text_mime: []const u8 = text_mime_types[0],
    has_text: bool = false,
    active: bool = false,
    dropped: bool = false,
    serial: u32 = 0,
    x: f64 = 0,
    y: f64 = 0,

    pub fn noteEnter(
        self: *DragState,
        serial_value: u32,
        surface_id: ?usize,
        x: f64,
        y: f64,
        offer_id: ?usize,
        offer: ?*const ClipboardOffer,
    ) void {
        self.* = .{
            .offer_id = offer_id,
            .surface_id = surface_id,
            .serial = serial_value,
            .x = x,
            .y = y,
            .active = true,
        };
        if (offer) |resolved| {
            if (resolved.preferredTextMime()) |mime_type| {
                self.has_text = true;
                self.preferred_text_mime = mime_type;
            }
        }
    }

    pub fn noteMotion(self: *DragState, x: f64, y: f64) void {
        self.x = x;
        self.y = y;
    }

    pub fn noteDrop(self: *DragState) void {
        self.dropped = true;
    }

    pub fn noteLeave(self: *DragState) void {
        self.* = .{};
    }
};

pub const ClipboardState = struct {
    has_primary_selection: bool = false,
    has_clipboard: bool = false,
    preferred_text_mime: []const u8 = text_mime_types[0],
    selection_offer: ?usize = null,
    selection_has_text: bool = false,
    primary_selection_offer: ?usize = null,
    primary_selection_has_text: bool = false,
    primary_preferred_text_mime: []const u8 = text_mime_types[0],
    drag: DragState = .{},

    pub fn noteSelection(self: *ClipboardState, offer_id: ?usize, offer: ?*const ClipboardOffer) void {
        self.selection_offer = offer_id;
        self.selection_has_text = false;
        if (offer) |resolved| {
            if (resolved.preferredTextMime()) |mime_type| {
                self.selection_has_text = true;
                self.preferred_text_mime = mime_type;
            }
        }
    }

    pub fn notePrimarySelection(self: *ClipboardState, offer_id: ?usize, offer: ?*const ClipboardOffer) void {
        self.primary_selection_offer = offer_id;
        self.primary_selection_has_text = false;
        if (offer) |resolved| {
            if (resolved.preferredTextMime()) |mime_type| {
                self.primary_selection_has_text = true;
                self.primary_preferred_text_mime = mime_type;
            }
        }
    }
};

test "clipboard offer selects preferred text mime" {
    var offer = ClipboardOffer{};
    defer offer.deinit(std.testing.allocator);
    try offer.addMimeType(std.testing.allocator, "application/octet-stream");
    try offer.addMimeType(std.testing.allocator, "text/plain");

    var clipboard = ClipboardState{};
    clipboard.noteSelection(42, &offer);
    try std.testing.expect(clipboard.selection_has_text);
    try std.testing.expectEqualStrings("text/plain", clipboard.preferred_text_mime);
}

test "clipboard state tracks primary selection independently" {
    var offer = ClipboardOffer{};
    defer offer.deinit(std.testing.allocator);
    try offer.addMimeType(std.testing.allocator, "text/plain;charset=utf-8");

    var state = ClipboardState{ .has_primary_selection = true };
    state.notePrimarySelection(7, &offer);
    try std.testing.expect(state.primary_selection_has_text);
    try std.testing.expectEqual(@as(?usize, 7), state.primary_selection_offer);
    try std.testing.expectEqualStrings("text/plain;charset=utf-8", state.primary_preferred_text_mime);
}

test "drag state records offer and motion" {
    var offer = ClipboardOffer{};
    defer offer.deinit(std.testing.allocator);
    try offer.addMimeType(std.testing.allocator, "text/plain");

    var drag = DragState{};
    drag.noteEnter(11, 55, 10.5, 18.25, 9, &offer);
    try std.testing.expect(drag.active);
    try std.testing.expect(drag.has_text);
    try std.testing.expectEqual(@as(?usize, 9), drag.offer_id);

    drag.noteMotion(20.0, 30.0);
    try std.testing.expectEqual(@as(f64, 20.0), drag.x);
    try std.testing.expectEqual(@as(f64, 30.0), drag.y);

    drag.noteDrop();
    try std.testing.expect(drag.dropped);

    drag.noteLeave();
    try std.testing.expect(!drag.active);
    try std.testing.expectEqual(@as(?usize, null), drag.offer_id);
}

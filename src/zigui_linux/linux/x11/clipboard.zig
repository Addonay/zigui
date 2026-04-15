const std = @import("std");

const max_clipboard_bytes = 4096;

pub const ClipboardKind = enum {
    primary,
    clipboard,
};

const TextSelection = struct {
    len: usize = 0,
    buffer: [max_clipboard_bytes]u8 = undefined,

    pub fn write(self: *TextSelection, text: []const u8) void {
        self.len = @min(text.len, self.buffer.len);
        @memcpy(self.buffer[0..self.len], text[0..self.len]);
    }

    pub fn read(self: *const TextSelection) []const u8 {
        return self.buffer[0..self.len];
    }

    pub fn isEmpty(self: *const TextSelection) bool {
        return self.len == 0;
    }
};

pub const ClipboardState = struct {
    has_primary_selection: bool = true,
    has_clipboard: bool = true,
    primary_atom_name: []const u8 = "PRIMARY",
    clipboard_atom_name: []const u8 = "CLIPBOARD",
    primary: TextSelection = .{},
    clipboard: TextSelection = .{},

    pub fn write(self: *ClipboardState, kind: ClipboardKind, text: []const u8) void {
        switch (kind) {
            .primary => self.primary.write(text),
            .clipboard => self.clipboard.write(text),
        }
    }

    pub fn read(self: *const ClipboardState, kind: ClipboardKind) []const u8 {
        return switch (kind) {
            .primary => self.primary.read(),
            .clipboard => self.clipboard.read(),
        };
    }

    pub fn hasData(self: *const ClipboardState, kind: ClipboardKind) bool {
        return switch (kind) {
            .primary => !self.primary.isEmpty(),
            .clipboard => !self.clipboard.isEmpty(),
        };
    }
};

test "x11 clipboard stores primary and clipboard data independently" {
    var state = ClipboardState{};
    state.write(.primary, "alpha");
    state.write(.clipboard, "beta");

    try std.testing.expectEqualStrings("alpha", state.read(.primary));
    try std.testing.expectEqualStrings("beta", state.read(.clipboard));
    try std.testing.expect(state.hasData(.primary));
    try std.testing.expect(state.hasData(.clipboard));
}

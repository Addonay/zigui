const std = @import("std");
const common = @import("../../zigui/common.zig");

pub const KeyRepeatConfig = common.KeyRepeatConfig;
pub const ModifierMask = common.ModifierMask;
pub const KeyboardLayout = common.KeyboardLayout;
pub const KeyboardInfo = common.KeyboardInfo;

pub const MacKeyboardLayout = struct {
    id: []const u8 = "com.apple.keylayout.US",
    name: []const u8 = "U.S.",

    pub fn new() MacKeyboardLayout {
        return .{};
    }
};

pub const KeyEquivalent = struct {
    from: u21,
    to: u21,
};

const qwertz_equivalents = [_]KeyEquivalent{
    .{ .from = '"', .to = '`' },
    .{ .from = '#', .to = '§' },
    .{ .from = '&', .to = '/' },
    .{ .from = '(', .to = ')' },
    .{ .from = ')', .to = '=' },
    .{ .from = '*', .to = '(' },
    .{ .from = '/', .to = 'ß' },
    .{ .from = ':', .to = 'Ü' },
    .{ .from = ';', .to = 'ü' },
    .{ .from = '<', .to = ';' },
    .{ .from = '=', .to = '*' },
    .{ .from = '>', .to = ':' },
    .{ .from = '@', .to = '"' },
    .{ .from = '[', .to = 'ö' },
    .{ .from = '\'', .to = '´' },
    .{ .from = '\\', .to = '#' },
    .{ .from = ']', .to = 'ä' },
    .{ .from = '^', .to = '&' },
    .{ .from = '`', .to = '<' },
    .{ .from = '{', .to = 'Ö' },
    .{ .from = '|', .to = '\'' },
    .{ .from = '}', .to = 'Ä' },
    .{ .from = '~', .to = '>' },
};

const azerty_equivalents = [_]KeyEquivalent{
    .{ .from = '!', .to = '1' },
    .{ .from = '"', .to = '%' },
    .{ .from = '#', .to = '3' },
    .{ .from = '$', .to = '4' },
    .{ .from = '%', .to = '5' },
    .{ .from = '&', .to = '7' },
    .{ .from = '(', .to = '9' },
    .{ .from = ')', .to = '0' },
    .{ .from = '*', .to = '8' },
    .{ .from = '.', .to = ';' },
    .{ .from = '/', .to = ':' },
    .{ .from = '0', .to = 'à' },
    .{ .from = '1', .to = '&' },
    .{ .from = '2', .to = 'é' },
    .{ .from = '3', .to = '"' },
    .{ .from = '4', .to = '\'' },
    .{ .from = '5', .to = '(' },
    .{ .from = '6', .to = '§' },
    .{ .from = '7', .to = 'è' },
    .{ .from = '8', .to = '!' },
    .{ .from = '9', .to = 'ç' },
    .{ .from = ':', .to = '°' },
    .{ .from = ';', .to = ')' },
    .{ .from = '<', .to = '.' },
    .{ .from = '>', .to = '/' },
    .{ .from = '@', .to = '2' },
    .{ .from = '[', .to = '^' },
    .{ .from = '\'', .to = 'ù' },
    .{ .from = '\\', .to = '`' },
    .{ .from = ']', .to = '$' },
    .{ .from = '^', .to = '6' },
    .{ .from = '`', .to = '<' },
    .{ .from = '{', .to = '¨' },
    .{ .from = '|', .to = '£' },
    .{ .from = '}', .to = '*' },
    .{ .from = '~', .to = '>' },
};

pub const MacKeyboardMapper = struct {
    key_equivalents: ?[]const KeyEquivalent = null,

    pub fn new(layout_id: []const u8) MacKeyboardMapper {
        return .{
            .key_equivalents = layoutKeyEquivalents(layout_id),
        };
    }

    pub fn mapKeyEquivalentChar(self: *const MacKeyboardMapper, ch: u21, use_key_equivalents: bool) u21 {
        if (!use_key_equivalents) return ch;
        if (self.key_equivalents) |key_equivalents| {
            for (key_equivalents) |equivalent| {
                if (equivalent.from == ch) return equivalent.to;
            }
        }
        return ch;
    }

    pub fn getKeyEquivalents(self: *const MacKeyboardMapper) ?[]const KeyEquivalent {
        return self.key_equivalents;
    }
};

pub const KeyboardState = struct {
    repeat: KeyRepeatConfig = .{},
    uses_text_services_framework: bool = true,
    active_modifiers: ModifierMask = .{},
    layout: KeyboardLayout = .apple,

    pub fn snapshot(self: KeyboardState) KeyboardInfo {
        return .{
            .layout = self.layout,
            .repeat = self.repeat,
            .modifiers = self.active_modifiers,
            .compose_enabled = self.uses_text_services_framework,
        };
    }
};

pub const Keyboard = KeyboardState;
pub const MacKeyboardState = KeyboardState;

fn layoutKeyEquivalents(layout_id: []const u8) ?[]const KeyEquivalent {
    if (std.mem.eql(u8, layout_id, "com.apple.keylayout.ABC-QWERTZ")) return &qwertz_equivalents;
    if (std.mem.eql(u8, layout_id, "com.apple.keylayout.ABC-AZERTY")) return &azerty_equivalents;
    return null;
}

test "keyboard snapshot reflects the apple layout" {
    const info = (KeyboardState{}).snapshot();
    try std.testing.expectEqual(KeyboardLayout.apple, info.layout);
    try std.testing.expect(info.compose_enabled);
}

test "keyboard mapper remaps known equivalent characters" {
    const mapper = MacKeyboardMapper.new("com.apple.keylayout.ABC-QWERTZ");
    try std.testing.expectEqual(@as(u21, ':'), mapper.mapKeyEquivalentChar('>', true));
    try std.testing.expectEqual(@as(u21, '>'), mapper.mapKeyEquivalentChar('>', false));
}

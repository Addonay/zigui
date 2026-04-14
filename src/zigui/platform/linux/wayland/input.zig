const std = @import("std");
const common = @import("../../common.zig");
const linux_keyboard = @import("../keyboard.zig");
const c = @import("c.zig").c;
const serial = @import("serial.zig");

pub const PointerState = struct {
    focused_surface: ?*c.wl_surface = null,
    entered: bool = false,
    serials: serial.SerialTracker = .{},
    cursor: common.Cursor = .arrow,
    surface_x: f64 = 0,
    surface_y: f64 = 0,
    last_button: u32 = 0,
    last_button_state: u32 = 0,
    last_button_time: u32 = 0,
    vertical_scroll: f64 = 0,
    horizontal_scroll: f64 = 0,
    axis_source: ?u32 = null,

    pub fn noteEnter(self: *PointerState, enter_serial: u32, surface: ?*c.wl_surface, x: f64, y: f64) void {
        self.entered = true;
        self.focused_surface = surface;
        self.surface_x = x;
        self.surface_y = y;
        self.serials.record(.pointer_enter, enter_serial);
    }

    pub fn noteLeave(self: *PointerState, leave_serial: u32) void {
        self.entered = false;
        self.focused_surface = null;
        self.vertical_scroll = 0;
        self.horizontal_scroll = 0;
        self.axis_source = null;
        self.serials.record(.pointer_enter, leave_serial);
    }

    pub fn noteMotion(self: *PointerState, x: f64, y: f64) void {
        self.surface_x = x;
        self.surface_y = y;
    }

    pub fn noteButton(self: *PointerState, button_serial: u32, time_ms: u32, button: u32, state_value: u32) void {
        self.last_button = button;
        self.last_button_state = state_value;
        self.last_button_time = time_ms;
        self.serials.record(.pointer_button, button_serial);
    }

    pub fn noteAxis(self: *PointerState, axis: u32, value: f64) void {
        switch (axis) {
            c.WL_POINTER_AXIS_VERTICAL_SCROLL => self.vertical_scroll += value,
            c.WL_POINTER_AXIS_HORIZONTAL_SCROLL => self.horizontal_scroll += value,
            else => {},
        }
    }
};

pub const KeyboardContext = struct {
    allocator: std.mem.Allocator,
    xkb_context: ?*c.struct_xkb_context = null,
    xkb_keymap: ?*c.struct_xkb_keymap = null,
    xkb_state: ?*c.struct_xkb_state = null,
    state: linux_keyboard.KeyboardState = .{},
    focused_surface: ?*c.wl_surface = null,
    serials: serial.SerialTracker = .{},
    last_key: u32 = 0,
    last_key_state: u32 = 0,
    last_key_time: u32 = 0,
    last_keysym: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) KeyboardContext {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *KeyboardContext) void {
        if (self.xkb_state) |xkb_state| c.xkb_state_unref(xkb_state);
        if (self.xkb_keymap) |xkb_keymap| c.xkb_keymap_unref(xkb_keymap);
        if (self.xkb_context) |xkb_context| c.xkb_context_unref(xkb_context);
        self.* = undefined;
    }

    pub fn loadKeymap(self: *KeyboardContext, fd: i32, size: u32) !void {
        defer _ = std.os.linux.close(fd);

        const mapped = try std.posix.mmap(
            null,
            size,
            std.posix.PROT{ .READ = true },
            std.posix.MAP{ .TYPE = .PRIVATE },
            fd,
            0,
        );
        defer std.posix.munmap(mapped);

        const keymap_text = try self.allocator.alloc(u8, size + 1);
        defer self.allocator.free(keymap_text);
        @memcpy(keymap_text[0..size], mapped[0..size]);
        keymap_text[size] = 0;

        const xkb_context = self.xkb_context orelse blk: {
            const created = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS) orelse return error.XkbContextUnavailable;
            self.xkb_context = created;
            break :blk created;
        };

        const keymap = c.xkb_keymap_new_from_string(
            xkb_context,
            @ptrCast(keymap_text.ptr),
            c.XKB_KEYMAP_FORMAT_TEXT_V1,
            c.XKB_KEYMAP_COMPILE_NO_FLAGS,
        ) orelse return error.KeymapParseFailed;
        errdefer c.xkb_keymap_unref(keymap);

        const xkb_state = c.xkb_state_new(keymap) orelse return error.KeyStateCreationFailed;

        if (self.xkb_state) |previous_state| c.xkb_state_unref(previous_state);
        if (self.xkb_keymap) |previous_keymap| c.xkb_keymap_unref(previous_keymap);

        self.xkb_keymap = keymap;
        self.xkb_state = xkb_state;
        self.state.layout = .xkb;
        self.state.has_hardware_layout = true;
    }

    pub fn noteEnter(self: *KeyboardContext, enter_serial: u32, surface: ?*c.wl_surface) void {
        self.focused_surface = surface;
        self.serials.record(.keyboard_enter, enter_serial);
    }

    pub fn noteLeave(self: *KeyboardContext) void {
        self.focused_surface = null;
        self.last_key = 0;
        self.last_key_state = 0;
        self.last_key_time = 0;
        self.last_keysym = 0;
    }

    pub fn noteKey(self: *KeyboardContext, time_ms: u32, key: u32, state_value: u32) void {
        self.last_key = key;
        self.last_key_state = state_value;
        self.last_key_time = time_ms;
        if (self.xkb_state) |xkb_state| {
            self.last_keysym = c.xkb_state_key_get_one_sym(xkb_state, key + 8);
        }
    }

    pub fn updateModifiers(
        self: *KeyboardContext,
        depressed: u32,
        latched: u32,
        locked: u32,
        group: u32,
    ) void {
        const xkb_state = self.xkb_state orelse return;
        _ = c.xkb_state_update_mask(xkb_state, depressed, latched, locked, 0, 0, group);
        self.state.active_modifiers = .{
            .shift = isModifierActive(xkb_state, c.XKB_MOD_NAME_SHIFT),
            .ctrl = isModifierActive(xkb_state, c.XKB_MOD_NAME_CTRL),
            .alt = isModifierActive(xkb_state, c.XKB_MOD_NAME_ALT),
            .super = isModifierActive(xkb_state, c.XKB_MOD_NAME_LOGO),
            .caps_lock = isModifierActive(xkb_state, c.XKB_MOD_NAME_CAPS),
            .num_lock = isModifierActive(xkb_state, c.XKB_MOD_NAME_NUM),
        };
    }

    pub fn setRepeatInfo(self: *KeyboardContext, rate_hz: i32, delay_ms: i32) void {
        if (rate_hz >= 0) self.state.repeat.rate_hz = @intCast(rate_hz);
        if (delay_ms >= 0) self.state.repeat.delay_ms = @intCast(delay_ms);
    }

    pub fn snapshot(self: KeyboardContext) linux_keyboard.KeyboardInfo {
        return self.state.snapshot();
    }
};

pub const WaylandInputState = struct {
    pointer: PointerState = .{},
    keyboard: KeyboardContext,

    pub fn init(allocator: std.mem.Allocator) WaylandInputState {
        return .{
            .keyboard = KeyboardContext.init(allocator),
        };
    }

    pub fn deinit(self: *WaylandInputState) void {
        self.keyboard.deinit();
    }
};

fn isModifierActive(xkb_state: *c.struct_xkb_state, modifier_name: [*:0]const u8) bool {
    return c.xkb_state_mod_name_is_active(xkb_state, modifier_name, c.XKB_STATE_MODS_EFFECTIVE) != 0;
}

test "keyboard repeat info updates state" {
    var context = KeyboardContext.init(std.testing.allocator);
    defer context.deinit();
    context.setRepeatInfo(35, 300);
    try std.testing.expectEqual(@as(u32, 35), context.state.repeat.rate_hz);
    try std.testing.expectEqual(@as(u32, 300), context.state.repeat.delay_ms);
}

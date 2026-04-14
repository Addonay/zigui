const std = @import("std");
const common = @import("../common.zig");
const ui_input = @import("../../input.zig");
const dispatcher = @import("dispatcher.zig");
const headless = @import("headless.zig");
const keyboard = @import("keyboard.zig");
const text_system = @import("text_system.zig");
const types = @import("types.zig");
const wayland = @import("wayland/root.zig");
const x11 = @import("x11/root.zig");
const xdg_desktop_portal = @import("xdg_desktop_portal.zig");

pub const LinuxClipboardKind = types.LinuxClipboardKind;
pub const LinuxClipboardSnapshot = types.LinuxClipboardSnapshot;
pub const LinuxDisplayInfo = types.LinuxDisplayInfo;
pub const LinuxPathList = types.LinuxPathList;
pub const LinuxPathPromptOptions = types.LinuxPathPromptOptions;
pub const LinuxPortalSettings = types.LinuxPortalSettings;
pub const LinuxRuntimeSnapshot = types.LinuxRuntimeSnapshot;
pub const LinuxWindowInfo = types.LinuxWindowInfo;
pub const LinuxWindowAppearance = types.LinuxWindowAppearance;
pub const LinuxWindowButtonLayout = types.LinuxWindowButtonLayout;

pub const LinuxRuntimeKind = enum {
    wayland,
    x11,
    headless,
};

pub const EnvironmentProbe = struct {
    xdg_session_type: ?[]const u8,
    wayland_display: ?[]const u8,
    x_display: ?[]const u8,
    current_desktop: ?[]const u8,
    desktop_session: ?[]const u8,
    dbus_session_bus_address: ?[]const u8,
    shell: ?[]const u8,
};

pub const DesktopEnvironment = enum {
    unknown,
    cosmic,
    gnome,
    hyprland,
    kde,
    sway,
    weston,
    xfce,
};

pub const LinuxPlatformState = struct {
    allocator: std.mem.Allocator,
    environment: EnvironmentProbe,
    dispatcher: dispatcher.Dispatcher = .{},
    keyboard: keyboard.KeyboardState = .{},
    text: text_system.LinuxTextSystem = .{},
    clipboard: x11.clipboard.ClipboardState = .{},
    portal: xdg_desktop_portal.PortalState,

    pub fn init(allocator: std.mem.Allocator) LinuxPlatformState {
        const environment = probeEnvironment();
        return .{
            .allocator = allocator,
            .environment = environment,
            .portal = xdg_desktop_portal.PortalState.init(
                allocator,
                environment.dbus_session_bus_address != null,
                desktopEnvironment(environment) != .unknown,
            ),
        };
    }

    pub fn deinit(self: *LinuxPlatformState) void {
        self.portal.deinit(self.allocator);
        self.dispatcher.deinit(self.allocator);
    }

    pub fn runtimeKind(self: LinuxPlatformState) LinuxRuntimeKind {
        return guessRuntimeKind(self.environment);
    }

    pub fn desktop(self: LinuxPlatformState) DesktopEnvironment {
        return desktopEnvironment(self.environment);
    }

    pub fn compositorName(self: LinuxPlatformState) []const u8 {
        return switch (self.runtimeKind()) {
            .wayland => "wayland",
            .x11 => "x11",
            .headless => "headless",
        };
    }

    pub fn services(self: LinuxPlatformState) common.PlatformServices {
        return .{
            .backend = switch (self.runtimeKind()) {
                .wayland => .linux_wayland,
                .x11 => .linux_x11,
                .headless => .linux_headless,
            },
            .supports_ime = self.runtimeKind() != .headless,
            .supports_clipboard = self.runtimeKind() != .headless and self.portal.supports_clipboard,
            .supports_gpu_rendering = false,
            .supports_multiple_windows = self.runtimeKind() != .headless,
        };
    }

    pub fn diagnostics(self: LinuxPlatformState) common.Diagnostics {
        const note = switch (self.desktop()) {
            .cosmic => "COSMIC session detected. Linux runtime is Wayland-first with portal helpers, primary selection, fractional scaling, and activation-token support. Renderer, text shaping, and IME composition still need to be built.",
            .gnome => "GNOME session detected. Linux runtime is Wayland-first with portal helpers, primary selection, fractional scaling, and activation-token support. Renderer, text shaping, and IME composition still need to be built.",
            .hyprland => "Hyprland session detected. Linux runtime is Wayland-first with portal helpers, primary selection, fractional scaling, and activation-token support. Renderer, text shaping, and IME composition still need to be built.",
            .kde => "KDE session detected. Linux runtime is Wayland-first with portal helpers, primary selection, fractional scaling, and activation-token support. Renderer, text shaping, and IME composition still need to be built.",
            .sway => "Sway session detected. Linux runtime is Wayland-first with portal helpers, primary selection, fractional scaling, and activation-token support. Renderer, text shaping, and IME composition still need to be built.",
            .weston => "Weston session detected. Linux runtime is Wayland-first with portal helpers, primary selection, fractional scaling, and activation-token support. Renderer, text shaping, and IME composition still need to be built.",
            .xfce => "XFCE session detected. Linux runtime is Wayland-first with portal helpers, primary selection, fractional scaling, and activation-token support. Renderer, text shaping, and IME composition still need to be built.",
            .unknown => "Linux runtime is Wayland-first with X11 fallback and headless support. Wayland windowing, primary selection, fractional scaling, and activation handoff are implemented; renderer, text shaping, and advanced input remain in progress.",
        };
        return .{
            .backend_name = switch (self.runtimeKind()) {
                .wayland => "linux-wayland",
                .x11 => "linux-x11",
                .headless => "linux-headless",
            },
            .window_system = switch (self.runtimeKind()) {
                .wayland => "Wayland",
                .x11 => "X11",
                .headless => "Headless",
            },
            .renderer = "unbound",
            .note = note,
        };
    }
};

pub const LaunchTarget = union(enum) {
    uri: []const u8,
    reveal_path: []const u8,
};

pub const LaunchCommand = struct {
    program: []const u8,
    argv: [4]?[]const u8 = .{ null, null, null, null },

    pub fn slice(self: *const LaunchCommand) [4]?[]const u8 {
        return self.argv;
    }
};

pub const LinuxPlatform = struct {
    allocator: std.mem.Allocator,
    state: LinuxPlatformState,

    pub fn init(allocator: std.mem.Allocator) LinuxPlatform {
        return .{
            .allocator = allocator,
            .state = LinuxPlatformState.init(allocator),
        };
    }

    pub fn deinit(self: *LinuxPlatform) void {
        self.state.deinit();
    }

    pub fn runtimeKind(self: LinuxPlatform) LinuxRuntimeKind {
        return self.state.runtimeKind();
    }

    pub fn services(self: LinuxPlatform) common.PlatformServices {
        return self.state.services();
    }

    pub fn diagnostics(self: LinuxPlatform) common.Diagnostics {
        return self.state.diagnostics();
    }

    pub fn createBackend(self: LinuxPlatform, options: common.WindowOptions) !LinuxBackend {
        return LinuxBackend.initAuto(self.allocator, options);
    }

    pub fn portalSettings(self: LinuxPlatform) LinuxPortalSettings {
        return self.state.portal.settings;
    }

    pub fn promptForPathsAlloc(
        self: LinuxPlatform,
        allocator: std.mem.Allocator,
        options: LinuxPathPromptOptions,
    ) !?LinuxPathList {
        return self.state.portal.promptForPathsAlloc(allocator, options);
    }

    pub fn promptForNewPathAlloc(
        self: LinuxPlatform,
        allocator: std.mem.Allocator,
        options: LinuxPathPromptOptions,
    ) !?[]u8 {
        return self.state.portal.promptForNewPathAlloc(allocator, options);
    }

    pub fn appPath(self: LinuxPlatform, allocator: std.mem.Allocator) ![]u8 {
        _ = self;
        return std.fs.selfExePathAlloc(allocator);
    }

    pub fn openUri(self: LinuxPlatform, uri: []const u8) !void {
        const command = self.commandFor(.{ .uri = uri }) orelse return error.LaunchCommandUnavailable;
        try spawnDetached(command);
    }

    pub fn revealPath(self: LinuxPlatform, path: []const u8) !void {
        const command = self.commandFor(.{ .reveal_path = path }) orelse return error.LaunchCommandUnavailable;
        try spawnDetached(command);
    }

    pub fn restart(self: LinuxPlatform, allocator: std.mem.Allocator, binary_path: ?[]const u8) !void {
        const resolved = if (binary_path) |path| try allocator.dupe(u8, path) else try self.appPath(allocator);
        defer allocator.free(resolved);

        const command = LaunchCommand{
            .program = resolved,
            .argv = .{ resolved, null, null, null },
        };
        try spawnDetached(command);
    }

    pub fn commandFor(self: LinuxPlatform, target: LaunchTarget) ?LaunchCommand {
        const desktop = self.state.desktop();
        return switch (target) {
            .uri => |uri| commandForUri(desktop, uri),
            .reveal_path => |path| commandForRevealPath(desktop, path),
        };
    }
};

fn getenvSlice(name: [*:0]const u8) ?[]const u8 {
    const value = std.c.getenv(name) orelse return null;
    return std.mem.span(value);
}

pub fn probeEnvironment() EnvironmentProbe {
    return .{
        .xdg_session_type = getenvSlice("XDG_SESSION_TYPE"),
        .wayland_display = getenvSlice("WAYLAND_DISPLAY"),
        .x_display = getenvSlice("DISPLAY"),
        .current_desktop = getenvSlice("XDG_CURRENT_DESKTOP"),
        .desktop_session = getenvSlice("DESKTOP_SESSION"),
        .dbus_session_bus_address = getenvSlice("DBUS_SESSION_BUS_ADDRESS"),
        .shell = getenvSlice("SHELL"),
    };
}

pub fn guessRuntimeKind(env: EnvironmentProbe) LinuxRuntimeKind {
    if (env.xdg_session_type) |session_type| {
        if (std.ascii.eqlIgnoreCase(session_type, "wayland")) return .wayland;
        if (std.ascii.eqlIgnoreCase(session_type, "x11")) return .x11;
        if (std.ascii.eqlIgnoreCase(session_type, "tty")) return .headless;
    }
    if (env.wayland_display != null) return .wayland;
    if (env.x_display != null) return .x11;
    return .headless;
}

pub fn desktopEnvironment(env: EnvironmentProbe) DesktopEnvironment {
    if (env.current_desktop) |desktop| {
        if (containsToken(desktop, "COSMIC")) return .cosmic;
        if (containsToken(desktop, "GNOME")) return .gnome;
        if (containsToken(desktop, "Hyprland")) return .hyprland;
        if (containsToken(desktop, "KDE")) return .kde;
        if (containsToken(desktop, "Sway")) return .sway;
        if (containsToken(desktop, "Weston")) return .weston;
        if (containsToken(desktop, "XFCE")) return .xfce;
    }
    if (env.desktop_session) |session| {
        if (containsToken(session, "cosmic")) return .cosmic;
        if (containsToken(session, "gnome")) return .gnome;
        if (containsToken(session, "hyprland")) return .hyprland;
        if (containsToken(session, "kde")) return .kde;
        if (containsToken(session, "sway")) return .sway;
        if (containsToken(session, "weston")) return .weston;
        if (containsToken(session, "xfce")) return .xfce;
    }
    return .unknown;
}

fn containsToken(haystack: []const u8, needle: []const u8) bool {
    return std.ascii.indexOfIgnoreCase(haystack, needle) != null;
}

fn commandForUri(desktop: DesktopEnvironment, uri: []const u8) ?LaunchCommand {
    if (desktop == .gnome or desktop == .cosmic) {
        if (commandExists("/usr/bin/gio")) {
            return .{
                .program = "/usr/bin/gio",
                .argv = .{ "/usr/bin/gio", "open", uri, null },
            };
        }
    }
    if ((desktop == .kde or desktop == .xfce) and commandExists("/usr/bin/kioclient5")) {
        return .{
            .program = "/usr/bin/kioclient5",
            .argv = .{ "/usr/bin/kioclient5", "open", uri, null },
        };
    }
    if (commandExists("/usr/bin/xdg-open")) {
        return .{
            .program = "/usr/bin/xdg-open",
            .argv = .{ "/usr/bin/xdg-open", uri, null, null },
        };
    }
    return null;
}

fn commandForRevealPath(desktop: DesktopEnvironment, path: []const u8) ?LaunchCommand {
    if (desktop == .gnome or desktop == .cosmic) {
        if (commandExists("/usr/bin/gio")) {
            return .{
                .program = "/usr/bin/gio",
                .argv = .{ "/usr/bin/gio", "open", path, null },
            };
        }
    }
    if ((desktop == .kde or desktop == .xfce) and commandExists("/usr/bin/kioclient5")) {
        return .{
            .program = "/usr/bin/kioclient5",
            .argv = .{ "/usr/bin/kioclient5", "show", path, null },
        };
    }
    if (commandExists("/usr/bin/xdg-open")) {
        return .{
            .program = "/usr/bin/xdg-open",
            .argv = .{ "/usr/bin/xdg-open", path, null, null },
        };
    }
    return null;
}

fn commandExists(path: []const u8) bool {
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0) catch return false;
    _ = std.os.linux.close(fd);
    return true;
}

fn spawnDetached(command: LaunchCommand) !void {
    const pid = std.c.fork();
    if (pid < 0) return error.ProcessSpawnFailed;
    if (pid > 0) return;

    _ = std.c.setsid();

    var argv_storage: [5]?[*:0]const u8 = .{ null, null, null, null, null };
    var arg_buffers: [4]?[:0]u8 = .{ null, null, null, null };
    defer {
        for (&arg_buffers) |*entry| {
            if (entry.*) |buffer| std.heap.c_allocator.free(buffer);
        }
    }

    inline for (0..4) |index| {
        if (command.argv[index]) |arg| {
            const z_arg = try std.heap.c_allocator.dupeZ(u8, arg);
            arg_buffers[index] = z_arg;
            argv_storage[index] = z_arg.ptr;
        }
    }

    const result = std.c.execve(
        argv_storage[0].?,
        @ptrCast(&argv_storage),
        @ptrCast(std.c.environ),
    );
    if (result != 0) std.c._exit(127);
    unreachable;
}

pub const LinuxWaylandBackend = struct {
    allocator: std.mem.Allocator,
    options: common.WindowOptions,
    dispatcher: dispatcher.Dispatcher = .{},
    keyboard: keyboard.KeyboardState = .{},
    text: text_system.TextSystemConfig = .{},
    client: wayland.client.WaylandClient,
    appearance: LinuxWindowAppearance = .light,
    button_layout: LinuxWindowButtonLayout = .{},

    pub fn init(allocator: std.mem.Allocator, options: common.WindowOptions) !LinuxWaylandBackend {
        const client = try wayland.client.WaylandClient.init(allocator, options);
        errdefer {
            var owned_client = client;
            owned_client.deinit();
        }
        const visual_settings = xdg_desktop_portal.currentVisualSettings(allocator);
        return .{
            .allocator = allocator,
            .options = options,
            .client = client,
            .appearance = visual_settings.appearance,
            .button_layout = visual_settings.button_layout,
        };
    }

    pub fn deinit(self: *LinuxWaylandBackend) void {
        self.client.deinit();
    }

    pub fn run(self: *LinuxWaylandBackend) !void {
        try self.client.run();
    }

    pub fn name(self: *const LinuxWaylandBackend) []const u8 {
        _ = self;
        return "linux-wayland";
    }

    pub fn services(self: *const LinuxWaylandBackend) common.PlatformServices {
        _ = self;
        return .{
            .backend = .linux_wayland,
            .supports_ime = true,
            .supports_clipboard = true,
            .supports_gpu_rendering = false,
            .supports_multiple_windows = true,
        };
    }

    pub fn diagnostics(self: *const LinuxWaylandBackend) common.Diagnostics {
        _ = self;
        return .{
            .backend_name = "linux-wayland",
            .window_system = "Wayland",
            .renderer = "unbound",
            .note = "Wayland runtime creates a native xdg-shell window with shared-memory surfaces, cursor themes, primary selection, fractional scaling, and activation-token support. Renderer, text shaping, IME composition, and drag payload transfer still need to be built.",
        };
    }

    pub fn compositorName(self: *const LinuxWaylandBackend) []const u8 {
        return self.client.compositorName();
    }

    pub fn keyboardInfo(self: *const LinuxWaylandBackend) keyboard.KeyboardInfo {
        return self.client.keyboardInfo();
    }

    pub fn snapshot(self: *const LinuxWaylandBackend) LinuxRuntimeSnapshot {
        var runtime_snapshot = self.client.snapshot();
        runtime_snapshot.appearance = self.appearance;
        runtime_snapshot.button_layout = self.button_layout;
        return runtime_snapshot;
    }

    pub fn setCursorStyle(self: *LinuxWaylandBackend, cursor_kind: common.Cursor) void {
        self.client.setCursorStyle(cursor_kind);
    }

    pub fn writeTextToClipboard(
        self: *LinuxWaylandBackend,
        kind: LinuxClipboardKind,
        text: []const u8,
    ) !void {
        try self.client.writeTextToClipboard(kind, text);
    }

    pub fn readTextFromClipboardAlloc(
        self: *LinuxWaylandBackend,
        kind: LinuxClipboardKind,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        return switch (kind) {
            .clipboard => self.client.readClipboardTextAlloc(allocator),
            .primary => self.client.readPrimarySelectionTextAlloc(allocator),
        };
    }

    pub fn displayInfosAlloc(
        self: *const LinuxWaylandBackend,
        allocator: std.mem.Allocator,
    ) ![]LinuxDisplayInfo {
        return self.client.displayInfosAlloc(allocator);
    }

    pub fn windowInfosAlloc(
        self: *const LinuxWaylandBackend,
        allocator: std.mem.Allocator,
    ) ![]LinuxWindowInfo {
        return self.client.windowInfosAlloc(allocator);
    }

    pub fn drainEventsAlloc(
        self: *LinuxWaylandBackend,
        allocator: std.mem.Allocator,
    ) ![]ui_input.InputEvent {
        return self.client.drainEventsAlloc(allocator);
    }

    pub fn openWindow(self: *LinuxWaylandBackend, options: common.WindowOptions) !usize {
        return self.client.openWindow(options);
    }

    pub fn closeWindow(self: *LinuxWaylandBackend, handle: usize) !void {
        try self.client.closeWindow(handle);
    }
};

pub const LinuxBackend = union(enum) {
    wayland: LinuxWaylandBackend,
    x11: x11.X11Backend,
    headless: headless.HeadlessBackend,

    pub fn initAuto(allocator: std.mem.Allocator, options: common.WindowOptions) !LinuxBackend {
        const env = probeEnvironment();
        return switch (guessRuntimeKind(env)) {
            .wayland => initWaylandOrFallback(allocator, options, env),
            .x11 => .{ .x11 = try x11.client.X11Backend.init(allocator, options) },
            .headless => .{ .headless = headless.HeadlessBackend.init(allocator, options) },
        };
    }

    pub fn deinit(self: *LinuxBackend) void {
        switch (self.*) {
            .wayland => |*backend| backend.deinit(),
            .x11 => |*backend| backend.deinit(),
            .headless => |*backend| backend.deinit(),
        }
    }

    pub fn run(self: *LinuxBackend) !void {
        switch (self.*) {
            .wayland => |*backend| try backend.run(),
            .x11 => |*backend| try backend.run(),
            .headless => |*backend| try backend.run(),
        }
    }

    pub fn name(self: *const LinuxBackend) []const u8 {
        return switch (self.*) {
            .wayland => |*backend| backend.name(),
            .x11 => |*backend| backend.name(),
            .headless => |*backend| backend.name(),
        };
    }

    pub fn services(self: *const LinuxBackend) common.PlatformServices {
        return switch (self.*) {
            .wayland => |*backend| backend.services(),
            .x11 => |*backend| backend.services(),
            .headless => |*backend| backend.services(),
        };
    }

    pub fn diagnostics(self: *const LinuxBackend) common.Diagnostics {
        return switch (self.*) {
            .wayland => |*backend| backend.diagnostics(),
            .x11 => |*backend| backend.diagnostics(),
            .headless => |*backend| backend.diagnostics(),
        };
    }

    pub fn runtimeKind(self: *const LinuxBackend) LinuxRuntimeKind {
        return switch (self.*) {
            .wayland => .wayland,
            .x11 => .x11,
            .headless => .headless,
        };
    }

    pub fn compositorName(self: *const LinuxBackend) []const u8 {
        return switch (self.*) {
            .wayland => |*backend| backend.compositorName(),
            .x11 => |*backend| backend.compositorName(),
            .headless => |*backend| backend.compositorName(),
        };
    }

    pub fn keyboardInfo(self: *const LinuxBackend) keyboard.KeyboardInfo {
        return switch (self.*) {
            .wayland => |*backend| backend.keyboardInfo(),
            .x11 => |*backend| backend.keyboardInfo(),
            .headless => |*backend| backend.keyboardInfo(),
        };
    }

    pub fn snapshot(self: *const LinuxBackend) LinuxRuntimeSnapshot {
        return switch (self.*) {
            .wayland => |*backend| backend.snapshot(),
            .x11 => |*backend| backend.snapshot(),
            .headless => |*backend| backend.snapshot(),
        };
    }

    pub fn setCursorStyle(self: *LinuxBackend, cursor_kind: common.Cursor) void {
        switch (self.*) {
            .wayland => |*backend| backend.setCursorStyle(cursor_kind),
            .x11 => |*backend| backend.setCursorStyle(cursor_kind),
            .headless => |*backend| backend.setCursorStyle(cursor_kind),
        }
    }

    pub fn writeTextToClipboard(
        self: *LinuxBackend,
        kind: LinuxClipboardKind,
        text: []const u8,
    ) !void {
        switch (self.*) {
            .wayland => |*backend| try backend.writeTextToClipboard(kind, text),
            .x11 => |*backend| try backend.writeTextToClipboard(kind, text),
            .headless => |*backend| try backend.writeTextToClipboard(kind, text),
        }
    }

    pub fn readTextFromClipboardAlloc(
        self: *LinuxBackend,
        kind: LinuxClipboardKind,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        return switch (self.*) {
            .wayland => |*backend| backend.readTextFromClipboardAlloc(kind, allocator),
            .x11 => |*backend| backend.readTextFromClipboardAlloc(kind, allocator),
            .headless => |*backend| backend.readTextFromClipboardAlloc(kind, allocator),
        };
    }

    pub fn displayInfosAlloc(
        self: *const LinuxBackend,
        allocator: std.mem.Allocator,
    ) ![]LinuxDisplayInfo {
        return switch (self.*) {
            .wayland => |*backend| backend.displayInfosAlloc(allocator),
            .x11 => |*backend| backend.displayInfosAlloc(allocator),
            .headless => |*backend| backend.displayInfosAlloc(allocator),
        };
    }

    pub fn windowInfosAlloc(
        self: *const LinuxBackend,
        allocator: std.mem.Allocator,
    ) ![]LinuxWindowInfo {
        return switch (self.*) {
            .wayland => |*backend| backend.windowInfosAlloc(allocator),
            .x11 => |*backend| backend.windowInfosAlloc(allocator),
            .headless => |*backend| backend.windowInfosAlloc(allocator),
        };
    }

    pub fn drainEventsAlloc(
        self: *LinuxBackend,
        allocator: std.mem.Allocator,
    ) ![]ui_input.InputEvent {
        return switch (self.*) {
            .wayland => |*backend| backend.drainEventsAlloc(allocator),
            .x11 => |*backend| backend.drainEventsAlloc(allocator),
            .headless => |*backend| backend.drainEventsAlloc(allocator),
        };
    }

    pub fn openWindow(self: *LinuxBackend, options: common.WindowOptions) !usize {
        return switch (self.*) {
            .wayland => |*backend| backend.openWindow(options),
            .x11 => |*backend| backend.openWindow(options),
            .headless => |*backend| backend.openWindow(options),
        };
    }

    pub fn closeWindow(self: *LinuxBackend, handle: usize) !void {
        switch (self.*) {
            .wayland => |*backend| try backend.closeWindow(handle),
            .x11 => |*backend| try backend.closeWindow(@intCast(handle)),
            .headless => |*backend| try backend.closeWindow(handle),
        }
    }
};

const LinuxRuntimeState = struct {
    allocator: std.mem.Allocator,
    platform: LinuxPlatform,
    backend: LinuxBackend,

    fn init(allocator: std.mem.Allocator, options: common.WindowOptions) !LinuxRuntimeState {
        var platform = LinuxPlatform.init(allocator);
        errdefer platform.deinit();
        return .{
            .allocator = allocator,
            .platform = platform,
            .backend = try platform.createBackend(options),
        };
    }

    fn deinit(self: *LinuxRuntimeState) void {
        self.backend.deinit();
        self.platform.deinit();
    }
};

const vtable = common.RuntimeVTable{
    .deinit = runtimeDeinit,
    .run = runtimeRun,
    .name = runtimeName,
    .services = runtimeServices,
    .diagnostics = runtimeDiagnostics,
    .snapshot = runtimeSnapshot,
    .display_infos_alloc = runtimeDisplayInfosAlloc,
    .window_infos_alloc = runtimeWindowInfosAlloc,
    .drain_events_alloc = runtimeDrainEventsAlloc,
    .set_cursor_style = runtimeSetCursorStyle,
    .write_text_to_clipboard = runtimeWriteTextToClipboard,
    .read_text_from_clipboard_alloc = runtimeReadTextFromClipboardAlloc,
    .open_uri = runtimeOpenUri,
    .reveal_path = runtimeRevealPath,
    .prompt_for_paths_alloc = runtimePromptForPathsAlloc,
    .prompt_for_new_path_alloc = runtimePromptForNewPathAlloc,
    .open_window = runtimeOpenWindow,
    .close_window = runtimeCloseWindow,
};

pub fn createRuntime(allocator: std.mem.Allocator, options: common.WindowOptions) !common.Runtime {
    const runtime_state = try allocator.create(LinuxRuntimeState);
    errdefer allocator.destroy(runtime_state);

    runtime_state.* = try LinuxRuntimeState.init(allocator, options);
    return .{
        .allocator = allocator,
        .ptr = runtime_state,
        .vtable = &vtable,
    };
}

fn initWaylandOrFallback(
    allocator: std.mem.Allocator,
    options: common.WindowOptions,
    env: EnvironmentProbe,
) !LinuxBackend {
    const backend = LinuxWaylandBackend.init(allocator, options) catch |err| switch (err) {
        error.DisplayUnavailable,
        error.MissingCompositor,
        error.MissingSharedMemory,
        error.MissingShell,
        error.NativeBackendNotImplemented,
        => return if (env.x_display != null)
            .{ .x11 = try x11.client.X11Backend.init(allocator, options) }
        else
            .{ .headless = headless.HeadlessBackend.init(allocator, options) },
        else => return err,
    };
    return .{ .wayland = backend };
}

fn runtimeDeinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const runtime_state: *LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    runtime_state.deinit();
    allocator.destroy(runtime_state);
}

fn runtimeRun(ptr: *anyopaque) anyerror!void {
    const runtime_state: *LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    try runtime_state.backend.run();
}

fn runtimeName(ptr: *const anyopaque) []const u8 {
    const runtime_state: *const LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    return runtime_state.backend.name();
}

fn runtimeServices(ptr: *const anyopaque) common.PlatformServices {
    const runtime_state: *const LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    return runtime_state.backend.services();
}

fn runtimeDiagnostics(ptr: *const anyopaque) common.Diagnostics {
    const runtime_state: *const LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    return runtime_state.backend.diagnostics();
}

fn runtimeSnapshot(ptr: *const anyopaque) common.RuntimeSnapshot {
    const runtime_state: *const LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    return runtime_state.backend.snapshot();
}

fn runtimeDisplayInfosAlloc(
    ptr: *const anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]common.DisplayInfo {
    const runtime_state: *const LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    return try runtime_state.backend.displayInfosAlloc(allocator);
}

fn runtimeWindowInfosAlloc(
    ptr: *const anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]common.WindowInfo {
    const runtime_state: *const LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    return try runtime_state.backend.windowInfosAlloc(allocator);
}

fn runtimeDrainEventsAlloc(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]ui_input.InputEvent {
    const runtime_state: *LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    return try runtime_state.backend.drainEventsAlloc(allocator);
}

fn runtimeSetCursorStyle(ptr: *anyopaque, cursor_kind: common.Cursor) void {
    const runtime_state: *LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    runtime_state.backend.setCursorStyle(cursor_kind);
}

fn runtimeWriteTextToClipboard(
    ptr: *anyopaque,
    kind: common.ClipboardKind,
    text: []const u8,
) anyerror!void {
    const runtime_state: *LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    try runtime_state.backend.writeTextToClipboard(kind, text);
}

fn runtimeReadTextFromClipboardAlloc(
    ptr: *anyopaque,
    kind: common.ClipboardKind,
    allocator: std.mem.Allocator,
) anyerror![]u8 {
    const runtime_state: *LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    return try runtime_state.backend.readTextFromClipboardAlloc(kind, allocator);
}

fn runtimeOpenUri(ptr: *anyopaque, uri: []const u8) anyerror!void {
    const runtime_state: *LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    try runtime_state.platform.openUri(uri);
}

fn runtimeRevealPath(ptr: *anyopaque, path: []const u8) anyerror!void {
    const runtime_state: *LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    try runtime_state.platform.revealPath(path);
}

fn runtimePromptForPathsAlloc(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    options: common.PathPromptOptions,
) anyerror!?common.PathList {
    const runtime_state: *LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    return try runtime_state.platform.promptForPathsAlloc(allocator, options);
}

fn runtimePromptForNewPathAlloc(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    options: common.PathPromptOptions,
) anyerror!?[]u8 {
    const runtime_state: *LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    return try runtime_state.platform.promptForNewPathAlloc(allocator, options);
}

fn runtimeOpenWindow(ptr: *anyopaque, options: common.WindowOptions) anyerror!usize {
    const runtime_state: *LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    return try runtime_state.backend.openWindow(options);
}

fn runtimeCloseWindow(ptr: *anyopaque, handle: usize) anyerror!void {
    const runtime_state: *LinuxRuntimeState = @ptrCast(@alignCast(ptr));
    try runtime_state.backend.closeWindow(handle);
}

test "runtime selection prefers wayland when wayland variables are present" {
    const runtime_kind = guessRuntimeKind(.{
        .xdg_session_type = "wayland",
        .wayland_display = "wayland-0",
        .x_display = ":0",
    });
    try std.testing.expectEqual(LinuxRuntimeKind.wayland, runtime_kind);
}

test "runtime selection falls back to x11 when only display is present" {
    const runtime_kind = guessRuntimeKind(.{
        .xdg_session_type = null,
        .wayland_display = null,
        .x_display = ":0",
    });
    try std.testing.expectEqual(LinuxRuntimeKind.x11, runtime_kind);
}

test "runtime selection becomes headless without desktop environment variables" {
    const runtime_kind = guessRuntimeKind(.{
        .xdg_session_type = null,
        .wayland_display = null,
        .x_display = null,
        .current_desktop = null,
        .desktop_session = null,
        .dbus_session_bus_address = null,
        .shell = null,
    });
    try std.testing.expectEqual(LinuxRuntimeKind.headless, runtime_kind);
}

test "desktop detection prefers current desktop token" {
    const desktop = desktopEnvironment(.{
        .xdg_session_type = "wayland",
        .wayland_display = "wayland-0",
        .x_display = null,
        .current_desktop = "GNOME:GNOME-Classic",
        .desktop_session = "gnome",
        .dbus_session_bus_address = "unix:path=/run/user/1000/bus",
        .shell = "/bin/bash",
    });
    try std.testing.expectEqual(DesktopEnvironment.gnome, desktop);
}

test "linux platform builds xdg-open fallback command" {
    const command = commandForUri(.unknown, "https://ziglang.org");
    if (command) |resolved| {
        try std.testing.expectEqualStrings("/usr/bin/xdg-open", resolved.program);
    } else {
        try std.testing.expect(!commandExists("/usr/bin/xdg-open"));
    }
}

test "linux backend snapshot exposes headless runtime state" {
    var backend = LinuxBackend{
        .headless = headless.HeadlessBackend.init(std.testing.allocator, .{}),
    };
    defer backend.deinit();

    const snapshot = backend.snapshot();
    try std.testing.expectEqual(LinuxRuntimeKind.headless, backend.runtimeKind());
    try std.testing.expectEqualStrings("headless", snapshot.compositor_name);
    try std.testing.expectEqual(@as(usize, 0), snapshot.window_count);
}

const std = @import("std");
const types = @import("types.zig");

const DialogBackend = enum {
    kdialog,
    zenity,
    unavailable,
};

pub const PortalState = struct {
    available: bool,
    supports_clipboard: bool,
    prefers_portal_open_uri: bool,
    prefers_portal_file_dialogs: bool,
    settings: types.LinuxPortalSettings = .{},

    pub fn init(
        allocator: std.mem.Allocator,
        has_session_bus: bool,
        has_known_desktop: bool,
    ) PortalState {
        return .{
            .available = has_session_bus,
            .supports_clipboard = has_session_bus,
            .prefers_portal_open_uri = has_session_bus and has_known_desktop,
            .prefers_portal_file_dialogs = has_session_bus and has_known_desktop,
            .settings = probeSettings(allocator),
        };
    }

    pub fn deinit(self: *PortalState, allocator: std.mem.Allocator) void {
        if (self.settings.cursor_theme) |theme| allocator.free(theme);
        self.* = undefined;
    }

    pub fn appearance(self: PortalState) types.LinuxWindowAppearance {
        return self.settings.appearance;
    }

    pub fn buttonLayout(self: PortalState) types.LinuxWindowButtonLayout {
        return self.settings.button_layout;
    }

    pub fn promptForPathsAlloc(
        self: PortalState,
        allocator: std.mem.Allocator,
        options: types.LinuxPathPromptOptions,
    ) !?types.LinuxPathList {
        _ = self;
        const backend = detectDialogBackend();
        if (backend == .unavailable) return error.FileDialogUnavailable;

        var argv = try buildOpenPromptCommand(allocator, backend, options);
        defer freeArgv(allocator, &argv);

        const stdout = try runDialog(allocator, argv.items);
        defer allocator.free(stdout);
        if (stdout.len == 0) return null;
        return try parsePathsOutput(allocator, stdout);
    }

    pub fn promptForNewPathAlloc(
        self: PortalState,
        allocator: std.mem.Allocator,
        options: types.LinuxPathPromptOptions,
    ) !?[]u8 {
        _ = self;
        const backend = detectDialogBackend();
        if (backend == .unavailable) return error.FileDialogUnavailable;

        var argv = try buildSavePromptCommand(allocator, backend, options);
        defer freeArgv(allocator, &argv);

        const stdout = try runDialog(allocator, argv.items);
        defer allocator.free(stdout);
        if (stdout.len == 0) return null;

        const trimmed = std.mem.trim(u8, stdout, " \r\n\t");
        if (trimmed.len == 0) return null;
        return try allocator.dupe(u8, trimmed);
    }
};

pub const VisualSettings = struct {
    appearance: types.LinuxWindowAppearance = .light,
    button_layout: types.LinuxWindowButtonLayout = .{},
};

pub fn currentVisualSettings(allocator: std.mem.Allocator) VisualSettings {
    var portal = PortalState.init(
        allocator,
        getenvSlice("DBUS_SESSION_BUS_ADDRESS") != null,
        getenvSlice("XDG_CURRENT_DESKTOP") != null or getenvSlice("DESKTOP_SESSION") != null,
    );
    defer portal.deinit(allocator);
    return .{
        .appearance = portal.appearance(),
        .button_layout = portal.buttonLayout(),
    };
}

fn probeSettings(allocator: std.mem.Allocator) types.LinuxPortalSettings {
    var settings = types.LinuxPortalSettings{};

    if (getenvSlice("GTK_THEME")) |theme| {
        if (std.ascii.indexOfIgnoreCase(theme, ":dark") != null or
            std.ascii.indexOfIgnoreCase(theme, "-dark") != null)
        {
            settings.appearance = .dark;
        }
    }

    if (getenvSlice("XCURSOR_THEME")) |theme| {
        settings.cursor_theme = allocator.dupe(u8, theme) catch null;
    } else if (runSettingCommand(allocator, &.{ "gsettings", "get", "org.gnome.desktop.interface", "cursor-theme" })) |value| {
        defer allocator.free(value);
        const maybe_theme = parseQuotedSetting(allocator, value) catch null;
        if (maybe_theme) |theme| settings.cursor_theme = theme;
    }

    if (getenvSlice("XCURSOR_SIZE")) |value| {
        settings.cursor_size = std.fmt.parseUnsigned(u32, value, 10) catch null;
    } else if (runSettingCommand(allocator, &.{ "gsettings", "get", "org.gnome.desktop.interface", "cursor-size" })) |value| {
        defer allocator.free(value);
        settings.cursor_size = parseIntegerSetting(value);
    }

    settings.auto_hide_scrollbars = if (getenvSlice("GTK_OVERLAY_SCROLLING")) |value|
        std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "true")
    else
        false;

    if (runSettingCommand(allocator, &.{ "gsettings", "get", "org.gnome.desktop.interface", "color-scheme" })) |value| {
        defer allocator.free(value);
        settings.appearance = parseAppearance(value);
    }

    if (runSettingCommand(allocator, &.{ "gsettings", "get", "org.gnome.desktop.wm.preferences", "button-layout" })) |value| {
        defer allocator.free(value);
        if (parseButtonLayout(value)) |layout| settings.button_layout = layout;
    }

    return settings;
}

fn detectDialogBackend() DialogBackend {
    if (commandAvailable("kdialog")) return .kdialog;
    if (commandAvailable("zenity")) return .zenity;
    if (commandAvailable("qarma")) return .zenity;
    if (commandAvailable("matedialog")) return .zenity;
    return .unavailable;
}

fn buildOpenPromptCommand(
    allocator: std.mem.Allocator,
    backend: DialogBackend,
    options: types.LinuxPathPromptOptions,
) !std.ArrayList([]u8) {
    var argv: std.ArrayList([]u8) = .empty;
    errdefer freeArgv(allocator, &argv);

    switch (backend) {
        .kdialog => {
            try argv.append(allocator, try allocator.dupe(u8, "kdialog"));
            if (options.directories) {
                try argv.append(allocator, try allocator.dupe(u8, "--getexistingdirectory"));
            } else if (options.multiple) {
                try argv.append(allocator, try allocator.dupe(u8, "--getopenfilename"));
                try argv.append(allocator, try allocator.dupe(u8, "--multiple"));
                try argv.append(allocator, try allocator.dupe(u8, "--separate-output"));
            } else {
                try argv.append(allocator, try allocator.dupe(u8, "--getopenfilename"));
            }

            if (options.current_directory) |directory| {
                try argv.append(allocator, try allocator.dupe(u8, directory));
            }
            if (options.title) |title| {
                try argv.append(allocator, try allocator.dupe(u8, "--title"));
                try argv.append(allocator, try allocator.dupe(u8, title));
            }
        },
        .zenity => {
            const command_name = if (commandAvailable("zenity"))
                "zenity"
            else if (commandAvailable("qarma"))
                "qarma"
            else if (commandAvailable("matedialog"))
                "matedialog"
            else
                return error.FileDialogUnavailable;
            try argv.append(allocator, try allocator.dupe(u8, command_name));
            try argv.append(allocator, try allocator.dupe(u8, "--file-selection"));

            if (options.directories) {
                try argv.append(allocator, try allocator.dupe(u8, "--directory"));
            }
            if (options.multiple) {
                try argv.append(allocator, try allocator.dupe(u8, "--multiple"));
                try argv.append(allocator, try allocator.dupe(u8, "--separator=\n"));
            }
            if (options.title) |title| {
                try argv.append(allocator, try allocator.dupe(u8, "--title"));
                try argv.append(allocator, try allocator.dupe(u8, title));
            }
            if (options.prompt_label) |label| {
                try argv.append(allocator, try allocator.dupe(u8, "--ok-label"));
                try argv.append(allocator, try allocator.dupe(u8, label));
            }
            if (options.current_directory) |directory| {
                const filename = try std.fmt.allocPrint(allocator, "--filename={s}/", .{trimTrailingSlashes(directory)});
                try argv.append(allocator, filename);
            }
        },
        .unavailable => return error.FileDialogUnavailable,
    }

    return argv;
}

fn buildSavePromptCommand(
    allocator: std.mem.Allocator,
    backend: DialogBackend,
    options: types.LinuxPathPromptOptions,
) !std.ArrayList([]u8) {
    var argv: std.ArrayList([]u8) = .empty;
    errdefer freeArgv(allocator, &argv);

    switch (backend) {
        .kdialog => {
            try argv.append(allocator, try allocator.dupe(u8, "kdialog"));
            try argv.append(allocator, try allocator.dupe(u8, "--getsavefilename"));

            const initial = try buildInitialSavePath(allocator, options);
            if (initial) |path| {
                errdefer allocator.free(path);
                try argv.append(allocator, path);
            }
            if (options.title) |title| {
                try argv.append(allocator, try allocator.dupe(u8, "--title"));
                try argv.append(allocator, try allocator.dupe(u8, title));
            }
        },
        .zenity => {
            const command_name = if (commandAvailable("zenity"))
                "zenity"
            else if (commandAvailable("qarma"))
                "qarma"
            else if (commandAvailable("matedialog"))
                "matedialog"
            else
                return error.FileDialogUnavailable;
            try argv.append(allocator, try allocator.dupe(u8, command_name));
            try argv.append(allocator, try allocator.dupe(u8, "--file-selection"));
            try argv.append(allocator, try allocator.dupe(u8, "--save"));
            try argv.append(allocator, try allocator.dupe(u8, "--confirm-overwrite"));

            if (options.title) |title| {
                try argv.append(allocator, try allocator.dupe(u8, "--title"));
                try argv.append(allocator, try allocator.dupe(u8, title));
            }
            if (options.prompt_label) |label| {
                try argv.append(allocator, try allocator.dupe(u8, "--ok-label"));
                try argv.append(allocator, try allocator.dupe(u8, label));
            }
            if (try buildInitialSavePath(allocator, options)) |path| {
                errdefer allocator.free(path);
                const filename = try std.fmt.allocPrint(allocator, "--filename={s}", .{path});
                allocator.free(path);
                try argv.append(allocator, filename);
            }
        },
        .unavailable => return error.FileDialogUnavailable,
    }

    return argv;
}

fn buildInitialSavePath(
    allocator: std.mem.Allocator,
    options: types.LinuxPathPromptOptions,
) !?[]u8 {
    const directory = options.current_directory orelse return if (options.suggested_name) |name|
        try allocator.dupe(u8, name)
    else
        null;

    if (options.suggested_name) |name| {
        return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ trimTrailingSlashes(directory), name });
    }
    return try std.fmt.allocPrint(allocator, "{s}/", .{trimTrailingSlashes(directory)});
}

fn freeArgv(allocator: std.mem.Allocator, argv: *std.ArrayList([]u8)) void {
    for (argv.items) |arg| allocator.free(arg);
    argv.deinit(allocator);
}

fn runDialog(allocator: std.mem.Allocator, argv: []const []u8) ![]u8 {
    const result = runProcess(allocator, argv) catch |err| switch (err) {
        error.FileNotFound => return error.FileDialogUnavailable,
        else => return err,
    };
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| {
            if (code == 0) return result.stdout;
            allocator.free(result.stdout);
            return if (code == 1) allocator.alloc(u8, 0) else error.FileDialogFailed;
        },
        else => {
            allocator.free(result.stdout);
            return error.FileDialogFailed;
        },
    }
}

fn parsePathsOutput(allocator: std.mem.Allocator, stdout: []const u8) !types.LinuxPathList {
    const trimmed = std.mem.trim(u8, stdout, " \r\n\t");
    if (trimmed.len == 0) return .{ .paths = try allocator.alloc([]u8, 0) };

    var split = std.mem.splitScalar(u8, trimmed, '\n');
    var count: usize = 0;
    while (split.next()) |_| count += 1;

    const paths = try allocator.alloc([]u8, count);
    errdefer {
        for (paths[0..count]) |path| allocator.free(path);
        allocator.free(paths);
    }

    split = std.mem.splitScalar(u8, trimmed, '\n');
    var index: usize = 0;
    while (split.next()) |line| : (index += 1) {
        paths[index] = try allocator.dupe(u8, std.mem.trim(u8, line, " \r\n\t"));
    }

    return .{ .paths = paths };
}

fn runSettingCommand(allocator: std.mem.Allocator, argv: []const []const u8) ?[]u8 {
    const result = runProcess(allocator, argv) catch return null;
    defer allocator.free(result.stderr);

    return switch (result.term) {
        .exited => |code| if (code == 0) result.stdout else blk: {
            allocator.free(result.stdout);
            break :blk null;
        },
        else => blk: {
            allocator.free(result.stdout);
            break :blk null;
        },
    };
}

fn runProcess(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.RunResult {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    return std.process.run(allocator, threaded.io(), .{
        .argv = argv,
    });
}

fn parseAppearance(value: []const u8) types.LinuxWindowAppearance {
    if (std.ascii.indexOfIgnoreCase(value, "dark") != null) return .dark;
    return .light;
}

fn parseButtonLayout(value: []const u8) ?types.LinuxWindowButtonLayout {
    const quoted = parseQuotedSettingValue(value) orelse return null;
    const controls_on_left = std.mem.indexOfScalar(u8, quoted, ':') == null or quoted[0] != ':';
    return .{
        .raw = if (controls_on_left) "close,maximize:minimize" else ":minimize,maximize,close",
        .controls_on_left = controls_on_left,
    };
}

fn parseIntegerSetting(value: []const u8) ?u32 {
    const trimmed = std.mem.trim(u8, value, " \r\n\t");
    return std.fmt.parseUnsigned(u32, trimmed, 10) catch null;
}

fn parseQuotedSetting(
    allocator: std.mem.Allocator,
    value: []const u8,
) !?[]u8 {
    const parsed = parseQuotedSettingValue(value) orelse return null;
    return try allocator.dupe(u8, parsed);
}

fn parseQuotedSettingValue(value: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, value, " \r\n\t");
    if (trimmed.len < 2) return null;
    if ((trimmed[0] == '\'' and trimmed[trimmed.len - 1] == '\'') or
        (trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"'))
    {
        return trimmed[1 .. trimmed.len - 1];
    }
    return null;
}

fn getenvSlice(name: [*:0]const u8) ?[]const u8 {
    const value = std.c.getenv(name) orelse return null;
    return std.mem.span(value);
}

fn trimTrailingSlashes(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 0 and path[end - 1] == '/') end -= 1;
    return path[0..end];
}

fn commandAvailable(name: []const u8) bool {
    const path = getenvSlice("PATH") orelse return false;
    var segments = std.mem.splitScalar(u8, path, ':');
    while (segments.next()) |segment| {
        if (segment.len == 0) continue;
        var buffer: [std.fs.max_path_bytes]u8 = undefined;
        const candidate = std.fmt.bufPrint(&buffer, "{s}/{s}", .{ segment, name }) catch continue;
        const fd = std.posix.openat(std.posix.AT.FDCWD, candidate, .{ .ACCMODE = .RDONLY }, 0) catch continue;
        _ = std.c.close(fd);
        return true;
    }
    return false;
}

test "portal state requires a session bus" {
    const state = PortalState.init(std.testing.allocator, false, true);
    defer {
        var owned = state;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expect(!state.available);
    try std.testing.expect(!state.prefers_portal_open_uri);
}

test "appearance parser detects dark themes" {
    try std.testing.expectEqual(types.LinuxWindowAppearance.dark, parseAppearance("'prefer-dark'"));
    try std.testing.expectEqual(types.LinuxWindowAppearance.light, parseAppearance("'default'"));
}

test "button layout parser tracks left-hand controls" {
    const left = parseButtonLayout("'close,maximize:minimize'").?;
    try std.testing.expect(left.controls_on_left);

    const right = parseButtonLayout("':minimize,maximize,close'").?;
    try std.testing.expect(!right.controls_on_left);
}

test "path output parser splits newline separated results" {
    var list = try parsePathsOutput(std.testing.allocator, "/tmp/a\n/tmp/b\n");
    defer list.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), list.paths.len);
    try std.testing.expectEqualStrings("/tmp/a", list.paths[0]);
    try std.testing.expectEqualStrings("/tmp/b", list.paths[1]);
}

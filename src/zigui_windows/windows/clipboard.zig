const std = @import("std");
const common = @import("../../zigui/common.zig");
const util = @import("util.zig");

pub const ClipboardState = struct {
    clipboard_text: ?[]u8 = null,

    pub fn deinit(self: *ClipboardState, allocator: std.mem.Allocator) void {
        if (self.clipboard_text) |existing| allocator.free(existing);
        self.* = .{};
    }

    pub fn writeTextToClipboard(
        self: *ClipboardState,
        allocator: std.mem.Allocator,
        kind: common.ClipboardKind,
        text: []const u8,
    ) !void {
        if (kind == .primary) return error.NoClipboardSupport;

        const script = try clipboardWriteScript(allocator, text);
        defer allocator.free(script);
        try util.runPowerShellStatus(allocator, script);

        if (self.clipboard_text) |existing| allocator.free(existing);
        self.clipboard_text = try allocator.dupe(u8, text);
    }

    pub fn readTextFromClipboardAlloc(
        self: *ClipboardState,
        allocator: std.mem.Allocator,
        kind: common.ClipboardKind,
        out_allocator: std.mem.Allocator,
    ) ![]u8 {
        if (kind == .primary) return error.NoClipboardSupport;

        const stdout = try util.runPowerShellCapture(allocator, "Get-Clipboard -Raw");
        defer allocator.free(stdout);
        const trimmed = std.mem.trimRight(u8, stdout, "\r\n");
        if (trimmed.len == 0) return error.NoClipboardText;

        if (self.clipboard_text) |existing| allocator.free(existing);
        self.clipboard_text = try allocator.dupe(u8, trimmed);
        return try out_allocator.dupe(u8, trimmed);
    }
};

pub fn openUri(allocator: std.mem.Allocator, uri: []const u8) !void {
    const script = try startProcessScript(allocator, uri);
    defer allocator.free(script);
    try util.runPowerShellStatus(allocator, script);
}

pub fn revealPath(allocator: std.mem.Allocator, path: []const u8) !void {
    const select_arg = try std.fmt.allocPrint(allocator, "/select,{s}", .{path});
    defer allocator.free(select_arg);

    const script = try explorerScript(allocator, select_arg);
    defer allocator.free(script);
    try util.runPowerShellStatus(allocator, script);
}

pub fn promptForPathsAlloc(
    allocator: std.mem.Allocator,
    options: common.PathPromptOptions,
) !?common.PathList {
    const script = try openDialogScript(allocator, options);
    defer allocator.free(script);

    const stdout = try util.runPowerShellCapture(allocator, script);
    defer allocator.free(stdout);
    return try util.parsePathList(allocator, stdout);
}

pub fn promptForNewPathAlloc(
    allocator: std.mem.Allocator,
    options: common.PathPromptOptions,
) !?[]u8 {
    const script = try saveDialogScript(allocator, options);
    defer allocator.free(script);

    const stdout = try util.runPowerShellCapture(allocator, script);
    defer allocator.free(stdout);
    return try util.parseSinglePath(allocator, stdout);
}

fn clipboardWriteScript(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var script: std.ArrayListUnmanaged(u8) = .empty;
    defer script.deinit(allocator);

    try script.appendSlice(allocator, "Set-Clipboard -Value ");
    try util.appendPowerShellLiteral(&script, allocator, text);
    return try script.toOwnedSlice(allocator);
}

fn startProcessScript(allocator: std.mem.Allocator, target: []const u8) ![]u8 {
    var script: std.ArrayListUnmanaged(u8) = .empty;
    defer script.deinit(allocator);

    try script.appendSlice(allocator, "Start-Process ");
    try util.appendPowerShellLiteral(&script, allocator, target);
    return try script.toOwnedSlice(allocator);
}

fn explorerScript(allocator: std.mem.Allocator, select_arg: []const u8) ![]u8 {
    var script: std.ArrayListUnmanaged(u8) = .empty;
    defer script.deinit(allocator);

    try script.appendSlice(allocator, "Start-Process explorer.exe -ArgumentList ");
    try util.appendPowerShellLiteral(&script, allocator, select_arg);
    return try script.toOwnedSlice(allocator);
}

fn openDialogScript(allocator: std.mem.Allocator, options: common.PathPromptOptions) ![]u8 {
    if (options.directories and options.multiple) return error.FileDialogUnavailable;

    var script: std.ArrayListUnmanaged(u8) = .empty;
    defer script.deinit(allocator);
    try script.appendSlice(allocator, "Add-Type -AssemblyName System.Windows.Forms; ");

    if (options.directories) {
        try script.appendSlice(allocator, "$dialog = New-Object System.Windows.Forms.FolderBrowserDialog; ");
        if (options.title) |title| {
            try script.appendSlice(allocator, "$dialog.Description = ");
            try util.appendPowerShellLiteral(&script, allocator, title);
            try script.appendSlice(allocator, "; ");
        }
        if (options.current_directory) |cwd| {
            try script.appendSlice(allocator, "$dialog.SelectedPath = ");
            try util.appendPowerShellLiteral(&script, allocator, cwd);
            try script.appendSlice(allocator, "; ");
        }
        try script.appendSlice(allocator, "if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { [Console]::WriteLine($dialog.SelectedPath) }");
        return try script.toOwnedSlice(allocator);
    }

    try script.appendSlice(allocator, "$dialog = New-Object System.Windows.Forms.OpenFileDialog; ");
    if (options.title) |title| {
        try script.appendSlice(allocator, "$dialog.Title = ");
        try util.appendPowerShellLiteral(&script, allocator, title);
        try script.appendSlice(allocator, "; ");
    }
    if (options.current_directory) |cwd| {
        try script.appendSlice(allocator, "$dialog.InitialDirectory = ");
        try util.appendPowerShellLiteral(&script, allocator, cwd);
        try script.appendSlice(allocator, "; ");
    }
    if (options.suggested_name) |suggested_name| {
        try script.appendSlice(allocator, "$dialog.FileName = ");
        try util.appendPowerShellLiteral(&script, allocator, suggested_name);
        try script.appendSlice(allocator, "; ");
    }
    try script.appendSlice(allocator, "$dialog.Multiselect = ");
    try script.appendSlice(allocator, if (options.multiple) "$true; " else "$false; ");
    try script.appendSlice(allocator, "if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $dialog.FileNames | ForEach-Object { [Console]::WriteLine($_) } }");
    return try script.toOwnedSlice(allocator);
}

fn saveDialogScript(allocator: std.mem.Allocator, options: common.PathPromptOptions) ![]u8 {
    var script: std.ArrayListUnmanaged(u8) = .empty;
    defer script.deinit(allocator);
    try script.appendSlice(allocator, "Add-Type -AssemblyName System.Windows.Forms; $dialog = New-Object System.Windows.Forms.SaveFileDialog; ");

    if (options.title) |title| {
        try script.appendSlice(allocator, "$dialog.Title = ");
        try util.appendPowerShellLiteral(&script, allocator, title);
        try script.appendSlice(allocator, "; ");
    }
    if (options.current_directory) |cwd| {
        try script.appendSlice(allocator, "$dialog.InitialDirectory = ");
        try util.appendPowerShellLiteral(&script, allocator, cwd);
        try script.appendSlice(allocator, "; ");
    }
    if (options.suggested_name) |suggested_name| {
        try script.appendSlice(allocator, "$dialog.FileName = ");
        try util.appendPowerShellLiteral(&script, allocator, suggested_name);
        try script.appendSlice(allocator, "; ");
    }
    try script.appendSlice(allocator, "if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { [Console]::WriteLine($dialog.FileName) }");
    return try script.toOwnedSlice(allocator);
}

test "clipboard script escaping and dialog helpers are wired" {
    const script = try clipboardWriteScript(std.testing.allocator, "O'Brien");
    defer std.testing.allocator.free(script);
    try std.testing.expectEqualStrings("Set-Clipboard -Value 'O''Brien'", script);

    const open_script = try openDialogScript(std.testing.allocator, .{ .directories = true });
    defer std.testing.allocator.free(open_script);
    try std.testing.expect(std.mem.indexOf(u8, open_script, "FolderBrowserDialog") != null);
}

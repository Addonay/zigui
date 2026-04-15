const builtin = @import("builtin");
const std = @import("std");
const common = @import("../../zigui/common.zig");

pub fn appendPowerShellLiteral(
    builder: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,
    value: []const u8,
) !void {
    try builder.append(allocator, '\'');
    for (value) |byte| {
        if (byte == '\'') {
            try builder.appendSlice(allocator, "''");
        } else {
            try builder.append(allocator, byte);
        }
    }
    try builder.append(allocator, '\'');
}

pub fn runProcess(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.RunResult {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    return std.process.run(allocator, threaded.io(), .{
        .argv = argv,
    });
}

pub fn runPowerShellCapture(allocator: std.mem.Allocator, script: []const u8) ![]u8 {
    if (builtin.os.tag != .windows) return error.UnsupportedPlatform;

    const result = try runProcess(allocator, &.{
        "powershell.exe",
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        script,
    });
    defer allocator.free(result.stderr);

    return switch (result.term) {
        .exited => |code| if (code == 0) result.stdout else blk: {
            allocator.free(result.stdout);
            break :blk error.ProcessExitedNonZero;
        },
        else => blk: {
            allocator.free(result.stdout);
            break :blk error.ProcessExitedNonZero;
        },
    };
}

pub fn runPowerShellStatus(allocator: std.mem.Allocator, script: []const u8) !void {
    const stdout = try runPowerShellCapture(allocator, script);
    allocator.free(stdout);
}

pub fn parsePathList(allocator: std.mem.Allocator, stdout: []const u8) !?common.PathList {
    const trimmed = std.mem.trim(u8, stdout, " \r\n\t");
    if (trimmed.len == 0) return null;

    var count: usize = 0;
    var counter = std.mem.splitScalar(u8, trimmed, '\n');
    while (counter.next()) |_| count += 1;

    const paths = try allocator.alloc([]u8, count);
    var initialized: usize = 0;
    errdefer {
        for (paths[0..initialized]) |path| allocator.free(path);
        allocator.free(paths);
    }

    var split = std.mem.splitScalar(u8, trimmed, '\n');
    var index: usize = 0;
    while (split.next()) |line| : (index += 1) {
        paths[index] = try allocator.dupe(u8, std.mem.trimRight(u8, line, "\r"));
        initialized += 1;
    }

    return .{ .paths = paths };
}

pub fn parseSinglePath(allocator: std.mem.Allocator, stdout: []const u8) !?[]u8 {
    const trimmed = std.mem.trim(u8, stdout, " \r\n\t");
    if (trimmed.len == 0) return null;
    return try allocator.dupe(u8, trimmed);
}

test "powershell literal escaping doubles apostrophes" {
    var builder: std.ArrayListUnmanaged(u8) = .empty;
    defer builder.deinit(std.testing.allocator);

    try appendPowerShellLiteral(&builder, std.testing.allocator, "O'Brien");
    const owned = try builder.toOwnedSlice(std.testing.allocator);
    defer std.testing.allocator.free(owned);

    try std.testing.expectEqualStrings("'O''Brien'", owned);
}

test "path list parsing returns newline-delimited selections" {
    const parsed = (try parsePathList(std.testing.allocator, "C:\\a\nC:\\b\r\n")).?;
    defer {
        var owned = parsed;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), parsed.paths.len);
    try std.testing.expectEqualStrings("C:\\a", parsed.paths[0]);
    try std.testing.expectEqualStrings("C:\\b", parsed.paths[1]);
}

test "single path parsing trims surrounding whitespace" {
    const parsed = (try parseSinglePath(std.testing.allocator, "  C:\\path\\file.txt\r\n")).?;
    defer std.testing.allocator.free(parsed);

    try std.testing.expectEqualStrings("C:\\path\\file.txt", parsed);
}

test "powershell capture rejects unsupported platforms" {
    if (builtin.os.tag != .windows) {
        try std.testing.expectError(
            error.UnsupportedPlatform,
            runPowerShellCapture(std.testing.allocator, "Write-Output 'test'"),
        );
    }
}

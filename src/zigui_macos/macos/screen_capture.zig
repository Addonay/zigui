const std = @import("std");
const display = @import("display.zig");

pub const ScreenCaptureMetadata = struct {
    id: u64 = 0,
    label: ?[]const u8 = null,
    is_main: bool = false,
    width: u32 = 0,
    height: u32 = 0,
};

pub const MacScreenCaptureSource = struct {
    display_id: usize = 0,
    label: ?[]const u8 = null,
    is_main: bool = false,
    width: u32 = 0,
    height: u32 = 0,

    pub fn metadata(self: *const MacScreenCaptureSource) ScreenCaptureMetadata {
        return .{
            .id = self.display_id,
            .label = self.label,
            .is_main = self.is_main,
            .width = self.width,
            .height = self.height,
        };
    }

    pub fn stream(self: *const MacScreenCaptureSource) MacScreenCaptureStream {
        return .{
            .meta = self.metadata(),
        };
    }
};

pub const MacScreenCaptureStream = struct {
    meta: ScreenCaptureMetadata = .{},
    active: bool = false,
    frame_count: usize = 0,

    pub fn metadata(self: *const MacScreenCaptureStream) ScreenCaptureMetadata {
        return self.meta;
    }

    pub fn start(self: *MacScreenCaptureStream) void {
        self.active = true;
    }

    pub fn stop(self: *MacScreenCaptureStream) void {
        self.active = false;
    }

    pub fn emitFrame(self: *MacScreenCaptureStream) void {
        if (self.active) {
            self.frame_count += 1;
        }
    }
};

pub const ScreenCaptureState = struct {
    last_source_count: usize = 0,
    last_stream_count: usize = 0,

    pub fn refresh(self: *ScreenCaptureState, display_state: *const display.DisplayState) void {
        self.last_source_count = display_state.count();
    }

    pub fn noteStream(self: *ScreenCaptureState) void {
        self.last_stream_count += 1;
    }
};

pub fn getSourcesAlloc(
    display_state: *const display.DisplayState,
    allocator: std.mem.Allocator,
) ![]MacScreenCaptureSource {
    const infos = try display_state.infosAlloc(allocator);
    defer allocator.free(infos);

    const sources = try allocator.alloc(MacScreenCaptureSource, infos.len);
    for (infos, 0..) |info, index| {
        sources[index] = .{
            .display_id = info.id,
            .label = info.name,
            .is_main = info.is_primary,
            .width = @intCast(info.width),
            .height = @intCast(info.height),
        };
    }

    return sources;
}

test "screen capture sources reflect display state" {
    const display_state = display.DisplayState.init(.{ .width = 1440, .height = 900 });
    const sources = try getSourcesAlloc(&display_state, std.testing.allocator);
    defer std.testing.allocator.free(sources);

    try std.testing.expectEqual(@as(usize, 1), sources.len);
    try std.testing.expect(sources[0].is_main);

    var stream = sources[0].stream();
    try std.testing.expectEqual(@as(u64, sources[0].display_id), stream.metadata().id);
    stream.start();
    stream.emitFrame();
    try std.testing.expectEqual(@as(usize, 1), stream.frame_count);
}

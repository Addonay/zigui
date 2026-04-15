const std = @import("std");

pub const TaskId = enum(u64) {
    _,
};

pub const TaskKind = enum {
    wake,
    redraw,
    quit,
};

pub const PostedTask = struct {
    id: TaskId,
    kind: TaskKind,
};

pub const LoopMode = enum {
    polling,
    event_driven,
};

pub const DispatcherConfig = struct {
    mode: LoopMode = .event_driven,
    max_pending_tasks: usize = 1024,
};

pub const MacDispatcher = struct {
    config: DispatcherConfig = .{},
    owns_run_loop: bool = true,
    wakes_requested: usize = 0,
    next_task_id: u64 = 1,
    pending: std.ArrayListUnmanaged(PostedTask) = .empty,

    pub fn isMainThread(self: *const MacDispatcher) bool {
        _ = self;
        return true;
    }

    pub fn requestWake(self: *MacDispatcher) void {
        self.wakes_requested += 1;
    }

    pub fn post(self: *MacDispatcher, allocator: std.mem.Allocator, kind: TaskKind) !TaskId {
        const task_id: TaskId = @enumFromInt(self.next_task_id);
        self.next_task_id += 1;

        try self.pending.append(allocator, .{
            .id = task_id,
            .kind = kind,
        });

        if (kind == .wake or kind == .redraw) {
            self.requestWake();
        }

        return task_id;
    }

    pub fn drain(self: *MacDispatcher) []PostedTask {
        const tasks = self.pending.items;
        self.pending.clearRetainingCapacity();
        return tasks;
    }

    pub fn pendingCount(self: *const MacDispatcher) usize {
        return self.pending.items.len;
    }

    pub fn deinit(self: *MacDispatcher, allocator: std.mem.Allocator) void {
        self.pending.deinit(allocator);
    }
};

pub const Dispatcher = MacDispatcher;

test "dispatcher tracks wake requests" {
    var dispatcher = MacDispatcher{};
    defer dispatcher.deinit(std.testing.allocator);

    dispatcher.requestWake();
    try std.testing.expectEqual(@as(usize, 1), dispatcher.wakes_requested);
    try std.testing.expect(dispatcher.isMainThread());
}

test "dispatcher stores posted tasks" {
    var dispatcher = MacDispatcher{};
    defer dispatcher.deinit(std.testing.allocator);

    const task_id = try dispatcher.post(std.testing.allocator, .redraw);
    try std.testing.expectEqual(@as(u64, 1), @intFromEnum(task_id));
    try std.testing.expectEqual(@as(usize, 1), dispatcher.pendingCount());
    try std.testing.expectEqual(@as(usize, 1), dispatcher.wakes_requested);

    const tasks = dispatcher.drain();
    try std.testing.expectEqual(@as(usize, 1), tasks.len);
}

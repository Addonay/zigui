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

pub const Dispatcher = struct {
    config: DispatcherConfig = .{},
    owns_message_loop: bool = true,
    wakes_requested: usize = 0,
    next_task_id: u64 = 1,
    pending: std.ArrayListUnmanaged(PostedTask) = .empty,

    pub fn requestWake(self: *Dispatcher) void {
        self.wakes_requested += 1;
    }

    pub fn post(self: *Dispatcher, allocator: std.mem.Allocator, kind: TaskKind) !TaskId {
        const task_id: TaskId = @enumFromInt(self.next_task_id);
        self.next_task_id += 1;
        try self.pending.append(allocator, .{
            .id = task_id,
            .kind = kind,
        });
        if (kind == .wake or kind == .redraw) self.requestWake();
        return task_id;
    }

    pub fn drain(self: *Dispatcher) []PostedTask {
        const tasks = self.pending.items;
        self.pending.clearRetainingCapacity();
        return tasks;
    }

    pub fn pendingCount(self: *const Dispatcher) usize {
        return self.pending.items.len;
    }

    pub fn deinit(self: *Dispatcher, allocator: std.mem.Allocator) void {
        self.pending.deinit(allocator);
    }
};

pub const WindowsDispatcher = Dispatcher;

test "dispatcher stores posted tasks" {
    var instance = Dispatcher{};
    defer instance.deinit(std.testing.allocator);

    const task_id = try instance.post(std.testing.allocator, .redraw);
    try std.testing.expectEqual(@as(u64, 1), @intFromEnum(task_id));
    try std.testing.expectEqual(@as(usize, 1), instance.pendingCount());
}

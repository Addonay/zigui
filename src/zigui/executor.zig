pub const TaskId = enum(u64) {
    _,
};

pub const ExecutorConfig = struct {
    integrate_with_event_loop: bool = true,
};

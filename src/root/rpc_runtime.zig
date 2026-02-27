const std = @import("std");
const bridge_template = @import("../bridge/template.zig");
const api_types = @import("api_types.zig");
const logging = @import("logging.zig");

pub const HandlerEntry = struct {
    name: []u8,
    arity: usize,
    invoker: api_types.RpcInvokeFn,
    ts_arg_signature: []u8,
    ts_return_type: []u8,
};

const Task = struct {
    allocator: std.mem.Allocator,
    payload_json: []u8,
    done: bool = false,
    result_json: ?[]u8 = null,
    err: ?anyerror = null,
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},

    fn init(allocator: std.mem.Allocator, payload_json: []const u8) !*Task {
        const task = try allocator.create(Task);
        task.* = .{
            .allocator = allocator,
            .payload_json = try allocator.dupe(u8, payload_json),
        };
        return task;
    }

    fn deinit(self: *Task) void {
        self.allocator.free(self.payload_json);
        if (self.result_json) |result| self.allocator.free(result);
        self.allocator.destroy(self);
    }
};

pub const State = struct {
    pub const LogConfig = struct {
        enabled: bool = false,
        sink: logging.Sink = .{},
    };

    handlers: std.array_list.Managed(HandlerEntry),
    generated_script: []const u8,
    generated_typescript: []const u8,
    bridge_options: api_types.BridgeOptions,
    dispatcher_mode: api_types.DispatcherMode,
    custom_dispatcher: ?api_types.CustomDispatcher,
    custom_context: ?*anyopaque,
    threaded_poll_interval_ns: u64,
    invoke_mutex: std.Thread.Mutex,

    queue_mutex: std.Thread.Mutex,
    queue_cond: std.Thread.Condition,
    queue: std.array_list.Managed(*Task),
    worker_thread: ?std.Thread,
    worker_stop: std.atomic.Value(bool),
    worker_lifecycle_mutex: std.Thread.Mutex,
    log_enabled: bool,
    log_sink: logging.Sink,

    pub fn init(allocator: std.mem.Allocator, log_config: LogConfig) State {
        return .{
            .handlers = std.array_list.Managed(HandlerEntry).init(allocator),
            .generated_script = bridge_template.default_script,
            .generated_typescript = "export interface WebuiRpcClient {}\n",
            .bridge_options = .{},
            .dispatcher_mode = .sync,
            .custom_dispatcher = null,
            .custom_context = null,
            .threaded_poll_interval_ns = 2 * std.time.ns_per_ms,
            .invoke_mutex = .{},
            .queue_mutex = .{},
            .queue_cond = .{},
            .queue = std.array_list.Managed(*Task).init(allocator),
            .worker_thread = null,
            .worker_stop = std.atomic.Value(bool).init(false),
            .worker_lifecycle_mutex = .{},
            .log_enabled = log_config.enabled,
            .log_sink = log_config.sink,
        };
    }

    pub inline fn logf(self: *const State, level: logging.Level, comptime fmt: []const u8, args: anytype) void {
        logging.emitf(self.log_sink, self.log_enabled, level, fmt, args);
    }

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        self.stopWorker();

        self.queue_mutex.lock();
        while (self.queue.items.len > 0) {
            const task = self.queue.items[self.queue.items.len - 1];
            _ = self.queue.pop();
            task.deinit();
        }
        self.queue_mutex.unlock();
        self.queue.deinit();

        for (self.handlers.items) |handler| {
            allocator.free(handler.name);
            allocator.free(handler.ts_arg_signature);
            allocator.free(handler.ts_return_type);
        }
        self.handlers.deinit();
    }

    pub fn addFunction(
        self: *State,
        allocator: std.mem.Allocator,
        function_name: []const u8,
        arity: usize,
        invoker: api_types.RpcInvokeFn,
        ts_arg_signature: []const u8,
        ts_return_type: []const u8,
    ) !void {
        for (self.handlers.items) |*existing| {
            if (std.mem.eql(u8, existing.name, function_name)) {
                existing.arity = arity;
                existing.invoker = invoker;
                allocator.free(existing.ts_arg_signature);
                allocator.free(existing.ts_return_type);
                existing.ts_arg_signature = try allocator.dupe(u8, ts_arg_signature);
                existing.ts_return_type = try allocator.dupe(u8, ts_return_type);
                return;
            }
        }

        try self.handlers.append(.{
            .name = try allocator.dupe(u8, function_name),
            .arity = arity,
            .invoker = invoker,
            .ts_arg_signature = try allocator.dupe(u8, ts_arg_signature),
            .ts_return_type = try allocator.dupe(u8, ts_return_type),
        });
    }

    fn findHandler(self: *const State, function_name: []const u8) ?HandlerEntry {
        for (self.handlers.items) |handler| {
            if (std.mem.eql(u8, handler.name, function_name)) return handler;
        }
        return null;
    }

    fn invokeSync(
        self: *State,
        allocator: std.mem.Allocator,
        function_name: []const u8,
        args: []const std.json.Value,
    ) ![]u8 {
        const handler = self.findHandler(function_name) orelse return error.UnknownRpcFunction;

        if (self.dispatcher_mode == .custom and self.custom_dispatcher != null) {
            return try self.custom_dispatcher.?(self.custom_context, function_name, handler.invoker, allocator, args);
        }

        return try handler.invoker(allocator, args);
    }

    pub fn ensureWorkerStarted(self: *State) !void {
        self.worker_lifecycle_mutex.lock();
        defer self.worker_lifecycle_mutex.unlock();

        if (self.dispatcher_mode != .threaded) return;
        if (self.worker_thread != null) return;

        self.worker_stop.store(false, .release);
        self.worker_thread = try std.Thread.spawn(.{}, rpcWorkerMain, .{self});
    }

    fn stopWorker(self: *State) void {
        self.worker_lifecycle_mutex.lock();
        defer self.worker_lifecycle_mutex.unlock();

        self.worker_stop.store(true, .release);
        self.queue_cond.broadcast();
        if (self.worker_thread) |thread| {
            thread.join();
            self.worker_thread = null;
        }
    }

    pub fn invokeFromJsonPayload(self: *State, allocator: std.mem.Allocator, payload_json: []const u8) ![]u8 {
        if (self.dispatcher_mode != .threaded) {
            return try self.invokeFromJsonPayloadSync(allocator, payload_json);
        }

        try self.ensureWorkerStarted();

        const task = try Task.init(allocator, payload_json);
        errdefer task.deinit();

        self.queue_mutex.lock();
        try self.queue.append(task);
        self.queue_cond.signal();
        self.queue_mutex.unlock();

        task.mutex.lock();
        const wait_ns = if (self.threaded_poll_interval_ns == 0) std.time.ns_per_ms else self.threaded_poll_interval_ns;
        while (!task.done) {
            task.cond.timedWait(&task.mutex, wait_ns) catch {};
        }

        if (task.err) |err| {
            task.mutex.unlock();
            return err;
        }

        const out = task.result_json orelse {
            task.mutex.unlock();
            return error.InvalidRpcResult;
        };
        const result = try allocator.dupe(u8, out);
        task.mutex.unlock();
        task.deinit();
        return result;
    }

    fn invokeFromJsonPayloadSync(self: *State, allocator: std.mem.Allocator, payload_json: []const u8) ![]u8 {
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, payload_json, .{}) catch {
            return error.InvalidRpcPayload;
        };
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.InvalidRpcPayload;

        const fn_value = root.object.get("name") orelse return error.InvalidRpcPayload;
        if (fn_value != .string) return error.InvalidRpcPayload;
        const function_name = fn_value.string;

        const args_value = root.object.get("args") orelse return error.InvalidRpcPayload;
        if (args_value != .array) return error.InvalidRpcPayload;

        if (self.log_enabled) {
            const args_json = try std.json.Stringify.valueAlloc(allocator, args_value, .{});
            defer allocator.free(args_json);
            self.logf(.debug, "[webui.rpc] recv name={s} args={s}\n", .{ function_name, args_json });
        }

        const encoded_value = try self.invokeSync(allocator, function_name, args_value.array.items);
        errdefer allocator.free(encoded_value);

        self.logf(.debug, "[webui.rpc] send name={s} value={s}\n", .{ function_name, encoded_value });
        return encoded_value;
    }

    fn rpcWorkerMain(self: *State) void {
        const poll_ns = if (self.threaded_poll_interval_ns == 0) std.time.ns_per_ms else self.threaded_poll_interval_ns;
        while (!self.worker_stop.load(.acquire)) {
            self.queue_mutex.lock();
            while (self.queue.items.len == 0 and !self.worker_stop.load(.acquire)) {
                self.queue_cond.timedWait(&self.queue_mutex, poll_ns) catch {};
            }

            const task = if (self.queue.items.len == 0) null else blk: {
                const popped = self.queue.orderedRemove(0);
                break :blk popped;
            };
            self.queue_mutex.unlock();

            if (task == null) continue;
            const work = task.?;

            const result = self.invokeFromJsonPayloadSync(work.allocator, work.payload_json) catch |err| {
                work.mutex.lock();
                work.err = err;
                work.done = true;
                work.cond.signal();
                work.mutex.unlock();
                continue;
            };

            work.mutex.lock();
            work.result_json = result;
            work.done = true;
            work.cond.signal();
            work.mutex.unlock();
        }
    }
};

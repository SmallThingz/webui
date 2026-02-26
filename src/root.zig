const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const bridge_template = @import("bridge/template.zig");
const bridge_runtime_helpers = @import("bridge/runtime_helpers.zig");
const core_runtime = @import("ported/webui.zig");
const browser_discovery = @import("ported/browser_discovery.zig");
const civetweb = @import("ported/civetweb/civetweb.zig");
pub const process_signals = @import("process_signals.zig");
const window_style_types = @import("window_style.zig");
const webview_backend = @import("ported/webview/backend.zig");

pub const runtime = core_runtime;
pub const http = civetweb;
pub const runtime_helpers_js = bridge_runtime_helpers.embedded_runtime_helpers_js;
pub const runtime_helpers_js_written = bridge_runtime_helpers.written_runtime_helpers_js;
pub const BrowserPromptPreset = core_runtime.BrowserPromptPreset;
pub const BrowserPromptPolicy = core_runtime.BrowserPromptPolicy;
pub const BrowserLaunchOptions = core_runtime.BrowserLaunchOptions;

pub const Size = window_style_types.Size;
pub const Point = window_style_types.Point;
pub const WindowIcon = window_style_types.WindowIcon;
pub const WindowStyle = window_style_types.WindowStyle;
pub const WindowControl = window_style_types.WindowControl;
pub const WindowCapability = window_style_types.WindowCapability;
pub const CloseHandler = window_style_types.CloseHandler;

pub const BuildFlags = struct {
    pub const dynamic = build_options.dynamic;
    pub const enable_tls = build_options.enable_tls;
    pub const enable_webui_log = build_options.enable_webui_log;
    pub const run_mode = build_options.run_mode;
};

pub const DispatcherMode = enum {
    sync,
    threaded,
    custom,
};

pub const TransportMode = enum {
    browser_fallback,
    native_webview,
};

pub const EventKind = enum {
    connected,
    disconnected,
    navigation,
    rpc,
    raw,
    window_state,
    window_capability,
    close_requested,
};

pub const BridgeOptions = struct {
    namespace: []const u8 = "webuiRpc",
    script_route: []const u8 = "/webui_bridge.js",
    rpc_route: []const u8 = "/webui/rpc",
};

pub const Event = struct {
    window_id: usize,
    kind: EventKind,
    name: []const u8,
    payload: []const u8,
};

pub const EventHandler = *const fn (context: ?*anyopaque, event: *const Event) void;
pub const RawHandler = *const fn (context: ?*anyopaque, bytes: []const u8) void;

pub const RpcInvokeFn = *const fn (allocator: std.mem.Allocator, args: []const std.json.Value) anyerror![]u8;
pub const CustomDispatcher = *const fn (
    context: ?*anyopaque,
    function_name: []const u8,
    invoker: RpcInvokeFn,
    allocator: std.mem.Allocator,
    args: []const std.json.Value,
) anyerror![]u8;

pub const RpcOptions = struct {
    dispatcher_mode: DispatcherMode = .sync,
    custom_dispatcher: ?CustomDispatcher = null,
    custom_context: ?*anyopaque = null,
    bridge_options: BridgeOptions = .{},
    threaded_poll_interval_ns: u64 = 2 * std.time.ns_per_ms,
};

pub const AppOptions = struct {
    transport_mode: TransportMode = .browser_fallback,
    enable_tls: bool = build_options.enable_tls,
    enable_webui_log: bool = build_options.enable_webui_log,
    auto_open_browser: bool = false,
    browser_launch: BrowserLaunchOptions = .{},
    browser_fallback_on_native_failure: bool = true,
    window_fallback_emulation: bool = true,
};

pub const WindowOptions = struct {
    window_id: ?usize = null,
    title: []const u8 = "WebUI Zig",
    style: WindowStyle = .{},
};

pub const WindowContent = union(enum) {
    html: []const u8,
    file: []const u8,
    url: []const u8,
};

pub const WindowControlResult = struct {
    success: bool = true,
    emulation: ?[]const u8 = null,
    closed: bool = false,
    warning: ?[]const u8 = null,
};

pub const ServiceOptions = struct {
    app: AppOptions = .{},
    window: WindowOptions = .{},
    rpc: RpcOptions = .{},
};

const EventCallbackState = struct {
    handler: ?EventHandler = null,
    context: ?*anyopaque = null,
};

const RawCallbackState = struct {
    handler: ?RawHandler = null,
    context: ?*anyopaque = null,
};

const CloseCallbackState = struct {
    handler: ?CloseHandler = null,
    context: ?*anyopaque = null,
};

const LifecycleConfig = struct {
    enable_heartbeat: bool,
    heartbeat_interval_ms: u32,
    heartbeat_hidden_interval_ms: u32,
    heartbeat_timeout_ms: u32,
    heartbeat_failures_before_close: u8,
    heartbeat_initial_delay_ms: u32,
};

const lifecycle_child_process_config = LifecycleConfig{
    .enable_heartbeat = false,
    .heartbeat_interval_ms = 0,
    .heartbeat_hidden_interval_ms = 0,
    .heartbeat_timeout_ms = 0,
    .heartbeat_failures_before_close = 0,
    .heartbeat_initial_delay_ms = 0,
};

const lifecycle_fallback_config = LifecycleConfig{
    .enable_heartbeat = true,
    .heartbeat_interval_ms = 1_200,
    .heartbeat_hidden_interval_ms = 3_000,
    .heartbeat_timeout_ms = 500,
    .heartbeat_failures_before_close = 2,
    .heartbeat_initial_delay_ms = 400,
};

fn backendWarningForError(err: anyerror, will_fallback: bool) ?[]const u8 {
    return switch (err) {
        error.NativeBackendUnavailable => if (will_fallback)
            "native backend is unavailable on this target/runtime; falling back to browser emulation"
        else
            "native backend is unavailable on this target/runtime and no emulation fallback is enabled",
        error.UnsupportedWindowStyle => if (will_fallback)
            "requested window style is unsupported by the native backend on this target; falling back to browser emulation"
        else
            "requested window style is unsupported by the native backend on this target and no emulation fallback is enabled",
        error.UnsupportedWindowControl => if (will_fallback)
            "requested window control is unsupported by the native backend on this target; falling back to browser emulation"
        else
            "requested window control is unsupported by the native backend on this target and no emulation fallback is enabled",
        error.UnsupportedWindowCapability => if (will_fallback)
            "requested native capability is unavailable on this target; falling back to browser emulation"
        else
            "requested native capability is unavailable on this target and no emulation fallback is enabled",
        else => null,
    };
}

const RpcHandlerEntry = struct {
    name: []u8,
    arity: usize,
    invoker: RpcInvokeFn,
    ts_arg_signature: []u8,
    ts_return_type: []u8,
};

const RpcTask = struct {
    allocator: std.mem.Allocator,
    payload_json: []u8,
    done: bool = false,
    result_json: ?[]u8 = null,
    err: ?anyerror = null,
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},

    fn init(allocator: std.mem.Allocator, payload_json: []const u8) !*RpcTask {
        const task = try allocator.create(RpcTask);
        task.* = .{
            .allocator = allocator,
            .payload_json = try allocator.dupe(u8, payload_json),
        };
        return task;
    }

    fn deinit(self: *RpcTask) void {
        self.allocator.free(self.payload_json);
        if (self.result_json) |result| self.allocator.free(result);
        self.allocator.destroy(self);
    }
};

const RpcRegistryState = struct {
    handlers: std.array_list.Managed(RpcHandlerEntry),
    generated_script: ?[]u8,
    generated_typescript: ?[]u8,
    bridge_options: BridgeOptions,
    dispatcher_mode: DispatcherMode,
    custom_dispatcher: ?CustomDispatcher,
    custom_context: ?*anyopaque,
    threaded_poll_interval_ns: u64,

    queue_mutex: std.Thread.Mutex,
    queue_cond: std.Thread.Condition,
    queue: std.array_list.Managed(*RpcTask),
    worker_thread: ?std.Thread,
    worker_stop: std.atomic.Value(bool),
    log_enabled: bool,

    fn init(allocator: std.mem.Allocator, log_enabled: bool) RpcRegistryState {
        return .{
            .handlers = std.array_list.Managed(RpcHandlerEntry).init(allocator),
            .generated_script = null,
            .generated_typescript = null,
            .bridge_options = .{},
            .dispatcher_mode = .sync,
            .custom_dispatcher = null,
            .custom_context = null,
            .threaded_poll_interval_ns = 2 * std.time.ns_per_ms,
            .queue_mutex = .{},
            .queue_cond = .{},
            .queue = std.array_list.Managed(*RpcTask).init(allocator),
            .worker_thread = null,
            .worker_stop = std.atomic.Value(bool).init(false),
            .log_enabled = log_enabled,
        };
    }

    fn deinit(self: *RpcRegistryState, allocator: std.mem.Allocator) void {
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

        if (self.generated_script) |buf| {
            allocator.free(buf);
            self.generated_script = null;
        }
        if (self.generated_typescript) |buf| {
            allocator.free(buf);
            self.generated_typescript = null;
        }
    }

    fn addFunction(
        self: *RpcRegistryState,
        allocator: std.mem.Allocator,
        function_name: []const u8,
        arity: usize,
        invoker: RpcInvokeFn,
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
                if (self.generated_script) |buf| {
                    allocator.free(buf);
                    self.generated_script = null;
                }
                if (self.generated_typescript) |buf| {
                    allocator.free(buf);
                    self.generated_typescript = null;
                }
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

        if (self.generated_script) |buf| {
            allocator.free(buf);
            self.generated_script = null;
        }
        if (self.generated_typescript) |buf| {
            allocator.free(buf);
            self.generated_typescript = null;
        }
    }

    fn rebuildScript(self: *RpcRegistryState, allocator: std.mem.Allocator, options: BridgeOptions) !void {
        self.bridge_options = options;

        if (self.generated_script) |buf| {
            allocator.free(buf);
            self.generated_script = null;
        }

        const metas = try allocator.alloc(bridge_template.RpcFunctionMeta, self.handlers.items.len);
        defer allocator.free(metas);

        for (self.handlers.items, 0..) |handler, i| {
            metas[i] = .{
                .name = handler.name,
                .arity = handler.arity,
                .ts_arg_signature = handler.ts_arg_signature,
                .ts_return_type = handler.ts_return_type,
            };
        }

        self.generated_script = try bridge_template.render(allocator, .{
            .namespace = options.namespace,
            .rpc_route = options.rpc_route,
        }, metas);
    }

    fn rebuildTypeScript(self: *RpcRegistryState, allocator: std.mem.Allocator, options: BridgeOptions) !void {
        self.bridge_options = options;

        if (self.generated_typescript) |buf| {
            allocator.free(buf);
            self.generated_typescript = null;
        }

        const metas = try allocator.alloc(bridge_template.RpcFunctionMeta, self.handlers.items.len);
        defer allocator.free(metas);

        for (self.handlers.items, 0..) |handler, i| {
            metas[i] = .{
                .name = handler.name,
                .arity = handler.arity,
                .ts_arg_signature = handler.ts_arg_signature,
                .ts_return_type = handler.ts_return_type,
            };
        }

        self.generated_typescript = try bridge_template.renderTypeScriptDeclarations(allocator, .{
            .namespace = options.namespace,
            .rpc_route = options.rpc_route,
        }, metas);
    }

    fn findHandler(self: *const RpcRegistryState, function_name: []const u8) ?RpcHandlerEntry {
        for (self.handlers.items) |handler| {
            if (std.mem.eql(u8, handler.name, function_name)) return handler;
        }
        return null;
    }

    fn invokeSync(
        self: *RpcRegistryState,
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

    fn ensureWorkerStarted(self: *RpcRegistryState) !void {
        if (self.dispatcher_mode != .threaded) return;
        if (self.worker_thread != null) return;

        self.worker_stop.store(false, .release);
        self.worker_thread = try std.Thread.spawn(.{}, rpcWorkerMain, .{self});
    }

    fn stopWorker(self: *RpcRegistryState) void {
        self.worker_stop.store(true, .release);
        self.queue_cond.broadcast();
        if (self.worker_thread) |thread| {
            thread.join();
            self.worker_thread = null;
        }
    }

    fn invokeFromJsonPayload(self: *RpcRegistryState, allocator: std.mem.Allocator, payload_json: []const u8) ![]u8 {
        if (self.dispatcher_mode != .threaded) {
            return try self.invokeFromJsonPayloadSync(allocator, payload_json);
        }

        try self.ensureWorkerStarted();

        const task = try RpcTask.init(allocator, payload_json);
        errdefer task.deinit();

        self.queue_mutex.lock();
        try self.queue.append(task);
        self.queue_cond.signal();
        self.queue_mutex.unlock();

        task.mutex.lock();
        defer task.mutex.unlock();
        const wait_ns = if (self.threaded_poll_interval_ns == 0) std.time.ns_per_ms else self.threaded_poll_interval_ns;
        while (!task.done) {
            task.cond.timedWait(&task.mutex, wait_ns) catch {};
        }

        if (task.err) |err| {
            task.deinit();
            return err;
        }

        const out = task.result_json orelse return error.InvalidRpcResult;
        const result = try allocator.dupe(u8, out);
        task.deinit();
        return result;
    }

    fn invokeFromJsonPayloadSync(self: *RpcRegistryState, allocator: std.mem.Allocator, payload_json: []const u8) ![]u8 {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload_json, .{});
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
            std.debug.print("[webui.rpc] recv name={s} args={s}\n", .{ function_name, args_json });
        }

        const encoded_value = try self.invokeSync(allocator, function_name, args_value.array.items);
        defer allocator.free(encoded_value);

        if (self.log_enabled) {
            std.debug.print("[webui.rpc] send name={s} value={s}\n", .{ function_name, encoded_value });
        }

        var out = std.array_list.Managed(u8).init(allocator);
        errdefer out.deinit();

        try out.appendSlice("{\"value\":");
        try out.appendSlice(encoded_value);
        try out.appendSlice("}");

        return out.toOwnedSlice();
    }

    fn rpcWorkerMain(self: *RpcRegistryState) void {
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

const WindowState = struct {
    id: usize,
    title: []u8,
    transport_mode: TransportMode,
    window_fallback_emulation: bool,
    server_port: u16,
    last_html: ?[]u8,
    last_file: ?[]u8,
    last_url: ?[]u8,
    shown: bool,
    connected_emitted: bool,
    event_callback: EventCallbackState,
    raw_callback: RawCallbackState,
    close_callback: CloseCallbackState,
    rpc_state: RpcRegistryState,
    backend: webview_backend.NativeBackend,
    native_capabilities: []const WindowCapability,
    current_style: WindowStyle,
    style_icon_bytes: ?[]u8,
    style_icon_mime: ?[]u8,
    launched_browser_pid: ?i64,
    launched_browser_kind: ?browser_discovery.BrowserKind,
    launched_browser_is_child: bool,
    launched_browser_lifecycle_linked: bool,
    launched_browser_profile_dir: ?[]u8,
    last_warning: ?[]const u8,

    state_mutex: std.Thread.Mutex,
    server_thread: ?std.Thread,
    server_stop: std.atomic.Value(bool),
    server_ready_mutex: std.Thread.Mutex,
    server_ready_cond: std.Thread.Condition,
    server_ready: bool,
    server_listen_ok: bool,
    close_requested: std.atomic.Value(bool),

    const emulated_capabilities = [_]WindowCapability{
        .native_frameless,
        .native_transparency,
        .native_corner_radius,
        .native_minmax,
        .native_kiosk,
    };

    fn init(allocator: std.mem.Allocator, id: usize, options: WindowOptions, app_options: AppOptions) !WindowState {
        var state: WindowState = .{
            .id = id,
            .title = try allocator.dupe(u8, options.title),
            .transport_mode = app_options.transport_mode,
            .window_fallback_emulation = app_options.window_fallback_emulation,
            .server_port = core_runtime.nextFallbackPort(id),
            .last_html = null,
            .last_file = null,
            .last_url = null,
            .shown = false,
            .connected_emitted = false,
            .event_callback = .{},
            .raw_callback = .{},
            .close_callback = .{},
            .rpc_state = RpcRegistryState.init(allocator, app_options.enable_webui_log),
            .backend = webview_backend.NativeBackend.init(app_options.transport_mode == .native_webview),
            .native_capabilities = &.{},
            .current_style = .{},
            .style_icon_bytes = null,
            .style_icon_mime = null,
            .launched_browser_pid = null,
            .launched_browser_kind = null,
            .launched_browser_is_child = false,
            .launched_browser_lifecycle_linked = false,
            .launched_browser_profile_dir = null,
            .last_warning = null,
            .state_mutex = .{},
            .server_thread = null,
            .server_stop = std.atomic.Value(bool).init(false),
            .server_ready_mutex = .{},
            .server_ready_cond = .{},
            .server_ready = false,
            .server_listen_ok = false,
            .close_requested = std.atomic.Value(bool).init(false),
        };

        state.native_capabilities = state.backend.capabilities();
        try state.setStyleOwned(allocator, options.style);
        if (state.isNativeWindowActive()) {
            state.backend.applyStyle(state.current_style) catch |err| {
                if (state.rpc_state.log_enabled) {
                    if (backendWarningForError(err, state.window_fallback_emulation)) |warning| {
                        std.debug.print("[webui.warning] window={d} {s}\n", .{ state.id, warning });
                    }
                }
            };
        }
        return state;
    }

    fn setStyleOwned(self: *WindowState, allocator: std.mem.Allocator, style: WindowStyle) !void {
        if (self.style_icon_bytes) |buf| {
            allocator.free(buf);
            self.style_icon_bytes = null;
        }
        if (self.style_icon_mime) |buf| {
            allocator.free(buf);
            self.style_icon_mime = null;
        }

        self.current_style = style;
        self.current_style.icon = null;

        if (style.icon) |icon| {
            self.style_icon_bytes = try allocator.dupe(u8, icon.bytes);
            self.style_icon_mime = try allocator.dupe(u8, icon.mime_type);
            self.current_style.icon = .{
                .bytes = self.style_icon_bytes.?,
                .mime_type = self.style_icon_mime.?,
            };
        }
    }

    fn isNativeWindowActive(self: *const WindowState) bool {
        return self.transport_mode == .native_webview and self.backend.isNative();
    }

    fn capabilities(self: *const WindowState) []const WindowCapability {
        if (self.isNativeWindowActive()) {
            if (self.native_capabilities.len > 0) return self.native_capabilities;
            if (self.window_fallback_emulation) return emulated_capabilities[0..];
            return &.{};
        }
        if (self.window_fallback_emulation) return emulated_capabilities[0..];
        return &.{};
    }

    fn emit(self: *WindowState, kind: EventKind, name: []const u8, payload: []const u8) void {
        if (self.event_callback.handler) |handler| {
            const event = Event{
                .window_id = self.id,
                .kind = kind,
                .name = name,
                .payload = payload,
            };
            handler(self.event_callback.context, &event);
        }
    }

    fn requestClose(self: *WindowState) bool {
        self.emit(.close_requested, "close-requested", "");

        if (self.close_callback.handler) |handler| {
            if (!handler(self.close_callback.context, self.id)) {
                self.emit(.close_requested, "close-denied", "");
                return false;
            }
        }

        self.close_requested.store(true, .release);
        self.emit(.close_requested, "close-accepted", "");
        return true;
    }

    fn clearWarning(self: *WindowState) void {
        self.last_warning = null;
    }

    fn setWarning(self: *WindowState, message: []const u8) void {
        self.last_warning = message;
        if (self.rpc_state.log_enabled) {
            std.debug.print("[webui.warning] window={d} {s}\n", .{ self.id, message });
        }
        self.emit(.window_state, "warning", message);
    }

    fn setWarningFromBackendError(self: *WindowState, err: anyerror) bool {
        if (backendWarningForError(err, self.window_fallback_emulation)) |message| {
            self.setWarning(message);
            return true;
        }
        return false;
    }

    fn applyStyle(self: *WindowState, allocator: std.mem.Allocator, style: WindowStyle) !void {
        try self.setStyleOwned(allocator, style);
        self.clearWarning();
        if (self.isNativeWindowActive()) {
            self.backend.applyStyle(self.current_style) catch |err| {
                if (!(self.window_fallback_emulation and self.setWarningFromBackendError(err))) {
                    return err;
                }
                self.emit(.window_state, "style-emulated", "applied");
                return;
            };
            self.emit(.window_state, "style-native", "applied");
            return;
        }

        if (self.window_fallback_emulation) {
            self.emit(.window_state, "style-emulated", "applied");
            return;
        }

        return error.UnsupportedWindowStyle;
    }

    fn control(self: *WindowState, cmd: WindowControl) !WindowControlResult {
        self.emit(.window_state, "control", @tagName(cmd));
        self.clearWarning();

        if (cmd == .close and !self.requestClose()) {
            return error.CloseDenied;
        }

        if (self.isNativeWindowActive()) {
            const native_ok = blk: {
                self.backend.control(cmd) catch |err| {
                    if (self.window_fallback_emulation and self.setWarningFromBackendError(err)) {
                        break :blk false;
                    }
                    return err;
                };
                break :blk true;
            };
            if (native_ok) {
                return .{
                    .success = true,
                    .emulation = null,
                    .closed = cmd == .close,
                    .warning = null,
                };
            }
        }

        if (!self.window_fallback_emulation) return error.UnsupportedWindowControl;

        return switch (cmd) {
            .minimize => .{ .success = true, .emulation = "minimize_blur", .closed = false, .warning = self.last_warning },
            .maximize => .{ .success = true, .emulation = "maximize_fullscreen", .closed = false, .warning = self.last_warning },
            .restore => .{ .success = true, .emulation = "restore_fullscreen", .closed = false, .warning = self.last_warning },
            .hide => blk: {
                self.current_style.hidden = true;
                break :blk .{ .success = true, .emulation = "hide_page", .closed = false, .warning = self.last_warning };
            },
            .show => blk: {
                self.current_style.hidden = false;
                break :blk .{ .success = true, .emulation = "show_page", .closed = false, .warning = self.last_warning };
            },
            .close => .{ .success = true, .emulation = "close_window", .closed = true, .warning = self.last_warning },
        };
    }

    fn shouldServeBrowser(self: *const WindowState, app_options: AppOptions) bool {
        if (self.transport_mode == .browser_fallback) return true;
        if (self.transport_mode != .native_webview) return false;
        if (app_options.auto_open_browser and app_options.browser_launch.require_app_mode_window) return true;
        return app_options.browser_fallback_on_native_failure;
    }

    fn setLaunchedBrowserLaunch(self: *WindowState, allocator: std.mem.Allocator, launch: core_runtime.BrowserLaunch) void {
        self.cleanupBrowserProfileDir(allocator);
        if (launch.pid) |pid| {
            if (self.launched_browser_pid) |existing| {
                if (existing != pid) {
                    if (self.rpc_state.log_enabled) {
                        std.debug.print("[webui.browser] replacing tracked pid old={d} new={d}\n", .{ existing, pid });
                    }
                    core_runtime.terminateBrowserProcess(allocator, existing);
                }
            }
            if (self.rpc_state.log_enabled and self.launched_browser_pid == null) {
                std.debug.print("[webui.browser] tracking launched browser pid={d} kind={s}\n", .{
                    pid,
                    if (launch.kind) |kind| @tagName(kind) else "unknown",
                });
            }
            self.launched_browser_pid = pid;
        } else {
            if (self.launched_browser_pid) |existing| {
                if (self.rpc_state.log_enabled) {
                    std.debug.print("[webui.browser] replacing tracked pid old={d} with untracked browser launch\n", .{existing});
                }
                core_runtime.terminateBrowserProcess(allocator, existing);
            }
            self.launched_browser_pid = null;
        }

        self.launched_browser_kind = launch.kind;
        self.launched_browser_is_child = launch.is_child_process;
        self.launched_browser_lifecycle_linked = launch.lifecycle_linked;
        self.launched_browser_profile_dir = launch.profile_dir;

        if (self.rpc_state.log_enabled and launch.used_system_fallback) {
            std.debug.print("[webui.browser] system fallback launcher was used (tab-style window may appear)\n", .{});
        }

        self.backend.attachBrowserProcess(launch.kind, launch.pid, launch.is_child_process);
        self.native_capabilities = self.backend.capabilities();
        if (self.isNativeWindowActive()) {
            self.backend.applyStyle(self.current_style) catch |err| {
                _ = self.setWarningFromBackendError(err);
            };
        }
    }

    fn cleanupBrowserProfileDir(self: *WindowState, allocator: std.mem.Allocator) void {
        if (self.launched_browser_profile_dir) |dir| {
            core_runtime.cleanupBrowserProfileDir(allocator, dir);
            self.launched_browser_profile_dir = null;
        }
    }

    fn clearTrackedBrowserState(self: *WindowState, allocator: std.mem.Allocator) void {
        self.launched_browser_pid = null;
        self.launched_browser_kind = null;
        self.launched_browser_is_child = false;
        self.launched_browser_lifecycle_linked = false;
        self.cleanupBrowserProfileDir(allocator);
        self.backend.attachBrowserProcess(null, null, false);
        self.native_capabilities = self.backend.capabilities();
    }

    fn markClosedFromTrackedBrowserExit(self: *WindowState, allocator: std.mem.Allocator, event_name: []const u8) void {
        self.clearTrackedBrowserState(allocator);
        if (!self.close_requested.load(.acquire)) {
            self.close_requested.store(true, .release);
            self.emit(.close_requested, event_name, "");
        }
    }

    fn reconcileChildExit(self: *WindowState, allocator: std.mem.Allocator) void {
        const pid = self.launched_browser_pid orelse return;

        if (self.launched_browser_lifecycle_linked and core_runtime.linkedChildExited(pid)) {
            self.markClosedFromTrackedBrowserExit(allocator, "child-exited");
            return;
        }

        if (!core_runtime.isProcessAlive(pid)) {
            self.markClosedFromTrackedBrowserExit(allocator, "browser-exited");
        }
    }

    fn requestLifecycleCloseFromFrontend(self: *WindowState) void {
        if (self.launched_browser_pid) |pid| {
            if (core_runtime.isProcessAlive(pid)) {
                if (self.rpc_state.log_enabled) {
                    std.debug.print("[webui.lifecycle] ignoring close while tracked pid is alive pid={d}\n", .{pid});
                }
                return;
            }
        }

        _ = self.requestClose();
    }

    fn hasTrackedChildBrowser(self: *const WindowState) bool {
        return self.launched_browser_lifecycle_linked;
    }

    fn lifecycleConfig(self: *const WindowState) LifecycleConfig {
        if (self.hasTrackedChildBrowser()) return lifecycle_child_process_config;
        return lifecycle_fallback_config;
    }

    fn terminateLaunchedBrowser(self: *WindowState, allocator: std.mem.Allocator) void {
        if (self.launched_browser_pid) |pid| {
            if (self.rpc_state.log_enabled) {
                std.debug.print("[webui.browser] terminating tracked browser pid={d}\n", .{pid});
            }
            core_runtime.terminateBrowserProcess(allocator, pid);
        }
        self.clearTrackedBrowserState(allocator);
    }

    fn localRenderUrl(self: *const WindowState, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/", .{self.server_port});
    }

    fn ensureBrowserRenderState(self: *WindowState, allocator: std.mem.Allocator, app_options: AppOptions) !void {
        if (!self.shouldServeBrowser(app_options)) return;
        try self.ensureServerStarted();
        try self.ensureServerReachable();

        const url = try self.localRenderUrl(allocator);
        defer allocator.free(url);
        try replaceOwned(allocator, &self.last_url, url);

        if (app_options.auto_open_browser) {
            if (core_runtime.openInBrowser(allocator, url, self.current_style, app_options.browser_launch)) |launch| {
                self.setLaunchedBrowserLaunch(allocator, launch);
            } else |err| {
                if (self.rpc_state.log_enabled) {
                    std.debug.print("[webui.browser] launch failed error={s}\n", .{@errorName(err)});
                }
                if (app_options.browser_launch.require_app_mode_window) return err;
            }
        }
    }

    fn deinit(self: *WindowState, allocator: std.mem.Allocator) void {
        self.stopServer();

        allocator.free(self.title);

        if (self.last_html) |buf| allocator.free(buf);
        if (self.last_file) |buf| allocator.free(buf);
        if (self.last_url) |buf| allocator.free(buf);
        if (self.style_icon_bytes) |buf| allocator.free(buf);
        if (self.style_icon_mime) |buf| allocator.free(buf);

        self.terminateLaunchedBrowser(allocator);
        self.backend.deinit();
        self.rpc_state.deinit(allocator);
    }

    fn ensureServerStarted(self: *WindowState) !void {
        if (self.server_thread != null) return;

        self.server_stop.store(false, .release);

        self.server_ready_mutex.lock();
        self.server_ready = false;
        self.server_listen_ok = false;
        self.server_ready_mutex.unlock();

        self.server_thread = try std.Thread.spawn(.{}, serverThreadMain, .{self});

        self.server_ready_mutex.lock();
        defer self.server_ready_mutex.unlock();

        while (!self.server_ready) {
            self.server_ready_cond.timedWait(&self.server_ready_mutex, 2 * std.time.ns_per_s) catch return error.ServerStartTimeout;
        }

        if (!self.server_listen_ok) return error.ServerStartFailed;
    }

    fn ensureServerReachable(self: *WindowState) !void {
        const address = try std.net.Address.parseIp4("127.0.0.1", self.server_port);

        var attempt: usize = 0;
        while (attempt < 25) : (attempt += 1) {
            const stream = std.net.tcpConnectToAddress(address) catch {
                std.Thread.sleep(20 * std.time.ns_per_ms);
                continue;
            };
            stream.close();
            return;
        }

        return error.ServerStartTimeout;
    }

    fn stopServer(self: *WindowState) void {
        self.server_stop.store(true, .release);
        self.server_ready_cond.broadcast();

        if (self.server_thread) |thread| {
            thread.join();
            self.server_thread = null;
        }
    }

    fn serverThreadMain(self: *WindowState) void {
        const address = std.net.Address.parseIp4("127.0.0.1", self.server_port) catch {
            self.server_ready_mutex.lock();
            self.server_listen_ok = false;
            self.server_ready = true;
            self.server_ready_cond.broadcast();
            self.server_ready_mutex.unlock();
            return;
        };

        var server = address.listen(.{ .reuse_address = true, .force_nonblocking = true }) catch {
            self.server_ready_mutex.lock();
            self.server_listen_ok = false;
            self.server_ready = true;
            self.server_ready_cond.broadcast();
            self.server_ready_mutex.unlock();
            return;
        };
        defer server.deinit();

        self.server_ready_mutex.lock();
        self.server_listen_ok = true;
        self.server_ready = true;
        self.server_ready_cond.broadcast();
        self.server_ready_mutex.unlock();

        while (!self.server_stop.load(.acquire)) {
            const conn = server.accept() catch |err| {
                switch (err) {
                    error.WouldBlock => {
                        std.Thread.sleep(5 * std.time.ns_per_ms);
                        continue;
                    },
                    else => continue,
                }
            };
            defer conn.stream.close();
            handleConnection(self, std.heap.page_allocator, conn.stream) catch {};
        }
    }
};

pub const App = struct {
    allocator: std.mem.Allocator,
    options: AppOptions,
    windows: std.array_list.Managed(WindowState),
    shutdown_requested: bool,
    next_window_id: usize,

    pub fn init(allocator: std.mem.Allocator, options: AppOptions) !App {
        core_runtime.initializeRuntime(options.enable_tls, options.enable_webui_log);
        return .{
            .allocator = allocator,
            .options = options,
            .windows = std.array_list.Managed(WindowState).init(allocator),
            .shutdown_requested = false,
            .next_window_id = 1,
        };
    }

    pub fn initDefault(allocator: std.mem.Allocator) !App {
        return init(allocator, .{});
    }

    pub fn deinit(self: *App) void {
        for (self.windows.items) |*state| {
            state.deinit(self.allocator);
        }
        self.windows.deinit();
    }

    pub fn newWindow(self: *App, options: WindowOptions) !Window {
        const id = options.window_id orelse self.next_window_id;
        if (id == 0) return error.InvalidWindowId;

        if (options.window_id) |explicit_id| {
            if (explicit_id >= self.next_window_id) {
                self.next_window_id = explicit_id + 1;
            }
        } else {
            self.next_window_id += 1;
        }

        try self.windows.append(try WindowState.init(self.allocator, id, options, self.options));

        return .{
            .app = self,
            .index = self.windows.items.len - 1,
            .id = id,
        };
    }

    pub fn window(self: *App) !Window {
        return self.newWindow(.{});
    }

    pub fn windowWithTitle(self: *App, title: []const u8) !Window {
        return self.newWindow(.{ .title = title });
    }

    pub fn run(self: *App) !void {
        if (self.shutdown_requested) return;

        for (self.windows.items) |*state| {
            if (!state.shown or state.connected_emitted) continue;

            if (state.shouldServeBrowser(self.options) and (state.last_html != null or state.last_file != null)) {
                try state.ensureServerStarted();
            }

            state.connected_emitted = true;
            for (state.capabilities()) |capability| {
                state.emit(.window_capability, "capability", @tagName(capability));
            }

            if (state.event_callback.handler) |handler| {
                const event = Event{
                    .window_id = state.id,
                    .kind = .connected,
                    .name = "connected",
                    .payload = "",
                };
                handler(state.event_callback.context, &event);
            }
        }
    }

    pub fn shutdown(self: *App) void {
        self.shutdown_requested = true;

        for (self.windows.items) |*state| {
            state.terminateLaunchedBrowser(self.allocator);
            state.stopServer();
            if (state.event_callback.handler) |handler| {
                const event = Event{
                    .window_id = state.id,
                    .kind = .disconnected,
                    .name = "disconnected",
                    .payload = "",
                };
                handler(state.event_callback.context, &event);
            }
        }
    }
};

pub const Window = struct {
    app: *App,
    index: usize,
    id: usize,

    pub fn showHtml(self: *Window, html: []const u8) !void {
        if (html.len == 0) return error.EmptyHtml;

        const win_state = self.state();

        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();

        try replaceOwned(self.app.allocator, &win_state.last_html, html);
        if (win_state.last_file) |buf| {
            self.app.allocator.free(buf);
            win_state.last_file = null;
        }
        win_state.shown = true;

        try win_state.ensureBrowserRenderState(self.app.allocator, self.app.options);

        self.emit(.navigation, "show-html", html);
    }

    pub fn show(self: *Window, content: WindowContent) !void {
        switch (content) {
            .html => |html| try self.showHtml(html),
            .file => |path| try self.showFile(path),
            .url => |url| try self.showUrl(url),
        }
    }

    pub fn showFile(self: *Window, path: []const u8) !void {
        if (path.len == 0) return error.EmptyPath;

        _ = try std.fs.cwd().statFile(path);

        const win_state = self.state();

        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();

        try replaceOwned(self.app.allocator, &win_state.last_file, path);
        if (win_state.last_html) |buf| {
            self.app.allocator.free(buf);
            win_state.last_html = null;
        }
        win_state.shown = true;

        try win_state.ensureBrowserRenderState(self.app.allocator, self.app.options);

        self.emit(.navigation, "show-file", path);
    }

    pub fn showUrl(self: *Window, url: []const u8) !void {
        if (!isLikelyUrl(url)) return error.InvalidUrl;

        const win_state = self.state();

        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();

        try replaceOwned(self.app.allocator, &win_state.last_url, url);
        win_state.shown = true;

        if (win_state.isNativeWindowActive()) {
            win_state.backend.navigate(url);
        }

        if (self.app.options.auto_open_browser) {
            if (core_runtime.openInBrowser(self.app.allocator, url, win_state.current_style, self.app.options.browser_launch)) |launch| {
                win_state.setLaunchedBrowserLaunch(self.app.allocator, launch);
            } else |err| {
                if (win_state.rpc_state.log_enabled) {
                    std.debug.print("[webui.browser] launch failed error={s}\n", .{@errorName(err)});
                }
                if (self.app.options.browser_launch.require_app_mode_window) return err;
            }
        }

        self.emit(.navigation, "show-url", url);
    }

    pub fn navigate(self: *Window, url: []const u8) !void {
        try self.showUrl(url);
        self.emit(.navigation, "navigate", url);
    }

    pub fn onEvent(self: *Window, handler: EventHandler, context: ?*anyopaque) void {
        const win_state = self.state();
        win_state.event_callback = .{ .handler = handler, .context = context };
    }

    pub fn rpc(self: *Window) RpcRegistry {
        return .{
            .allocator = self.app.allocator,
            .state = &self.state().rpc_state,
        };
    }

    pub fn bindRpc(self: *Window, comptime RpcStruct: type, options: RpcOptions) !void {
        try self.rpc().register(RpcStruct, options);
    }

    pub fn rpcClientScript(self: *Window, options: BridgeOptions) []const u8 {
        return self.rpc().generatedClientScript(options);
    }

    pub fn rpcTypeDeclarations(self: *Window, options: BridgeOptions) []const u8 {
        return self.rpc().generatedTypeScriptDeclarations(options);
    }

    pub fn sendRaw(self: *Window, bytes: []const u8) !void {
        const win_state = self.state();
        if (win_state.raw_callback.handler) |handler| {
            handler(win_state.raw_callback.context, bytes);
        }
        self.emit(.raw, "raw-send", bytes);
    }

    pub fn onRaw(self: *Window, handler: RawHandler, context: ?*anyopaque) void {
        const win_state = self.state();
        win_state.raw_callback = .{ .handler = handler, .context = context };
    }

    pub fn browserUrl(self: *Window) ![]u8 {
        const win_state = self.state();
        if (!win_state.shouldServeBrowser(self.app.options)) return error.TransportNotBrowserRenderable;

        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();

        try win_state.ensureServerStarted();
        try win_state.ensureServerReachable();
        return try win_state.localRenderUrl(self.app.allocator);
    }

    pub fn openInBrowser(self: *Window) !void {
        return self.openInBrowserWithOptions(self.app.options.browser_launch);
    }

    pub fn openInBrowserWithOptions(self: *Window, launch_options: BrowserLaunchOptions) !void {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        if (!win_state.shouldServeBrowser(self.app.options)) return error.TransportNotBrowserRenderable;

        try win_state.ensureServerStarted();
        try win_state.ensureServerReachable();
        const url = try win_state.localRenderUrl(self.app.allocator);
        defer self.app.allocator.free(url);
        try replaceOwned(self.app.allocator, &win_state.last_url, url);

        const launch = try core_runtime.openInBrowser(self.app.allocator, url, win_state.current_style, launch_options);
        win_state.setLaunchedBrowserLaunch(self.app.allocator, launch);
    }

    pub fn applyStyle(self: *Window, style: WindowStyle) !void {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        try win_state.applyStyle(self.app.allocator, style);
    }

    pub fn currentStyle(self: *Window) WindowStyle {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        return win_state.current_style;
    }

    pub fn lastWarning(self: *Window) ?[]const u8 {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        return win_state.last_warning;
    }

    pub fn clearWarning(self: *Window) void {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        win_state.clearWarning();
    }

    pub fn control(self: *Window, cmd: WindowControl) !WindowControlResult {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        return win_state.control(cmd);
    }

    pub fn setCloseHandler(self: *Window, handler: CloseHandler, context: ?*anyopaque) void {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        win_state.close_callback = .{
            .handler = handler,
            .context = context,
        };
    }

    pub fn clearCloseHandler(self: *Window) void {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        win_state.close_callback = .{};
    }

    pub fn capabilities(self: *Window) []const WindowCapability {
        return self.state().capabilities();
    }

    fn state(self: *Window) *WindowState {
        return &self.app.windows.items[self.index];
    }

    fn emit(self: *Window, kind: EventKind, name: []const u8, payload: []const u8) void {
        const win_state = self.state();
        if (win_state.event_callback.handler) |handler| {
            const event = Event{
                .window_id = self.id,
                .kind = kind,
                .name = name,
                .payload = payload,
            };
            handler(win_state.event_callback.context, &event);
        }
    }
};

pub const Service = struct {
    app: App,
    window_index: usize,
    window_id: usize,

    pub fn init(allocator: std.mem.Allocator, comptime rpc_methods: type, options: ServiceOptions) !Service {
        var app = try App.init(allocator, options.app);
        errdefer app.deinit();

        var main_window = try app.newWindow(options.window);
        try main_window.bindRpc(rpc_methods, options.rpc);

        return .{
            .app = app,
            .window_index = main_window.index,
            .window_id = main_window.id,
        };
    }

    pub fn initDefault(allocator: std.mem.Allocator, comptime rpc_methods: type) !Service {
        return init(allocator, rpc_methods, .{});
    }

    pub fn deinit(self: *Service) void {
        self.app.deinit();
    }

    pub fn window(self: *Service) Window {
        return .{
            .app = &self.app,
            .index = self.window_index,
            .id = self.window_id,
        };
    }

    pub fn run(self: *Service) !void {
        try self.app.run();
    }

    pub fn shouldExit(self: *Service) bool {
        if (process_signals.stopRequested()) {
            self.app.shutdown();
            return true;
        }
        if (self.app.shutdown_requested) return true;
        var win = self.window();
        const state = win.state();
        state.state_mutex.lock();
        defer state.state_mutex.unlock();
        state.reconcileChildExit(self.app.allocator);
        return state.close_requested.load(.acquire);
    }

    pub fn shutdown(self: *Service) void {
        self.app.shutdown();
    }

    pub fn show(self: *Service, content: WindowContent) !void {
        var win = self.window();
        try win.show(content);
    }

    pub fn showHtml(self: *Service, html: []const u8) !void {
        var win = self.window();
        try win.showHtml(html);
    }

    pub fn showFile(self: *Service, path: []const u8) !void {
        var win = self.window();
        try win.showFile(path);
    }

    pub fn showUrl(self: *Service, url: []const u8) !void {
        var win = self.window();
        try win.showUrl(url);
    }

    pub fn navigate(self: *Service, url: []const u8) !void {
        var win = self.window();
        try win.navigate(url);
    }

    pub fn applyStyle(self: *Service, style: WindowStyle) !void {
        var win = self.window();
        try win.applyStyle(style);
    }

    pub fn currentStyle(self: *Service) WindowStyle {
        var win = self.window();
        return win.currentStyle();
    }

    pub fn lastWarning(self: *Service) ?[]const u8 {
        var win = self.window();
        return win.lastWarning();
    }

    pub fn clearWarning(self: *Service) void {
        var win = self.window();
        win.clearWarning();
    }

    pub fn control(self: *Service, cmd: WindowControl) !WindowControlResult {
        var win = self.window();
        return win.control(cmd);
    }

    pub fn setCloseHandler(self: *Service, handler: CloseHandler, context: ?*anyopaque) void {
        var win = self.window();
        win.setCloseHandler(handler, context);
    }

    pub fn clearCloseHandler(self: *Service) void {
        var win = self.window();
        win.clearCloseHandler();
    }

    pub fn capabilities(self: *Service) []const WindowCapability {
        var win = self.window();
        return win.capabilities();
    }

    pub fn onEvent(self: *Service, handler: EventHandler, context: ?*anyopaque) void {
        var win = self.window();
        win.onEvent(handler, context);
    }

    pub fn onRaw(self: *Service, handler: RawHandler, context: ?*anyopaque) void {
        var win = self.window();
        win.onRaw(handler, context);
    }

    pub fn sendRaw(self: *Service, bytes: []const u8) !void {
        var win = self.window();
        try win.sendRaw(bytes);
    }

    pub fn browserUrl(self: *Service) ![]u8 {
        var win = self.window();
        return win.browserUrl();
    }

    pub fn openInBrowser(self: *Service) !void {
        var win = self.window();
        try win.openInBrowser();
    }

    pub fn openInBrowserWithOptions(self: *Service, launch_options: BrowserLaunchOptions) !void {
        var win = self.window();
        try win.openInBrowserWithOptions(launch_options);
    }

    pub fn rpcClientScript(self: *Service, options: BridgeOptions) []const u8 {
        var win = self.window();
        return win.rpcClientScript(options);
    }

    pub fn rpcTypeDeclarations(self: *Service, options: BridgeOptions) []const u8 {
        var win = self.window();
        return win.rpcTypeDeclarations(options);
    }

    pub fn generatedClientScriptComptime(comptime rpc_methods: type, comptime options: BridgeOptions) []const u8 {
        return RpcRegistry.generatedClientScriptComptime(rpc_methods, options);
    }

    pub fn generatedTypeScriptDeclarationsComptime(comptime rpc_methods: type, comptime options: BridgeOptions) []const u8 {
        return RpcRegistry.generatedTypeScriptDeclarationsComptime(rpc_methods, options);
    }
};

pub const RpcRegistry = struct {
    allocator: std.mem.Allocator,
    state: *RpcRegistryState,

    pub fn register(self: RpcRegistry, comptime RpcStruct: type, options: RpcOptions) !void {
        self.state.dispatcher_mode = options.dispatcher_mode;
        self.state.custom_dispatcher = options.custom_dispatcher;
        self.state.custom_context = options.custom_context;
        self.state.threaded_poll_interval_ns = options.threaded_poll_interval_ns;

        if (self.state.dispatcher_mode == .threaded) {
            try self.state.ensureWorkerStarted();
        }

        var registered_count: usize = 0;

        const info = @typeInfo(RpcStruct);
        if (info != .@"struct") return error.InvalidRpcContainer;

        inline for (info.@"struct".decls) |decl| {
            const value = @field(RpcStruct, decl.name);
            switch (@typeInfo(@TypeOf(value))) {
                .@"fn" => {
                    const fn_info = @typeInfo(@TypeOf(value)).@"fn";
                    const ts_arg_signature = try buildTsArgSignature(self.allocator, fn_info.params);
                    defer self.allocator.free(ts_arg_signature);
                    try self.state.addFunction(
                        self.allocator,
                        decl.name,
                        fn_info.params.len,
                        makeInvoker(RpcStruct, decl.name),
                        ts_arg_signature,
                        tsTypeNameForReturn(fn_info.return_type orelse void),
                    );
                    registered_count += 1;
                },
                else => {},
            }
        }

        if (registered_count == 0) return error.NoRpcFunctions;

        try self.state.rebuildScript(self.allocator, options.bridge_options);
    }

    pub fn generatedClientScript(self: RpcRegistry, options: BridgeOptions) []const u8 {
        if (self.state.generated_script == null or !bridgeOptionsEqual(self.state.bridge_options, options)) {
            self.state.rebuildScript(self.allocator, options) catch {};
        }
        return self.state.generated_script orelse bridge_template.default_script;
    }

    pub fn generatedClientScriptComptime(comptime RpcStruct: type, comptime options: BridgeOptions) []const u8 {
        return bridge_template.renderComptime(RpcStruct, .{
            .namespace = options.namespace,
            .rpc_route = options.rpc_route,
        });
    }

    pub fn writeGeneratedClientScript(self: RpcRegistry, output_path: []const u8, options: BridgeOptions) !void {
        const metas = try self.allocator.alloc(bridge_template.RpcFunctionMeta, self.state.handlers.items.len);
        defer self.allocator.free(metas);

        for (self.state.handlers.items, 0..) |handler, i| {
            metas[i] = .{
                .name = handler.name,
                .arity = handler.arity,
                .ts_arg_signature = handler.ts_arg_signature,
                .ts_return_type = handler.ts_return_type,
            };
        }

        const script = try bridge_template.renderForWrittenOutput(self.allocator, .{
            .namespace = options.namespace,
            .rpc_route = options.rpc_route,
        }, metas);
        defer self.allocator.free(script);

        if (std.fs.path.dirname(output_path)) |dir_name| {
            try std.fs.cwd().makePath(dir_name);
        }
        const file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(script);
    }

    pub fn generatedTypeScriptDeclarations(self: RpcRegistry, options: BridgeOptions) []const u8 {
        if (self.state.generated_typescript == null or !bridgeOptionsEqual(self.state.bridge_options, options)) {
            self.state.rebuildTypeScript(self.allocator, options) catch {};
        }
        return self.state.generated_typescript orelse "export interface WebuiRpcClient {}\n";
    }

    pub fn generatedTypeScriptDeclarationsComptime(comptime RpcStruct: type, comptime options: BridgeOptions) []const u8 {
        return bridge_template.renderTypeScriptDeclarationsComptime(RpcStruct, .{
            .namespace = options.namespace,
            .rpc_route = options.rpc_route,
        });
    }

    pub fn writeGeneratedTypeScriptDeclarations(self: RpcRegistry, output_path: []const u8, options: BridgeOptions) !void {
        const script = self.generatedTypeScriptDeclarations(options);
        if (std.fs.path.dirname(output_path)) |dir_name| {
            try std.fs.cwd().makePath(dir_name);
        }
        const file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(script);
    }
};

fn bridgeOptionsEqual(lhs: BridgeOptions, rhs: BridgeOptions) bool {
    return std.mem.eql(u8, lhs.namespace, rhs.namespace) and
        std.mem.eql(u8, lhs.script_route, rhs.script_route) and
        std.mem.eql(u8, lhs.rpc_route, rhs.rpc_route);
}

fn buildTsArgSignature(allocator: std.mem.Allocator, comptime params: anytype) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    inline for (params, 0..) |param, idx| {
        if (idx != 0) try out.appendSlice(", ");
        const param_type = param.type orelse return error.InvalidRpcParamType;
        try out.writer().print("arg{d}: {s}", .{ idx, tsTypeNameForType(param_type) });
    }

    return out.toOwnedSlice();
}

fn tsTypeNameForReturn(comptime return_type: type) []const u8 {
    if (@typeInfo(return_type) == .error_union) {
        const payload = @typeInfo(return_type).error_union.payload;
        return tsTypeNameForType(payload);
    }
    return tsTypeNameForType(return_type);
}

fn tsTypeNameForType(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .bool => "boolean",
        .int, .comptime_int, .float, .comptime_float => "number",
        .pointer => |ptr| blk: {
            if (ptr.size == .slice and ptr.child == u8 and ptr.is_const) break :blk "string";
            break :blk "unknown";
        },
        .optional => "unknown | null",
        .@"enum" => "string",
        .void => "void",
        else => "unknown",
    };
}

fn makeInvoker(comptime RpcStruct: type, comptime function_name: []const u8) RpcInvokeFn {
    return struct {
        fn invoke(allocator: std.mem.Allocator, args: []const std.json.Value) anyerror![]u8 {
            const function = @field(RpcStruct, function_name);
            const Fn = @TypeOf(function);
            const fn_info = @typeInfo(Fn).@"fn";

            if (args.len != fn_info.params.len) return error.InvalidRpcArgCount;

            var tuple: std.meta.ArgsTuple(Fn) = undefined;
            inline for (fn_info.params, 0..) |param, idx| {
                const param_type = param.type orelse @compileError("RPC parameter type is required");
                @field(tuple, std.fmt.comptimePrint("{d}", .{idx})) = try coerceJsonArg(param_type, args[idx]);
            }

            const return_type = fn_info.return_type orelse void;

            if (@typeInfo(return_type) == .error_union) {
                const result = try @call(.auto, function, tuple);
                return try encodeJsonValue(allocator, result);
            }

            if (return_type == void) {
                @call(.auto, function, tuple);
                return try allocator.dupe(u8, "null");
            }

            const result = @call(.auto, function, tuple);
            return try encodeJsonValue(allocator, result);
        }
    }.invoke;
}

fn coerceJsonArg(comptime T: type, value: std.json.Value) !T {
    return switch (@typeInfo(T)) {
        .bool => switch (value) {
            .bool => |b| b,
            else => error.InvalidRpcArgType,
        },
        .int, .comptime_int => switch (value) {
            .integer => |v| @as(T, @intCast(v)),
            .float => |v| @as(T, @intFromFloat(v)),
            else => error.InvalidRpcArgType,
        },
        .float, .comptime_float => switch (value) {
            .float => |v| @as(T, @floatCast(v)),
            .integer => |v| @as(T, @floatFromInt(v)),
            else => error.InvalidRpcArgType,
        },
        .pointer => |ptr| blk: {
            if (ptr.size == .slice and ptr.child == u8 and ptr.is_const) {
                break :blk switch (value) {
                    .string => |s| s,
                    else => error.InvalidRpcArgType,
                };
            }
            break :blk error.UnsupportedRpcArgType;
        },
        .optional => |opt| blk: {
            if (value == .null) break :blk @as(T, null);
            const unwrapped = try coerceJsonArg(opt.child, value);
            break :blk unwrapped;
        },
        .@"enum" => |enum_info| blk: {
            _ = enum_info;
            const raw = switch (value) {
                .string => |s| s,
                else => break :blk error.InvalidRpcArgType,
            };
            break :blk std.meta.stringToEnum(T, raw) orelse error.InvalidRpcArgType;
        },
        else => error.UnsupportedRpcArgType,
    };
}

fn encodeJsonValue(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    return try std.json.Stringify.valueAlloc(allocator, value, .{});
}

fn replaceOwned(allocator: std.mem.Allocator, target: *?[]u8, value: []const u8) !void {
    if (target.*) |buf| {
        allocator.free(buf);
    }
    target.* = try allocator.dupe(u8, value);
}

fn isLikelyUrl(url: []const u8) bool {
    return isHttpUrl(url) or std.mem.startsWith(u8, url, "file://");
}

fn isHttpUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "http://") or std.mem.startsWith(u8, url, "https://");
}

const HttpRequest = struct {
    raw: []u8,
    method: []const u8,
    path: []const u8,
    body: []const u8,
};

fn handleConnection(state: *WindowState, allocator: std.mem.Allocator, stream: std.net.Stream) !void {
    const request = try readHttpRequest(allocator, stream);
    defer allocator.free(request.raw);

    const path_only = pathWithoutQuery(request.path);

    if (try handleBridgeScriptRoute(state, allocator, stream, request.method, path_only)) return;
    if (try handleRpcRoute(state, allocator, stream, request.method, path_only, request.body)) return;
    if (try handleLifecycleConfigRoute(state, allocator, stream, request.method, path_only)) return;
    if (try handleLifecycleRoute(state, allocator, stream, request.method, path_only, request.body)) return;
    if (try handleWindowControlRoute(state, allocator, stream, request.method, path_only, request.body)) return;
    if (try handleWindowStyleRoute(state, allocator, stream, request.method, path_only, request.body)) return;
    if (try handleWindowContentRoute(state, allocator, stream, request.method, path_only)) return;

    try writeHttpResponse(stream, 404, "text/plain; charset=utf-8", "not found");
}

fn handleLifecycleConfigRoute(
    state: *WindowState,
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    method: []const u8,
    path_only: []const u8,
) !bool {
    if (!std.mem.eql(u8, method, "GET")) return false;
    if (!std.mem.eql(u8, path_only, "/webui/lifecycle/config")) return false;

    state.state_mutex.lock();
    const config = state.lifecycleConfig();
    state.state_mutex.unlock();

    const payload = try std.json.Stringify.valueAlloc(allocator, config, .{});
    defer allocator.free(payload);

    try writeHttpResponse(stream, 200, "application/json; charset=utf-8", payload);
    return true;
}

fn handleLifecycleRoute(
    state: *WindowState,
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    method: []const u8,
    path_only: []const u8,
    body: []const u8,
) !bool {
    if (!std.mem.eql(u8, method, "POST")) return false;
    if (!std.mem.eql(u8, path_only, "/webui/lifecycle")) return false;

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch null;
    var logged_event = false;
    var heartbeat_event = false;
    if (parsed) |*p| {
        defer p.deinit();
        if (p.value == .object) {
            if (p.value.object.get("event")) |event_value| {
                if (event_value == .string) {
                    if (std.mem.eql(u8, event_value.string, "window_closing")) {
                        state.state_mutex.lock();
                        state.requestLifecycleCloseFromFrontend();
                        state.state_mutex.unlock();
                    }
                    if (std.mem.eql(u8, event_value.string, "heartbeat")) {
                        heartbeat_event = true;
                    }
                    if (state.rpc_state.log_enabled and !std.mem.eql(u8, event_value.string, "heartbeat")) {
                        std.debug.print("[webui.lifecycle] event={s}\n", .{event_value.string});
                        logged_event = true;
                    }
                }
            }
        }
    }

    if (state.rpc_state.log_enabled and !logged_event and !heartbeat_event) {
        std.debug.print("[webui.lifecycle] body={s}\n", .{body});
    }

    try writeHttpResponse(stream, 200, "application/json; charset=utf-8", "{\"ok\":true}");
    return true;
}

fn pathWithoutQuery(path: []const u8) []const u8 {
    return if (std.mem.indexOfScalar(u8, path, '?')) |q| path[0..q] else path;
}

fn handleBridgeScriptRoute(
    state: *WindowState,
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    method: []const u8,
    path_only: []const u8,
) !bool {
    if (!std.mem.eql(u8, method, "GET")) return false;
    if (!std.mem.eql(u8, path_only, state.rpc_state.bridge_options.script_route)) return false;

    if (state.rpc_state.generated_script == null) {
        try state.rpc_state.rebuildScript(allocator, state.rpc_state.bridge_options);
    }
    const script = state.rpc_state.generated_script orelse bridge_template.default_script;
    try writeHttpResponse(stream, 200, "application/javascript; charset=utf-8", script);
    return true;
}

fn handleRpcRoute(
    state: *WindowState,
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    method: []const u8,
    path_only: []const u8,
    body: []const u8,
) !bool {
    if (!std.mem.eql(u8, method, "POST")) return false;
    if (!std.mem.eql(u8, path_only, state.rpc_state.bridge_options.rpc_route)) return false;

    if (state.rpc_state.log_enabled) {
        std.debug.print("[webui.rpc] raw body={s}\n", .{body});
    }

    const payload = state.rpc_state.invokeFromJsonPayload(allocator, body) catch |err| {
        const err_body = try std.fmt.allocPrint(allocator, "{{\"error\":\"{s}\"}}", .{@errorName(err)});
        defer allocator.free(err_body);
        if (state.rpc_state.log_enabled) {
            std.debug.print("[webui.rpc] error={s}\n", .{@errorName(err)});
        }
        try writeHttpResponse(stream, 400, "application/json; charset=utf-8", err_body);
        return true;
    };
    defer allocator.free(payload);

    if (state.rpc_state.log_enabled) {
        std.debug.print("[webui.rpc] http response={s}\n", .{payload});
    }

    if (state.event_callback.handler) |handler| {
        const event = Event{
            .window_id = state.id,
            .kind = .rpc,
            .name = "rpc",
            .payload = "rpc-dispatch",
        };
        handler(state.event_callback.context, &event);
    }

    try writeHttpResponse(stream, 200, "application/json; charset=utf-8", payload);
    return true;
}

fn handleWindowControlRoute(
    state: *WindowState,
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    method: []const u8,
    path_only: []const u8,
    body: []const u8,
) !bool {
    if (!std.mem.eql(u8, path_only, "/webui/window/control")) return false;

    if (std.mem.eql(u8, method, "GET")) {
        state.state_mutex.lock();
        const caps = state.capabilities();
        const emulation_enabled = state.window_fallback_emulation;
        state.state_mutex.unlock();
        const payload = try std.json.Stringify.valueAlloc(allocator, .{
            .capabilities = caps,
            .emulation_enabled = emulation_enabled,
        }, .{});
        defer allocator.free(payload);
        try writeHttpResponse(stream, 200, "application/json; charset=utf-8", payload);
        return true;
    }

    if (!std.mem.eql(u8, method, "POST")) return false;

    const Req = struct {
        cmd: []const u8,
    };
    var parsed = std.json.parseFromSlice(Req, allocator, body, .{ .ignore_unknown_fields = true }) catch {
        try writeHttpResponse(stream, 400, "application/json; charset=utf-8", "{\"error\":\"invalid_control_request\"}");
        return true;
    };
    defer parsed.deinit();

    const cmd = std.meta.stringToEnum(WindowControl, parsed.value.cmd) orelse {
        try writeHttpResponse(stream, 400, "application/json; charset=utf-8", "{\"error\":\"unknown_window_control\"}");
        return true;
    };

    if (state.rpc_state.log_enabled) {
        std.debug.print("[webui.window] control cmd={s}\n", .{@tagName(cmd)});
    }

    state.state_mutex.lock();
    const result = state.control(cmd) catch |err| {
        state.state_mutex.unlock();
        const err_payload = try std.fmt.allocPrint(allocator, "{{\"error\":\"{s}\"}}", .{@errorName(err)});
        defer allocator.free(err_payload);
        if (state.rpc_state.log_enabled) {
            std.debug.print("[webui.window] control error={s}\n", .{@errorName(err)});
        }
        try writeHttpResponse(stream, 400, "application/json; charset=utf-8", err_payload);
        return true;
    };
    state.state_mutex.unlock();

    if (state.rpc_state.log_enabled) {
        std.debug.print("[webui.window] control result success={any} emulation={s} closed={any} warning={s}\n", .{
            result.success,
            result.emulation orelse "",
            result.closed,
            result.warning orelse "",
        });
    }

    const payload = try std.json.Stringify.valueAlloc(allocator, .{
        .success = result.success,
        .emulation = result.emulation,
        .closed = result.closed,
        .warning = result.warning,
    }, .{});
    defer allocator.free(payload);
    try writeHttpResponse(stream, 200, "application/json; charset=utf-8", payload);
    return true;
}

fn handleWindowStyleRoute(
    state: *WindowState,
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    method: []const u8,
    path_only: []const u8,
    body: []const u8,
) !bool {
    if (!std.mem.eql(u8, path_only, "/webui/window/style")) return false;

    if (std.mem.eql(u8, method, "GET")) {
        state.state_mutex.lock();
        const style = state.current_style;
        state.state_mutex.unlock();
        const payload = try std.json.Stringify.valueAlloc(allocator, style, .{});
        defer allocator.free(payload);
        try writeHttpResponse(stream, 200, "application/json; charset=utf-8", payload);
        return true;
    }

    if (!std.mem.eql(u8, method, "POST")) return false;

    var parsed = std.json.parseFromSlice(WindowStyle, allocator, body, .{ .ignore_unknown_fields = true }) catch {
        try writeHttpResponse(stream, 400, "application/json; charset=utf-8", "{\"error\":\"invalid_window_style\"}");
        return true;
    };
    defer parsed.deinit();

    state.state_mutex.lock();
    state.applyStyle(allocator, parsed.value) catch |err| {
        state.state_mutex.unlock();
        const err_payload = try std.fmt.allocPrint(allocator, "{{\"error\":\"{s}\"}}", .{@errorName(err)});
        defer allocator.free(err_payload);
        if (state.rpc_state.log_enabled) {
            std.debug.print("[webui.window] style error={s}\n", .{@errorName(err)});
        }
        try writeHttpResponse(stream, 400, "application/json; charset=utf-8", err_payload);
        return true;
    };
    const style = state.current_style;
    state.state_mutex.unlock();

    if (state.rpc_state.log_enabled) {
        std.debug.print("[webui.window] style applied frameless={any} transparent={any} corner_radius={any}\n", .{
            style.frameless,
            style.transparent,
            style.corner_radius,
        });
    }

    const payload = try std.json.Stringify.valueAlloc(allocator, style, .{});
    defer allocator.free(payload);
    try writeHttpResponse(stream, 200, "application/json; charset=utf-8", payload);
    return true;
}

fn handleWindowContentRoute(
    state: *WindowState,
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    method: []const u8,
    path_only: []const u8,
) !bool {
    if (!std.mem.eql(u8, method, "GET")) return false;
    if (!std.mem.eql(u8, path_only, "/") and !std.mem.eql(u8, path_only, "/index.html")) return false;

    state.state_mutex.lock();
    defer state.state_mutex.unlock();

    if (state.last_html) |html| {
        try writeHttpResponse(stream, 200, "text/html; charset=utf-8", html);
        return true;
    }

    if (state.last_file) |file_path| {
        const data = std.fs.cwd().readFileAlloc(allocator, file_path, 8 * 1024 * 1024) catch {
            try writeHttpResponse(stream, 500, "text/plain; charset=utf-8", "failed to read file");
            return true;
        };
        defer allocator.free(data);
        try writeHttpResponse(stream, 200, contentTypeForPath(file_path), data);
        return true;
    }

    if (state.last_url) |url| {
        if (isHttpUrl(url)) {
            const redirect = try std.fmt.allocPrint(
                allocator,
                "<html><head><meta http-equiv=\"refresh\" content=\"0; url={s}\" /></head><body>Redirecting...</body></html>",
                .{url},
            );
            defer allocator.free(redirect);
            try writeHttpResponse(stream, 200, "text/html; charset=utf-8", redirect);
            return true;
        }
    }

    try writeHttpResponse(stream, 404, "text/plain; charset=utf-8", "no content");
    return true;
}

fn readHttpRequest(allocator: std.mem.Allocator, stream: std.net.Stream) !HttpRequest {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    var scratch: [4096]u8 = undefined;
    var header_end: ?usize = null;
    var content_length: usize = 0;

    while (true) {
        const read_n = try stream.read(&scratch);
        if (read_n == 0) break;
        try buf.appendSlice(scratch[0..read_n]);

        if (header_end == null) {
            if (std.mem.indexOf(u8, buf.items, "\r\n\r\n")) |idx| {
                header_end = idx + 4;
                content_length = parseContentLength(buf.items[0..idx]) orelse 0;
            }
        }

        if (header_end) |end_idx| {
            if (buf.items.len >= end_idx + content_length) break;
        }

        if (buf.items.len > 16 * 1024 * 1024) return error.RequestTooLarge;
    }

    const raw = try buf.toOwnedSlice();

    const end_idx = header_end orelse return error.InvalidHttpRequest;
    const first_line_end = std.mem.indexOf(u8, raw, "\r\n") orelse return error.InvalidHttpRequest;

    const line = raw[0..first_line_end];
    var line_it = std.mem.splitScalar(u8, line, ' ');
    const method = line_it.next() orelse return error.InvalidHttpRequest;
    const path = line_it.next() orelse return error.InvalidHttpRequest;

    const body_end = end_idx + content_length;
    if (body_end > raw.len) return error.InvalidHttpRequest;

    return .{
        .raw = raw,
        .method = method,
        .path = path,
        .body = raw[end_idx..body_end],
    };
}

fn parseContentLength(headers: []const u8) ?usize {
    var it = std.mem.splitSequence(u8, headers, "\r\n");
    while (it.next()) |line| {
        const sep = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const key = std.mem.trim(u8, line[0..sep], " \t");
        if (!std.ascii.eqlIgnoreCase(key, "Content-Length")) continue;

        const value = std.mem.trim(u8, line[sep + 1 ..], " \t");
        return std.fmt.parseInt(usize, value, 10) catch null;
    }
    return null;
}

fn writeHttpResponse(stream: std.net.Stream, status: u16, content_type: []const u8, body: []const u8) !void {
    var header_buf: [512]u8 = undefined;
    const status_text = switch (status) {
        200 => "OK",
        400 => "Bad Request",
        404 => "Not Found",
        500 => "Internal Server Error",
        else => "OK",
    };

    const header = try std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n",
        .{ status, status_text, content_type, body.len },
    );

    try stream.writeAll(header);
    try stream.writeAll(body);
}

fn contentTypeForPath(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) return "text/html; charset=utf-8";
    if (std.mem.eql(u8, ext, ".js")) return "application/javascript; charset=utf-8";
    if (std.mem.eql(u8, ext, ".css")) return "text/css; charset=utf-8";
    if (std.mem.eql(u8, ext, ".json")) return "application/json; charset=utf-8";
    if (std.mem.eql(u8, ext, ".svg")) return "image/svg+xml";
    if (std.mem.eql(u8, ext, ".png")) return "image/png";
    if (std.mem.eql(u8, ext, ".jpg") or std.mem.eql(u8, ext, ".jpeg")) return "image/jpeg";
    return "application/octet-stream";
}

fn readAllFromStream(allocator: std.mem.Allocator, stream: std.net.Stream, max_bytes: usize) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    var scratch: [4096]u8 = undefined;
    while (true) {
        const n = stream.read(&scratch) catch |err| switch (err) {
            error.ConnectionResetByPeer => break,
            else => return err,
        };
        if (n == 0) break;
        if (out.items.len + n > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(scratch[0..n]);
    }

    return out.toOwnedSlice();
}

fn httpRoundTrip(
    allocator: std.mem.Allocator,
    port: u16,
    method: []const u8,
    path: []const u8,
    body: ?[]const u8,
) ![]u8 {
    const address = try std.net.Address.parseIp4("127.0.0.1", port);
    const stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();

    const request = if (body) |b|
        try std.fmt.allocPrint(
            allocator,
            "{s} {s} HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
            .{ method, path, b.len, b },
        )
    else
        try std.fmt.allocPrint(
            allocator,
            "{s} {s} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n",
            .{ method, path },
        );
    defer allocator.free(request);

    try stream.writeAll(request);
    return readAllFromStream(allocator, stream, 1024 * 1024);
}

test "window lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{});
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "Lifecycle" });
    try win.showHtml("<html>Lifecycle</html>");

    try app.run();
    app.shutdown();
}

test "browser fallback serves window html over local http" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .transport_mode = .browser_fallback,
        .auto_open_browser = false,
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "BrowserFallback" });
    try win.showHtml("<html><body>browser-fallback-ok</body></html>");
    try app.run();

    const local_url = try win.browserUrl();
    defer gpa.allocator().free(local_url);
    try std.testing.expect(std.mem.startsWith(u8, local_url, "http://127.0.0.1:"));

    const address = try std.net.Address.parseIp4("127.0.0.1", win.state().server_port);
    const stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();

    try stream.writeAll(
        "GET / HTTP/1.1\r\n" ++
            "Host: 127.0.0.1\r\n" ++
            "Connection: close\r\n" ++
            "\r\n",
    );

    const response = try readAllFromStream(gpa.allocator(), stream, 1024 * 1024);
    defer gpa.allocator().free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "HTTP/1.1 200 OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "browser-fallback-ok") != null);

    app.shutdown();
}

test "browser fallback server is reachable across repeated connects" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .transport_mode = .browser_fallback,
        .auto_open_browser = false,
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "Reachability" });
    try win.showHtml("<html><body>reachability-ok</body></html>");
    try app.run();

    var attempts: usize = 0;
    while (attempts < 12) : (attempts += 1) {
        const url = try win.browserUrl();
        defer gpa.allocator().free(url);
        try std.testing.expect(std.mem.startsWith(u8, url, "http://127.0.0.1:"));

        const response = try httpRoundTrip(gpa.allocator(), win.state().server_port, "GET", "/", null);
        defer gpa.allocator().free(response);
        try std.testing.expect(std.mem.indexOf(u8, response, "HTTP/1.1 200 OK") != null);
        try std.testing.expect(std.mem.indexOf(u8, response, "reachability-ok") != null);
    }
}

test "native_webview transport falls back to browser rendering by default" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .transport_mode = .native_webview,
        .auto_open_browser = false,
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "NativeFallback" });
    try win.showHtml("<html><body>native-fallback-ok</body></html>");
    try app.run();

    const local_url = try win.browserUrl();
    defer gpa.allocator().free(local_url);
    try std.testing.expect(std.mem.startsWith(u8, local_url, "http://127.0.0.1:"));

    const address = try std.net.Address.parseIp4("127.0.0.1", win.state().server_port);
    const stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();

    try stream.writeAll(
        "GET / HTTP/1.1\r\n" ++
            "Host: 127.0.0.1\r\n" ++
            "Connection: close\r\n" ++
            "\r\n",
    );

    const response = try readAllFromStream(gpa.allocator(), stream, 1024 * 1024);
    defer gpa.allocator().free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "HTTP/1.1 200 OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "native-fallback-ok") != null);

    app.shutdown();
}

test "native_webview browser fallback can be disabled" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .transport_mode = .native_webview,
        .browser_fallback_on_native_failure = false,
        .auto_open_browser = false,
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "NativeOnly" });
    try std.testing.expectError(error.TransportNotBrowserRenderable, win.browserUrl());
}

test "lifecycle config enables heartbeat without tracked child browser" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .transport_mode = .browser_fallback,
        .auto_open_browser = false,
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "LifecycleConfigEnabled" });
    try win.showHtml("<html><body>lifecycle-config</body></html>");
    try app.run();

    const response = try httpRoundTrip(gpa.allocator(), win.state().server_port, "GET", "/webui/lifecycle/config", null);
    defer gpa.allocator().free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"enable_heartbeat\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"heartbeat_interval_ms\":1200") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"heartbeat_hidden_interval_ms\":3000") != null);
}

test "lifecycle config disables heartbeat for lifecycle-linked child launches" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .transport_mode = .browser_fallback,
        .auto_open_browser = false,
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "LifecycleConfigDisabled" });
    try win.showHtml("<html><body>lifecycle-config-child</body></html>");
    try app.run();

    win.state().state_mutex.lock();
    win.state().launched_browser_is_child = true;
    win.state().launched_browser_lifecycle_linked = true;
    win.state().state_mutex.unlock();

    const response = try httpRoundTrip(gpa.allocator(), win.state().server_port, "GET", "/webui/lifecycle/config", null);
    defer gpa.allocator().free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"enable_heartbeat\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"heartbeat_interval_ms\":0") != null);
}

test "linked child exit requests close immediately" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .transport_mode = .native_webview,
        .auto_open_browser = false,
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "ChildExitClose" });
    try win.showHtml("<html><body>child-exit-close</body></html>");
    try app.run();

    var child = std.process.Child.init(&.{ "sh", "-c", "exit 0" }, gpa.allocator());
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    try child.spawn();

    win.state().state_mutex.lock();
    win.state().launched_browser_pid = @as(i64, @intCast(child.id));
    win.state().launched_browser_is_child = true;
    win.state().launched_browser_lifecycle_linked = true;
    win.state().state_mutex.unlock();

    var closed = false;
    var attempts: usize = 0;
    while (attempts < 100) : (attempts += 1) {
        win.state().state_mutex.lock();
        win.state().reconcileChildExit(gpa.allocator());
        const requested = win.state().close_requested.load(.acquire);
        win.state().state_mutex.unlock();
        if (requested) {
            closed = true;
            break;
        }
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    try std.testing.expect(closed);
}

test "window_closing lifecycle event is ignored while tracked browser pid is alive" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .transport_mode = .browser_fallback,
        .auto_open_browser = false,
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "LifecycleCloseAlivePid" });
    try win.showHtml("<html><body>lifecycle-close-alive</body></html>");
    try app.run();

    var child = std.process.Child.init(&.{ "sh", "-c", "sleep 5" }, gpa.allocator());
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    defer {
        std.posix.kill(@as(std.posix.pid_t, @intCast(child.id)), std.posix.SIG.TERM) catch {};
        _ = child.wait() catch {};
    }

    win.state().state_mutex.lock();
    win.state().launched_browser_pid = @as(i64, @intCast(child.id));
    win.state().launched_browser_is_child = true;
    win.state().launched_browser_lifecycle_linked = false;
    win.state().state_mutex.unlock();

    const response = try httpRoundTrip(
        gpa.allocator(),
        win.state().server_port,
        "POST",
        "/webui/lifecycle",
        "{\"event\":\"window_closing\"}",
    );
    defer gpa.allocator().free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "HTTP/1.1 200 OK") != null);

    win.state().state_mutex.lock();
    const should_close = win.state().close_requested.load(.acquire);
    win.state().state_mutex.unlock();
    try std.testing.expect(!should_close);
}

test "non-linked tracked browser pid death requests close" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .transport_mode = .browser_fallback,
        .auto_open_browser = false,
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "TrackedPidExitClose" });
    try win.showHtml("<html><body>tracked-pid-exit-close</body></html>");
    try app.run();

    var child = std.process.Child.init(&.{ "sh", "-c", "sleep 0.02" }, gpa.allocator());
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    defer {
        std.posix.kill(@as(std.posix.pid_t, @intCast(child.id)), std.posix.SIG.TERM) catch {};
        _ = child.wait() catch {};
    }

    win.state().state_mutex.lock();
    win.state().launched_browser_pid = @as(i64, @intCast(child.id));
    win.state().launched_browser_is_child = true;
    win.state().launched_browser_lifecycle_linked = false;
    win.state().state_mutex.unlock();

    var closed = false;
    var attempts: usize = 0;
    while (attempts < 120) : (attempts += 1) {
        win.state().state_mutex.lock();
        win.state().reconcileChildExit(gpa.allocator());
        const requested = win.state().close_requested.load(.acquire);
        win.state().state_mutex.unlock();
        if (requested) {
            closed = true;
            break;
        }
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    try std.testing.expect(closed);
}

test "window style apply updates persisted state" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{});
    defer app.deinit();

    var win = try app.newWindow(.{});
    try win.applyStyle(.{
        .frameless = true,
        .transparent = true,
        .corner_radius = 16,
        .resizable = false,
        .size = .{ .width = 920, .height = 540 },
        .min_size = .{ .width = 640, .height = 400 },
        .position = .{ .x = 22, .y = 44 },
        .icon = .{ .bytes = "icon-bytes", .mime_type = "image/png" },
        .high_contrast = false,
    });

    const style = win.currentStyle();
    try std.testing.expect(style.frameless);
    try std.testing.expect(style.transparent);
    try std.testing.expectEqual(@as(?u16, 16), style.corner_radius);
    try std.testing.expect(!style.resizable);
    try std.testing.expectEqual(@as(?Size, .{ .width = 920, .height = 540 }), style.size);
    try std.testing.expectEqual(@as(?Size, .{ .width = 640, .height = 400 }), style.min_size);
    try std.testing.expectEqual(@as(?Point, .{ .x = 22, .y = 44 }), style.position);
    try std.testing.expectEqual(@as(?bool, false), style.high_contrast);
    try std.testing.expect(style.icon != null);
    try std.testing.expectEqualStrings("image/png", style.icon.?.mime_type);
    try std.testing.expectEqualStrings("icon-bytes", style.icon.?.bytes);
}

test "window control close handler veto and allow" {
    const Hook = struct {
        fn onClose(context: ?*anyopaque, _: usize) bool {
            const allow = @as(*bool, @ptrCast(@alignCast(context.?)));
            return allow.*;
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{});
    defer app.deinit();

    var win = try app.newWindow(.{});
    var allow_close = false;
    win.setCloseHandler(Hook.onClose, &allow_close);

    try std.testing.expectError(error.CloseDenied, win.control(.close));
    try std.testing.expect(!win.state().close_requested.load(.acquire));

    allow_close = true;
    const close_result = try win.control(.close);
    try std.testing.expect(close_result.closed);
    try std.testing.expect(win.state().close_requested.load(.acquire));
}

test "native backend unavailability returns warnings and falls back to emulation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .transport_mode = .native_webview,
        .window_fallback_emulation = true,
        .auto_open_browser = false,
    });
    defer app.deinit();

    var win = try app.newWindow(.{});

    const control_result = try win.control(.maximize);
    try std.testing.expect(control_result.success);
    try std.testing.expectEqualStrings("maximize_fullscreen", control_result.emulation.?);
    try std.testing.expect(control_result.warning != null);
    try std.testing.expect(win.lastWarning() != null);

    try win.applyStyle(.{
        .transparent = true,
        .corner_radius = 14,
    });
    try std.testing.expect(win.lastWarning() == null);
}

test "window capability reporting follows fallback policy" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app_default = try App.init(gpa.allocator(), .{
        .transport_mode = .browser_fallback,
        .window_fallback_emulation = true,
    });
    defer app_default.deinit();
    var win_default = try app_default.newWindow(.{});
    const caps_default = win_default.capabilities();
    try std.testing.expect(caps_default.len > 0);
    try std.testing.expect(window_style_types.hasCapability(.native_frameless, caps_default));

    var app_disabled = try App.init(gpa.allocator(), .{
        .transport_mode = .browser_fallback,
        .window_fallback_emulation = false,
    });
    defer app_disabled.deinit();
    var win_disabled = try app_disabled.newWindow(.{});
    const caps_disabled = win_disabled.capabilities();
    try std.testing.expectEqual(@as(usize, 0), caps_disabled.len);
}

test "window control and style routes roundtrip" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .transport_mode = .browser_fallback,
        .auto_open_browser = false,
    });
    defer app.deinit();

    var win = try app.newWindow(.{});
    try win.showHtml("<html><body>window-routes</body></html>");
    try app.run();

    const caps_res = try httpRoundTrip(gpa.allocator(), win.state().server_port, "GET", "/webui/window/control", null);
    defer gpa.allocator().free(caps_res);
    try std.testing.expect(std.mem.indexOf(u8, caps_res, "\"capabilities\"") != null);

    const ctrl_res = try httpRoundTrip(gpa.allocator(), win.state().server_port, "POST", "/webui/window/control", "{\"cmd\":\"maximize\"}");
    defer gpa.allocator().free(ctrl_res);
    try std.testing.expect(std.mem.indexOf(u8, ctrl_res, "\"success\":true") != null);

    const style_res = try httpRoundTrip(gpa.allocator(), win.state().server_port, "POST", "/webui/window/style", "{\"frameless\":true,\"transparent\":true,\"corner_radius\":11}");
    defer gpa.allocator().free(style_res);
    try std.testing.expect(std.mem.indexOf(u8, style_res, "\"frameless\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, style_res, "\"corner_radius\":11") != null);

    const style_get_res = try httpRoundTrip(gpa.allocator(), win.state().server_port, "GET", "/webui/window/style", null);
    defer gpa.allocator().free(style_get_res);
    try std.testing.expect(std.mem.indexOf(u8, style_get_res, "\"transparent\":true") != null);
}

test "typed rpc registration, invocation, and bridge generation" {
    const DemoRpc = struct {
        pub fn sum(a: i64, b: i64) i64 {
            return a + b;
        }

        pub fn ping() []const u8 {
            return "pong";
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{});
    defer app.deinit();

    var win = try app.newWindow(.{});
    try win.bindRpc(DemoRpc, .{
        .bridge_options = .{
            .namespace = "demoRpc",
            .rpc_route = "/rpc/demo",
        },
    });

    const script = win.rpcClientScript(.{ .namespace = "demoRpc", .rpc_route = "/rpc/demo" });
    try std.testing.expect(std.mem.indexOf(u8, script, "sum: async (arg0, arg1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "__webuiRpcEndpoint = \"/rpc/demo\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "globalThis.__webuiWindowControl") != null);

    const written_path = try std.fmt.allocPrint(gpa.allocator(), ".zig-cache/test_bridge_written_{d}.js", .{std.time.nanoTimestamp()});
    defer gpa.allocator().free(written_path);
    defer std.fs.cwd().deleteFile(written_path) catch {};
    try win.rpc().writeGeneratedClientScript(written_path, .{ .namespace = "demoRpc", .rpc_route = "/rpc/demo" });
    const written_script = try std.fs.cwd().readFileAlloc(gpa.allocator(), written_path, 1024 * 1024);
    defer gpa.allocator().free(written_script);
    try std.testing.expect(std.mem.indexOf(u8, written_script, "async function __webuiInvoke(endpoint, name, args)") != null);

    const dts = win.rpcTypeDeclarations(.{ .namespace = "demoRpc", .rpc_route = "/rpc/demo" });
    try std.testing.expect(std.mem.indexOf(u8, dts, "sum(arg0: number, arg1: number): Promise<number>;") != null);
    try std.testing.expect(std.mem.indexOf(u8, dts, "ping(): Promise<string>;") != null);

    const payload = "{\"name\":\"sum\",\"args\":[2,3]}";
    const result = try win.state().rpc_state.invokeFromJsonPayload(gpa.allocator(), payload);
    defer gpa.allocator().free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"value\":5") != null);
}

test "friendly service api with compile-time rpc_methods constant" {
    const rpc_methods = struct {
        pub fn ping() []const u8 {
            return "pong";
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var service = try Service.init(gpa.allocator(), rpc_methods, .{
        .window = .{
            .title = "Friendly",
        },
    });
    defer service.deinit();

    try service.show(.{ .html = "<html><body>friendly-api-ok</body></html>" });
    try service.run();

    const local_url = try service.browserUrl();
    defer gpa.allocator().free(local_url);
    try std.testing.expect(std.mem.startsWith(u8, local_url, "http://127.0.0.1:"));

    const script_rt = service.rpcClientScript(.{});
    const script_ct = Service.generatedClientScriptComptime(rpc_methods, .{});
    const dts_ct = Service.generatedTypeScriptDeclarationsComptime(rpc_methods, .{});
    try std.testing.expect(std.mem.indexOf(u8, script_rt, "ping: async") != null);
    try std.testing.expect(std.mem.indexOf(u8, script_ct, "ping: async") != null);
    try std.testing.expect(dts_ct.len > 0);
}

test "threaded dispatcher executes rpc on worker queue" {
    const DemoRpc = struct {
        pub fn mul(a: i64, b: i64) i64 {
            return a * b;
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{});
    defer app.deinit();

    var win = try app.newWindow(.{});
    var registry = win.rpc();
    try registry.register(DemoRpc, .{
        .dispatcher_mode = .threaded,
        .threaded_poll_interval_ns = std.time.ns_per_ms,
    });

    const payload = "{\"name\":\"mul\",\"args\":[6,7]}";
    const result = try win.state().rpc_state.invokeFromJsonPayload(gpa.allocator(), payload);
    defer gpa.allocator().free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"value\":42") != null);
}

test "custom dispatcher can wrap default invoker" {
    const DemoRpc = struct {
        pub fn ping() []const u8 {
            return "pong";
        }
    };

    const Hook = struct {
        fn run(
            _: ?*anyopaque,
            _: []const u8,
            invoker: RpcInvokeFn,
            allocator: std.mem.Allocator,
            args: []const std.json.Value,
        ) ![]u8 {
            return invoker(allocator, args);
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{});
    defer app.deinit();

    var win = try app.newWindow(.{});
    var registry = win.rpc();
    try registry.register(DemoRpc, .{
        .dispatcher_mode = .custom,
        .custom_dispatcher = Hook.run,
    });

    const payload = "{\"name\":\"ping\",\"args\":[]}";
    const result = try win.state().rpc_state.invokeFromJsonPayload(gpa.allocator(), payload);
    defer gpa.allocator().free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"value\":\"pong\"") != null);
}

test "comptime bridge generation" {
    const DemoRpc = struct {
        pub fn ping() []const u8 {
            return "pong";
        }

        pub fn sum(a: i64, b: i64) i64 {
            return a + b;
        }
    };

    const script = RpcRegistry.generatedClientScriptComptime(DemoRpc, .{
        .namespace = "demo",
        .rpc_route = "/rpc",
    });
    const dts = RpcRegistry.generatedTypeScriptDeclarationsComptime(DemoRpc, .{
        .namespace = "demo",
        .rpc_route = "/rpc",
    });

    try std.testing.expect(std.mem.indexOf(u8, script, "const demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "sum: async (arg0, arg1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, dts, "export interface WebuiRpcClient") != null);
    try std.testing.expect(std.mem.indexOf(u8, dts, "sum(...args: unknown[]): Promise<unknown>;") != null);
}

test "runtime helper exposes window style/control helpers" {
    try std.testing.expect(std.mem.indexOf(u8, runtime_helpers_js, "webui-window-rounded") == null);
    try std.testing.expect(std.mem.indexOf(u8, runtime_helpers_js, "webui-transparent") != null);
    try std.testing.expect(std.mem.indexOf(u8, runtime_helpers_js, "__webuiWindowStyle") != null);
    try std.testing.expect(std.mem.indexOf(u8, runtime_helpers_js, "__webuiGetWindowStyle") != null);
    try std.testing.expect(std.mem.indexOf(u8, runtime_helpers_js, "__webui_style_scaffold") == null);
    try std.testing.expect(std.mem.indexOf(u8, runtime_helpers_js, "__webuiRefreshAppRegions") == null);
}

test "raw channel callback" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{});
    defer app.deinit();

    var win = try app.newWindow(.{});

    const State = struct {
        var bytes_seen: usize = 0;
        fn onRaw(_: ?*anyopaque, bytes: []const u8) void {
            bytes_seen = bytes.len;
        }
    };

    win.onRaw(State.onRaw, null);
    try win.sendRaw("abc123");
    try std.testing.expectEqual(@as(usize, 6), State.bytes_seen);
}

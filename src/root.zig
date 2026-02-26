const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const bridge_template = @import("bridge/template.zig");
const bridge_runtime_helpers = @import("bridge/runtime_helpers.zig");
const core_runtime = @import("ported/webui.zig");
const browser_discovery = @import("ported/browser_discovery.zig");
const civetweb = @import("ported/civetweb/civetweb.zig");
const tls_runtime = @import("network/tls_runtime.zig");
const websocket = @import("websocket");
pub const process_signals = @import("process_signals.zig");
const window_style_types = @import("window_style.zig");
const webview_backend = @import("ported/webview/backend.zig");
const runtime_requirements = @import("runtime_requirements.zig");

pub const runtime = core_runtime;
pub const http = civetweb;
pub const runtime_helpers_js = bridge_runtime_helpers.embedded_runtime_helpers_js;
pub const runtime_helpers_js_written = bridge_runtime_helpers.written_runtime_helpers_js;
pub const BrowserPromptPreset = core_runtime.BrowserPromptPreset;
pub const BrowserPromptPolicy = core_runtime.BrowserPromptPolicy;
pub const BrowserSurfaceMode = core_runtime.BrowserSurfaceMode;
pub const BrowserFallbackMode = core_runtime.BrowserFallbackMode;
pub const ProfilePathSpec = core_runtime.ProfilePathSpec;
pub const ProfileRuleTarget = core_runtime.ProfileRuleTarget;
pub const ProfileRule = core_runtime.ProfileRule;
pub const BrowserLaunchProfileOwnership = core_runtime.BrowserLaunchProfileOwnership;
pub const BrowserLaunchOptions = core_runtime.BrowserLaunchOptions;
pub const browser_default_profile_path = core_runtime.browser_default_profile_path;
pub const profile_base_prefix_hint = core_runtime.profile_base_prefix_hint;
pub const TlsOptions = tls_runtime.TlsOptions;
pub const TlsInfo = tls_runtime.TlsInfo;

pub fn resolveProfileBasePrefix(allocator: std.mem.Allocator) ![]u8 {
    return core_runtime.resolveProfileBasePrefix(allocator);
}

pub fn defaultWebviewProfilePath(allocator: std.mem.Allocator) ![]u8 {
    return core_runtime.defaultWebviewProfilePath(allocator);
}

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

pub const LaunchSurface = enum {
    native_webview,
    browser_window,
    web_url,
};

pub const LaunchPolicy = struct {
    first: LaunchSurface = .native_webview,
    second: ?LaunchSurface = .browser_window,
    third: ?LaunchSurface = .web_url,
    app_mode_required: bool = true,
    allow_dual_surface: bool = false,

    pub fn webviewFirst() LaunchPolicy {
        return .{
            .first = .native_webview,
            .second = .browser_window,
            .third = .web_url,
        };
    }

    pub fn browserFirst() LaunchPolicy {
        return .{
            .first = .browser_window,
            .second = .web_url,
            .third = .native_webview,
            .app_mode_required = false,
        };
    }

    pub fn webUrlOnly() LaunchPolicy {
        return .{
            .first = .web_url,
            .second = null,
            .third = null,
            .app_mode_required = false,
        };
    }
};

pub const FallbackReason = enum {
    native_backend_unavailable,
    unsupported_style,
    launch_failed,
    dependency_missing,
};

pub const RuntimeRenderState = struct {
    active_transport: TransportMode = .browser_fallback,
    active_surface: LaunchSurface = .web_url,
    fallback_applied: bool = false,
    fallback_reason: ?FallbackReason = null,
    launch_policy: LaunchPolicy = .{},
    using_system_fallback_launcher: bool = false,
    browser_process: ?struct {
        pid: i64,
        kind: ?browser_discovery.BrowserKind,
        lifecycle_linked: bool,
    } = null,
};

pub const DiagnosticCategory = enum {
    transport,
    browser_launch,
    rpc,
    websocket,
    tls,
    lifecycle,
    runtime_requirements,
};

pub const DiagnosticSeverity = enum {
    debug,
    info,
    warn,
    err,
};

pub const Diagnostic = struct {
    code: []const u8,
    category: DiagnosticCategory,
    severity: DiagnosticSeverity,
    message: []const u8,
    window_id: usize,
    timestamp_ms: i64,
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
    client_id: ?usize = null,
    connection_id: ?usize = null,
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

pub const RpcJobNotifyFn = *const fn (context: ?*anyopaque, job_id: RpcJobId, state: RpcJobState) void;

pub const RpcOptions = struct {
    dispatcher_mode: DispatcherMode = .sync,
    custom_dispatcher: ?CustomDispatcher = null,
    custom_context: ?*anyopaque = null,
    bridge_options: BridgeOptions = .{},
    threaded_poll_interval_ns: u64 = 2 * std.time.ns_per_ms,
    execution_mode: RpcExecutionMode = .inline_sync,
    job_queue_capacity: usize = 1024,
    job_default_timeout_ms: ?u32 = null,
    job_result_ttl_ms: u32 = 60_000,
    job_poll_min_ms: u32 = 200,
    job_poll_max_ms: u32 = 1_000,
    push_job_updates: bool = true,
};

pub const AppOptions = struct {
    launch_policy: LaunchPolicy = .{},
    enable_tls: bool = build_options.enable_tls,
    tls: TlsOptions = .{
        .enabled = build_options.enable_tls,
    },
    enable_webui_log: bool = build_options.enable_webui_log,
    public_network: bool = false,
    browser_launch: BrowserLaunchOptions = .{},
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

pub const ScriptTarget = union(enum) {
    window_default,
    client_connection: usize,
};

pub const ScriptOptions = struct {
    target: ScriptTarget = .window_default,
    timeout_ms: ?u32 = null,
};

pub const ScriptEvalResult = struct {
    ok: bool,
    timed_out: bool,
    js_error: bool,
    value: ?[]u8,
    error_message: ?[]u8,
};

pub const RpcExecutionMode = enum {
    inline_sync,
    queued_async,
};

pub const RpcJobId = u64;

pub const RpcJobState = enum {
    queued,
    running,
    completed,
    failed,
    canceled,
    timed_out,
};

pub const RpcJobStatus = struct {
    id: RpcJobId,
    state: RpcJobState,
    value_json: ?[]u8 = null,
    error_message: ?[]u8 = null,
    created_ms: i64,
    updated_ms: i64,
};

pub const RuntimeRequirement = runtime_requirements.RuntimeRequirement;

pub const EffectiveCapabilities = struct {
    transport_if_shown: TransportMode,
    surface_if_shown: LaunchSurface,
    supports_native_window_controls: bool,
    supports_transparency: bool,
    supports_frameless: bool,
    fallback_expected: bool,
};

pub const ServiceOptions = struct {
    app: AppOptions = .{},
    window: WindowOptions = .{},
    rpc: RpcOptions = .{},
};

fn launchPolicyOrder(policy: LaunchPolicy) [3]?LaunchSurface {
    var out: [3]?LaunchSurface = .{ null, null, null };
    var write_idx: usize = 0;
    const input = [_]?LaunchSurface{ policy.first, policy.second, policy.third };
    for (input) |candidate| {
        if (candidate == null) continue;

        var duplicate = false;
        for (out) |existing| {
            if (existing != null and existing.? == candidate.?) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) continue;
        out[write_idx] = candidate.?;
        write_idx += 1;
        if (write_idx >= out.len) break;
    }

    if (out[0] == null) out[0] = .web_url;
    return out;
}

fn launchPolicyContains(policy: LaunchPolicy, surface: LaunchSurface) bool {
    const ordered = launchPolicyOrder(policy);
    for (ordered) |candidate| {
        if (candidate == null) continue;
        if (candidate.? == surface) return true;
    }
    return false;
}

fn launchPolicyNextAfter(policy: LaunchPolicy, current: LaunchSurface) ?LaunchSurface {
    const ordered = launchPolicyOrder(policy);
    var found = false;
    for (ordered) |candidate| {
        if (candidate == null) continue;
        if (!found) {
            if (candidate.? == current) found = true;
            continue;
        }
        return candidate.?;
    }
    return null;
}

const EventCallbackState = struct {
    handler: ?EventHandler = null,
    context: ?*anyopaque = null,
};

pub const DiagnosticHandler = *const fn (context: ?*anyopaque, diagnostic: *const Diagnostic) void;

const DiagnosticCallbackState = struct {
    handler: ?DiagnosticHandler = null,
    context: ?*anyopaque = null,
};

const PinnedStructOwner = enum {
    app,
    service,
};

const DiagnosticCallbackBindingMismatch = struct {
    window_id: usize,
    expected_ptr: usize,
    actual_ptr: usize,
};

fn pinnedMoveGuardEnabled() bool {
    return switch (builtin.mode) {
        .Debug, .ReleaseSafe => true,
        .ReleaseFast, .ReleaseSmall => false,
    };
}

const RawCallbackState = struct {
    handler: ?RawHandler = null,
    context: ?*anyopaque = null,
};

const CloseCallbackState = struct {
    handler: ?CloseHandler = null,
    context: ?*anyopaque = null,
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

const ClientSession = struct {
    token: []u8,
    client_id: usize,
    connection_id: usize,
    last_seen_ms: i64,
};

const RpcJob = struct {
    allocator: std.mem.Allocator,
    id: RpcJobId,
    payload_json: []u8,
    state: RpcJobState = .queued,
    value_json: ?[]u8 = null,
    error_message: ?[]u8 = null,
    cancel_requested: bool = false,
    created_ms: i64,
    updated_ms: i64,

    fn init(allocator: std.mem.Allocator, id: RpcJobId, payload_json: []const u8) !*RpcJob {
        const now_ms = std.time.milliTimestamp();
        const job = try allocator.create(RpcJob);
        job.* = .{
            .allocator = allocator,
            .id = id,
            .payload_json = try allocator.dupe(u8, payload_json),
            .created_ms = now_ms,
            .updated_ms = now_ms,
        };
        return job;
    }

    fn deinit(self: *RpcJob) void {
        self.allocator.free(self.payload_json);
        if (self.value_json) |value| self.allocator.free(value);
        if (self.error_message) |msg| self.allocator.free(msg);
        self.allocator.destroy(self);
    }
};

const ScriptTask = struct {
    allocator: std.mem.Allocator,
    id: u64,
    target_connection: ?usize,
    script: []u8,
    expect_result: bool,
    done: bool = false,
    timed_out: bool = false,
    js_error: bool = false,
    value_json: ?[]u8 = null,
    error_message: ?[]u8 = null,
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},

    fn init(
        allocator: std.mem.Allocator,
        id: u64,
        script: []const u8,
        target_connection: ?usize,
        expect_result: bool,
    ) !*ScriptTask {
        const task = try allocator.create(ScriptTask);
        task.* = .{
            .allocator = allocator,
            .id = id,
            .target_connection = target_connection,
            .script = try allocator.dupe(u8, script),
            .expect_result = expect_result,
        };
        return task;
    }

    fn deinit(self: *ScriptTask) void {
        self.allocator.free(self.script);
        if (self.value_json) |value| self.allocator.free(value);
        if (self.error_message) |msg| self.allocator.free(msg);
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
    invoke_mutex: std.Thread.Mutex,

    queue_mutex: std.Thread.Mutex,
    queue_cond: std.Thread.Condition,
    queue: std.array_list.Managed(*RpcTask),
    worker_thread: ?std.Thread,
    worker_stop: std.atomic.Value(bool),
    worker_lifecycle_mutex: std.Thread.Mutex,
    log_enabled: bool,
    execution_mode: RpcExecutionMode,
    job_queue_capacity: usize,
    job_default_timeout_ms: ?u32,
    job_result_ttl_ms: u32,
    job_poll_min_ms: u32,
    job_poll_max_ms: u32,
    push_job_updates: bool,

    job_mutex: std.Thread.Mutex,
    job_cond: std.Thread.Condition,
    jobs_pending: std.array_list.Managed(*RpcJob),
    jobs_all: std.array_list.Managed(*RpcJob),
    next_job_id: RpcJobId,
    job_worker_thread: ?std.Thread,
    job_worker_stop: std.atomic.Value(bool),
    job_worker_lifecycle_mutex: std.Thread.Mutex,
    job_notify: ?RpcJobNotifyFn,
    job_notify_context: ?*anyopaque,

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
            .invoke_mutex = .{},
            .queue_mutex = .{},
            .queue_cond = .{},
            .queue = std.array_list.Managed(*RpcTask).init(allocator),
            .worker_thread = null,
            .worker_stop = std.atomic.Value(bool).init(false),
            .worker_lifecycle_mutex = .{},
            .log_enabled = log_enabled,
            .execution_mode = .inline_sync,
            .job_queue_capacity = 1024,
            .job_default_timeout_ms = null,
            .job_result_ttl_ms = 60_000,
            .job_poll_min_ms = 200,
            .job_poll_max_ms = 1_000,
            .push_job_updates = true,
            .job_mutex = .{},
            .job_cond = .{},
            .jobs_pending = std.array_list.Managed(*RpcJob).init(allocator),
            .jobs_all = std.array_list.Managed(*RpcJob).init(allocator),
            .next_job_id = 1,
            .job_worker_thread = null,
            .job_worker_stop = std.atomic.Value(bool).init(false),
            .job_worker_lifecycle_mutex = .{},
            .job_notify = null,
            .job_notify_context = null,
        };
    }

    fn deinit(self: *RpcRegistryState, allocator: std.mem.Allocator) void {
        self.stopWorker();
        self.stopJobWorker();

        self.queue_mutex.lock();
        while (self.queue.items.len > 0) {
            const task = self.queue.items[self.queue.items.len - 1];
            _ = self.queue.pop();
            task.deinit();
        }
        self.queue_mutex.unlock();
        self.queue.deinit();

        self.job_mutex.lock();
        while (self.jobs_pending.items.len > 0) {
            const job = self.jobs_pending.items[self.jobs_pending.items.len - 1];
            _ = self.jobs_pending.pop();
            _ = self.removeJobAllLocked(job.id);
            job.deinit();
        }
        while (self.jobs_all.items.len > 0) {
            const job = self.jobs_all.items[self.jobs_all.items.len - 1];
            _ = self.jobs_all.pop();
            job.deinit();
        }
        self.job_mutex.unlock();
        self.jobs_pending.deinit();
        self.jobs_all.deinit();

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
        self.worker_lifecycle_mutex.lock();
        defer self.worker_lifecycle_mutex.unlock();

        if (self.dispatcher_mode != .threaded) return;
        if (self.worker_thread != null) return;

        self.worker_stop.store(false, .release);
        self.worker_thread = try std.Thread.spawn(.{}, rpcWorkerMain, .{self});
    }

    fn stopWorker(self: *RpcRegistryState) void {
        self.worker_lifecycle_mutex.lock();
        defer self.worker_lifecycle_mutex.unlock();

        self.worker_stop.store(true, .release);
        self.queue_cond.broadcast();
        if (self.worker_thread) |thread| {
            thread.join();
            self.worker_thread = null;
        }
    }

    fn ensureJobWorkerStarted(self: *RpcRegistryState) !void {
        self.job_worker_lifecycle_mutex.lock();
        defer self.job_worker_lifecycle_mutex.unlock();

        if (self.execution_mode != .queued_async) return;
        if (self.job_worker_thread != null) return;

        self.job_worker_stop.store(false, .release);
        self.job_worker_thread = try std.Thread.spawn(.{}, rpcJobWorkerMain, .{self});
    }

    fn stopJobWorker(self: *RpcRegistryState) void {
        self.job_worker_lifecycle_mutex.lock();
        defer self.job_worker_lifecycle_mutex.unlock();

        self.job_worker_stop.store(true, .release);
        self.job_cond.broadcast();
        if (self.job_worker_thread) |thread| {
            thread.join();
            self.job_worker_thread = null;
        }
    }

    fn findJobLocked(self: *RpcRegistryState, id: RpcJobId) ?*RpcJob {
        for (self.jobs_all.items) |job| {
            if (job.id == id) return job;
        }
        return null;
    }

    fn removeJobAllLocked(self: *RpcRegistryState, id: RpcJobId) bool {
        for (self.jobs_all.items, 0..) |job, idx| {
            if (job.id != id) continue;
            _ = self.jobs_all.orderedRemove(idx);
            return true;
        }
        return false;
    }

    fn removeJobPendingLocked(self: *RpcRegistryState, id: RpcJobId) bool {
        for (self.jobs_pending.items, 0..) |job, idx| {
            if (job.id != id) continue;
            _ = self.jobs_pending.orderedRemove(idx);
            return true;
        }
        return false;
    }

    fn cleanupExpiredJobsLocked(self: *RpcRegistryState) void {
        if (self.job_result_ttl_ms == 0) return;
        const now_ms = std.time.milliTimestamp();
        var idx: usize = 0;
        while (idx < self.jobs_all.items.len) {
            const job = self.jobs_all.items[idx];
            switch (job.state) {
                .completed, .failed, .canceled, .timed_out => {},
                else => {
                    idx += 1;
                    continue;
                },
            }
            if (now_ms - job.updated_ms < @as(i64, @intCast(self.job_result_ttl_ms))) {
                idx += 1;
                continue;
            }
            _ = self.jobs_all.orderedRemove(idx);
            job.deinit();
        }
    }

    fn enqueueJob(self: *RpcRegistryState, allocator: std.mem.Allocator, payload_json: []const u8) !RpcJobStatus {
        try self.ensureJobWorkerStarted();

        self.job_mutex.lock();
        defer self.job_mutex.unlock();

        self.cleanupExpiredJobsLocked();

        if (self.jobs_pending.items.len >= self.job_queue_capacity) {
            return error.RpcJobQueueFull;
        }

        const job = try RpcJob.init(allocator, self.next_job_id, payload_json);
        self.next_job_id += 1;
        try self.jobs_pending.append(job);
        try self.jobs_all.append(job);
        self.job_cond.signal();

        return .{
            .id = job.id,
            .state = .queued,
            .value_json = null,
            .error_message = null,
            .created_ms = job.created_ms,
            .updated_ms = job.updated_ms,
        };
    }

    fn pollJob(self: *RpcRegistryState, allocator: std.mem.Allocator, job_id: RpcJobId) !RpcJobStatus {
        self.job_mutex.lock();
        defer self.job_mutex.unlock();
        self.cleanupExpiredJobsLocked();
        const job = self.findJobLocked(job_id) orelse return error.UnknownRpcJob;
        return .{
            .id = job.id,
            .state = job.state,
            .value_json = if (job.value_json) |v| try allocator.dupe(u8, v) else null,
            .error_message = if (job.error_message) |e| try allocator.dupe(u8, e) else null,
            .created_ms = job.created_ms,
            .updated_ms = job.updated_ms,
        };
    }

    fn cancelJob(self: *RpcRegistryState, job_id: RpcJobId) !bool {
        self.job_mutex.lock();
        defer self.job_mutex.unlock();

        const job = self.findJobLocked(job_id) orelse return false;
        switch (job.state) {
            .queued => {
                _ = self.removeJobPendingLocked(job_id);
                job.state = .canceled;
                job.updated_ms = std.time.milliTimestamp();
                return true;
            },
            .running => {
                job.cancel_requested = true;
                return true;
            },
            else => return false,
        }
    }

    fn notifyJobUpdate(self: *RpcRegistryState, job: *const RpcJob) void {
        if (!self.push_job_updates) return;
        if (self.job_notify) |hook| {
            hook(self.job_notify_context, job.id, job.state);
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
        const wait_ns = if (self.threaded_poll_interval_ns == 0) std.time.ns_per_ms else self.threaded_poll_interval_ns;
        while (!task.done) {
            task.cond.timedWait(&task.mutex, wait_ns) catch {};
        }

        if (task.err) |err| {
            task.mutex.unlock();
            task.deinit();
            return err;
        }

        const out = task.result_json orelse {
            task.mutex.unlock();
            task.deinit();
            return error.InvalidRpcResult;
        };
        const result = try allocator.dupe(u8, out);
        task.mutex.unlock();
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

    fn rpcJobWorkerMain(self: *RpcRegistryState) void {
        const poll_ns = if (self.threaded_poll_interval_ns == 0) std.time.ns_per_ms else self.threaded_poll_interval_ns;
        while (!self.job_worker_stop.load(.acquire)) {
            self.job_mutex.lock();
            while (self.jobs_pending.items.len == 0 and !self.job_worker_stop.load(.acquire)) {
                self.job_cond.timedWait(&self.job_mutex, poll_ns) catch {};
            }
            if (self.jobs_pending.items.len == 0) {
                self.job_mutex.unlock();
                continue;
            }

            const job = self.jobs_pending.orderedRemove(0);
            job.state = .running;
            job.updated_ms = std.time.milliTimestamp();
            self.job_mutex.unlock();

            const started_ms = std.time.milliTimestamp();
            const result = self.invokeFromJsonPayloadSync(job.allocator, job.payload_json);

            self.job_mutex.lock();
            defer self.job_mutex.unlock();

            if (job.cancel_requested) {
                job.state = .canceled;
                job.updated_ms = std.time.milliTimestamp();
                self.notifyJobUpdate(job);
                continue;
            }

            if (self.job_default_timeout_ms) |timeout_ms| {
                const elapsed = std.time.milliTimestamp() - started_ms;
                if (elapsed > @as(i64, @intCast(timeout_ms))) {
                    job.state = .timed_out;
                    job.updated_ms = std.time.milliTimestamp();
                    self.notifyJobUpdate(job);
                    continue;
                }
            }

            if (result) |value| {
                if (job.value_json) |prev| job.allocator.free(prev);
                job.value_json = value;
                job.state = .completed;
                job.updated_ms = std.time.milliTimestamp();
            } else |err| {
                if (job.error_message) |prev| job.allocator.free(prev);
                job.error_message = std.fmt.allocPrint(job.allocator, "{s}", .{@errorName(err)}) catch null;
                job.state = .failed;
                job.updated_ms = std.time.milliTimestamp();
            }
            self.notifyJobUpdate(job);
        }
    }
};

const default_client_token = "default-client";

const WsConnectionState = struct {
    connection_id: usize,
    stream: std.net.Stream,
};

const WindowState = struct {
    allocator: std.mem.Allocator,
    id: usize,
    title: []u8,
    diagnostic_callback: *DiagnosticCallbackState,
    launch_policy: LaunchPolicy,
    runtime_render_state: RuntimeRenderState,
    window_fallback_emulation: bool,
    server_port: u16,
    server_bind_public: bool,
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
    launched_browser_profile_ownership: BrowserLaunchProfileOwnership,
    last_warning: ?[]const u8,
    next_client_id: usize,
    next_connection_id: usize,
    client_sessions: std.array_list.Managed(ClientSession),
    next_script_id: u64,
    script_pending: std.array_list.Managed(*ScriptTask),
    script_inflight: std.array_list.Managed(*ScriptTask),
    next_close_signal_id: u64,
    last_close_ack_id: u64,
    close_ack_cond: std.Thread.Condition,
    ws_connections: std.array_list.Managed(WsConnectionState),

    state_mutex: std.Thread.Mutex,
    connection_mutex: std.Thread.Mutex,
    connection_cond: std.Thread.Condition,
    active_connection_workers: usize,
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

    fn init(
        allocator: std.mem.Allocator,
        id: usize,
        options: WindowOptions,
        app_options: AppOptions,
        diagnostic_callback: *DiagnosticCallbackState,
    ) !WindowState {
        var state: WindowState = .{
            .allocator = allocator,
            .id = id,
            .title = try allocator.dupe(u8, options.title),
            .diagnostic_callback = diagnostic_callback,
            .launch_policy = app_options.launch_policy,
            .runtime_render_state = .{
                .active_transport = .browser_fallback,
                .active_surface = .web_url,
                .fallback_applied = false,
                .fallback_reason = null,
                .launch_policy = app_options.launch_policy,
                .using_system_fallback_launcher = false,
                .browser_process = null,
            },
            .window_fallback_emulation = app_options.window_fallback_emulation,
            .server_port = 0,
            .server_bind_public = app_options.public_network,
            .last_html = null,
            .last_file = null,
            .last_url = null,
            .shown = false,
            .connected_emitted = false,
            .event_callback = .{},
            .raw_callback = .{},
            .close_callback = .{},
            .rpc_state = RpcRegistryState.init(allocator, app_options.enable_webui_log),
            .backend = webview_backend.NativeBackend.init(launchPolicyContains(app_options.launch_policy, .native_webview)),
            .native_capabilities = &.{},
            .current_style = .{},
            .style_icon_bytes = null,
            .style_icon_mime = null,
            .launched_browser_pid = null,
            .launched_browser_kind = null,
            .launched_browser_is_child = false,
            .launched_browser_lifecycle_linked = false,
            .launched_browser_profile_dir = null,
            .launched_browser_profile_ownership = .none,
            .last_warning = null,
            .next_client_id = 1,
            .next_connection_id = 1,
            .client_sessions = std.array_list.Managed(ClientSession).init(allocator),
            .next_script_id = 1,
            .script_pending = std.array_list.Managed(*ScriptTask).init(allocator),
            .script_inflight = std.array_list.Managed(*ScriptTask).init(allocator),
            .next_close_signal_id = 1,
            .last_close_ack_id = 0,
            .close_ack_cond = .{},
            .ws_connections = std.array_list.Managed(WsConnectionState).init(allocator),
            .state_mutex = .{},
            .connection_mutex = .{},
            .connection_cond = .{},
            .active_connection_workers = 0,
            .server_thread = null,
            .server_stop = std.atomic.Value(bool).init(false),
            .server_ready_mutex = .{},
            .server_ready_cond = .{},
            .server_ready = false,
            .server_listen_ok = false,
            .close_requested = std.atomic.Value(bool).init(false),
        };

        state.resolveActiveTransportLocked();
        state.native_capabilities = state.backend.capabilities();
        try state.setStyleOwned(allocator, options.style);
        if (state.isNativeWindowActive()) {
            state.backend.createWindow(state.id, state.title, state.current_style) catch |err| {
                if (err == error.NativeBackendUnavailable) {
                    if (launchPolicyNextAfter(state.launch_policy, .native_webview)) |next_surface| {
                        state.runtime_render_state.fallback_applied = true;
                        state.runtime_render_state.fallback_reason = .native_backend_unavailable;
                        state.runtime_render_state.active_surface = next_surface;
                        state.runtime_render_state.active_transport = switch (next_surface) {
                            .native_webview => .native_webview,
                            .browser_window, .web_url => .browser_fallback,
                        };
                    }
                }
                if (state.rpc_state.log_enabled) {
                    if (backendWarningForError(err, state.window_fallback_emulation)) |warning| {
                        std.debug.print("[webui.warning] window={d} {s}\n", .{ state.id, warning });
                    }
                }
            };
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

    fn resolveActiveTransportLocked(self: *WindowState) void {
        self.runtime_render_state.launch_policy = self.launch_policy;
        self.runtime_render_state.using_system_fallback_launcher = false;

        const ordered = launchPolicyOrder(self.launch_policy);
        var selected: ?LaunchSurface = null;
        var selected_index: usize = 0;
        var last_fallback_reason: ?FallbackReason = null;

        for (ordered, 0..) |candidate, idx| {
            if (candidate == null) continue;
            switch (candidate.?) {
                .native_webview => {
                    if (!self.backend.isNative()) {
                        last_fallback_reason = .native_backend_unavailable;
                        continue;
                    }
                    selected = .native_webview;
                    selected_index = idx;
                    break;
                },
                .browser_window, .web_url => {
                    selected = candidate.?;
                    selected_index = idx;
                    break;
                },
            }
        }

        const active_surface = selected orelse .web_url;
        self.runtime_render_state.active_surface = active_surface;
        self.runtime_render_state.active_transport = switch (active_surface) {
            .native_webview => .native_webview,
            .browser_window, .web_url => .browser_fallback,
        };
        self.runtime_render_state.fallback_applied = selected == null or selected_index != 0;
        self.runtime_render_state.fallback_reason = if (self.runtime_render_state.fallback_applied) last_fallback_reason else null;
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
        return self.runtime_render_state.active_transport == .native_webview and self.backend.isNative();
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
        if (cmd == .close) {
            self.notifyFrontendCloseLocked("window-control-close", 250);
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

        if (cmd == .close) {
            return .{
                .success = true,
                .emulation = null,
                .closed = true,
                .warning = self.last_warning,
            };
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
            .close => unreachable,
        };
    }

    fn emitDiagnostic(
        self: *WindowState,
        code: []const u8,
        category: DiagnosticCategory,
        severity: DiagnosticSeverity,
        message: []const u8,
    ) void {
        const callback = self.diagnostic_callback.*;
        if (callback.handler) |handler| {
            const diagnostic = Diagnostic{
                .window_id = self.id,
                .code = code,
                .category = category,
                .severity = severity,
                .message = message,
                .timestamp_ms = std.time.milliTimestamp(),
            };
            handler(callback.context, &diagnostic);
        }
    }

    fn shouldServeBrowser(self: *const WindowState) bool {
        if (self.runtime_render_state.active_surface != .native_webview) return true;
        // Native-webview mode still needs the local HTTP/WebSocket runtime so the
        // host process can render and communicate with this window.
        return true;
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
        self.launched_browser_profile_ownership = launch.profile_ownership;
        self.runtime_render_state.using_system_fallback_launcher = launch.used_system_fallback;
        self.runtime_render_state.browser_process = if (launch.pid) |pid|
            .{
                .pid = pid,
                .kind = launch.kind,
                .lifecycle_linked = launch.lifecycle_linked,
            }
        else
            null;

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
            core_runtime.cleanupBrowserProfileDir(allocator, dir, self.launched_browser_profile_ownership);
            self.launched_browser_profile_dir = null;
            self.launched_browser_profile_ownership = .none;
        }
    }

    fn releaseBrowserProfileDirWithoutDelete(self: *WindowState, allocator: std.mem.Allocator) void {
        if (self.launched_browser_profile_dir) |dir| {
            allocator.free(dir);
            self.launched_browser_profile_dir = null;
            self.launched_browser_profile_ownership = .none;
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
        self.runtime_render_state.browser_process = null;
        self.runtime_render_state.using_system_fallback_launcher = false;
    }

    fn clearTrackedBrowserStateWithoutDelete(self: *WindowState, allocator: std.mem.Allocator) void {
        self.launched_browser_pid = null;
        self.launched_browser_kind = null;
        self.launched_browser_is_child = false;
        self.launched_browser_lifecycle_linked = false;
        self.releaseBrowserProfileDirWithoutDelete(allocator);
        self.backend.attachBrowserProcess(null, null, false);
        self.native_capabilities = self.backend.capabilities();
        self.runtime_render_state.browser_process = null;
        self.runtime_render_state.using_system_fallback_launcher = false;
    }

    fn shouldTerminateTrackedBrowserProcess(self: *const WindowState) bool {
        // Browser/web-first runs should close the browser tab via lifecycle signal,
        // not force-kill the whole browser process.
        return self.launch_policy.first == .native_webview;
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

    fn terminateLaunchedBrowser(self: *WindowState, allocator: std.mem.Allocator) void {
        const should_terminate = self.shouldTerminateTrackedBrowserProcess();
        if (self.launched_browser_pid) |pid| {
            if (should_terminate) {
                if (self.rpc_state.log_enabled) {
                    std.debug.print("[webui.browser] terminating tracked browser pid={d}\n", .{pid});
                }
                core_runtime.terminateBrowserProcess(allocator, pid);
            } else if (self.rpc_state.log_enabled) {
                std.debug.print(
                    "[webui.browser] leaving tracked browser pid={d} alive (browser/web mode shutdown)\n",
                    .{pid},
                );
            }
        }
        if (should_terminate) {
            self.clearTrackedBrowserState(allocator);
        } else {
            self.clearTrackedBrowserStateWithoutDelete(allocator);
        }
    }

    fn localRenderUrl(self: *const WindowState, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/", .{self.server_port});
    }

    fn effectiveBrowserLaunchOptions(self: *const WindowState, base: BrowserLaunchOptions) BrowserLaunchOptions {
        var out = base;
        if (self.runtime_render_state.active_surface == .native_webview) {
            // Native-webview mode bootstraps via the platform host process.
            out.surface_mode = .native_webview_host;
            out.fallback_mode = .strict;
            return out;
        }
        if (out.surface_mode == .native_webview_host) {
            // Surface fallback already happened; map to a concrete browser surface.
            out.surface_mode = if (self.runtime_render_state.active_surface == .browser_window) .app_window else .tab;
        }
        return out;
    }

    fn shouldOpenBrowser(self: *const WindowState) bool {
        if (self.runtime_render_state.active_surface == .browser_window) return true;
        if (self.runtime_render_state.active_surface == .native_webview) {
            // Current native backends require a spawned host process to become ready.
            // Bootstrap it on first render even without dual-surface mode.
            if (!self.backend.isReady()) return true;
            if (!self.launch_policy.allow_dual_surface) return false;
            return launchPolicyContains(self.launch_policy, .browser_window);
        }
        return false;
    }

    fn shouldAttemptBrowserSpawnLocked(
        self: *WindowState,
        allocator: std.mem.Allocator,
        local_render: bool,
    ) bool {
        if (!self.shouldOpenBrowser()) return false;

        if (local_render) {
            if (self.launched_browser_pid) |pid| {
                if (core_runtime.isProcessAlive(pid)) return false;
                self.clearTrackedBrowserState(allocator);
            }
        }
        return true;
    }

    fn resolveAfterBrowserLaunchFailure(self: *WindowState, failed_surface: LaunchSurface) bool {
        const next_surface = launchPolicyNextAfter(self.launch_policy, failed_surface) orelse return false;
        self.runtime_render_state.fallback_applied = true;
        self.runtime_render_state.fallback_reason = .launch_failed;
        self.runtime_render_state.active_surface = next_surface;
        self.runtime_render_state.active_transport = switch (next_surface) {
            .native_webview => .native_webview,
            .browser_window, .web_url => .browser_fallback,
        };
        return true;
    }

    fn ensureBrowserRenderState(self: *WindowState, allocator: std.mem.Allocator, app_options: AppOptions) !void {
        if (!self.shouldServeBrowser()) return;
        try self.ensureServerStarted();
        try self.ensureServerReachable();

        const url = try self.localRenderUrl(allocator);
        defer allocator.free(url);
        try replaceOwned(allocator, &self.last_url, url);

        if (self.shouldAttemptBrowserSpawnLocked(allocator, true)) {
            const launch_options = self.effectiveBrowserLaunchOptions(app_options.browser_launch);
            if (core_runtime.openInBrowser(allocator, url, self.current_style, launch_options)) |launch| {
                self.setLaunchedBrowserLaunch(allocator, launch);
            } else |err| {
                _ = self.resolveAfterBrowserLaunchFailure(self.runtime_render_state.active_surface);
                if (self.rpc_state.log_enabled) {
                    std.debug.print("[webui.browser] launch failed error={s}\n", .{@errorName(err)});
                }
                if (self.runtime_render_state.active_surface != .browser_window) return;
                if (self.launch_policy.app_mode_required) return err;
            }
        }
    }

    const ClientRef = struct {
        client_id: usize,
        connection_id: usize,
    };

    fn findOrCreateClientSessionLocked(self: *WindowState, token: []const u8) !ClientRef {
        const now_ms = std.time.milliTimestamp();
        for (self.client_sessions.items) |*session| {
            if (!std.mem.eql(u8, session.token, token)) continue;
            session.last_seen_ms = now_ms;
            return .{
                .client_id = session.client_id,
                .connection_id = session.connection_id,
            };
        }

        const duped = try self.allocator.dupe(u8, token);
        errdefer self.allocator.free(duped);

        const created: ClientSession = .{
            .token = duped,
            .client_id = self.next_client_id,
            .connection_id = self.next_connection_id,
            .last_seen_ms = now_ms,
        };
        self.next_client_id += 1;
        self.next_connection_id += 1;
        try self.client_sessions.append(created);

        return .{
            .client_id = created.client_id,
            .connection_id = created.connection_id,
        };
    }

    fn queueScriptLocked(
        self: *WindowState,
        allocator: std.mem.Allocator,
        script: []const u8,
        target_connection: ?usize,
        expect_result: bool,
    ) !*ScriptTask {
        const task = try ScriptTask.init(allocator, self.next_script_id, script, target_connection, expect_result);
        self.next_script_id += 1;
        try self.script_pending.append(task);
        try self.dispatchPendingScriptTasksLocked();
        return task;
    }

    fn writeSocketAll(handle: std.posix.socket_t, bytes: []const u8) !void {
        var sent: usize = 0;
        while (sent < bytes.len) {
            const n = std.posix.send(handle, bytes[sent..], 0) catch |err| switch (err) {
                error.WouldBlock => {
                    std.Thread.sleep(std.time.ns_per_ms);
                    continue;
                },
                error.BrokenPipe,
                error.ConnectionResetByPeer,
                => return error.Closed,
                else => return err,
            };
            if (n == 0) return error.Closed;
            sent += n;
        }
    }

    fn writeWsFrame(stream: std.net.Stream, opcode: websocket.OpCode, payload: []const u8) !void {
        var header_buf: [10]u8 = undefined;
        const header = websocket.proto.writeFrameHeader(&header_buf, opcode, payload.len, false);
        try writeSocketAll(stream.handle, header);
        if (payload.len > 0) {
            try writeSocketAll(stream.handle, payload);
        }
    }

    fn sendWsTextLocked(_: *WindowState, stream: std.net.Stream, payload: []const u8) !void {
        try writeWsFrame(stream, .text, payload);
    }

    fn registerWsConnectionLocked(self: *WindowState, connection_id: usize, stream: std.net.Stream) !void {
        for (self.ws_connections.items) |*entry| {
            if (entry.connection_id != connection_id) continue;
            entry.stream.close();
            entry.stream = stream;
            return;
        }
        try self.ws_connections.append(.{
            .connection_id = connection_id,
            .stream = stream,
        });
    }

    fn unregisterWsConnectionLocked(self: *WindowState, connection_id: usize) void {
        for (self.ws_connections.items, 0..) |entry, idx| {
            if (entry.connection_id != connection_id) continue;
            _ = self.ws_connections.orderedRemove(idx);
            return;
        }
    }

    fn closeWsConnectionLocked(self: *WindowState, connection_id: usize) void {
        for (self.ws_connections.items, 0..) |entry, idx| {
            if (entry.connection_id != connection_id) continue;
            entry.stream.close();
            _ = self.ws_connections.orderedRemove(idx);
            return;
        }
    }

    fn closeAllWsConnectionsLocked(self: *WindowState) void {
        for (self.ws_connections.items) |entry| {
            entry.stream.close();
        }
        self.ws_connections.clearRetainingCapacity();
    }

    fn findWsConnectionByIdLocked(self: *WindowState, connection_id: usize) ?*WsConnectionState {
        for (self.ws_connections.items) |*entry| {
            if (entry.connection_id == connection_id) return entry;
        }
        return null;
    }

    fn firstWsConnectionLocked(self: *WindowState) ?*WsConnectionState {
        if (self.ws_connections.items.len == 0) return null;
        return &self.ws_connections.items[0];
    }

    fn clientIdForConnectionLocked(self: *const WindowState, connection_id: usize) ?usize {
        for (self.client_sessions.items) |session| {
            if (session.connection_id == connection_id) return session.client_id;
        }
        return null;
    }

    fn dispatchPendingScriptTasksLocked(self: *WindowState) !void {
        var idx: usize = 0;
        while (idx < self.script_pending.items.len) {
            const task = self.script_pending.items[idx];

            const ws_entry = if (task.target_connection) |target_connection|
                self.findWsConnectionByIdLocked(target_connection)
            else
                self.firstWsConnectionLocked();

            if (ws_entry == null) {
                idx += 1;
                continue;
            }

            const entry = ws_entry.?;
            const client_id = self.clientIdForConnectionLocked(entry.connection_id) orelse 0;
            const payload = try std.json.Stringify.valueAlloc(self.allocator, .{
                .type = "script_task",
                .id = task.id,
                .script = task.script,
                .expect_result = task.expect_result,
                .client_id = client_id,
                .connection_id = entry.connection_id,
            }, .{});
            defer self.allocator.free(payload);

            self.sendWsTextLocked(entry.stream, payload) catch |err| {
                if (self.rpc_state.log_enabled) {
                    std.debug.print(
                        "[webui.ws] send failed connection_id={d} err={s}\n",
                        .{ entry.connection_id, @errorName(err) },
                    );
                }
                self.closeWsConnectionLocked(entry.connection_id);
                idx += 1;
                continue;
            };

            _ = self.script_pending.orderedRemove(idx);

            if (task.expect_result) {
                try self.script_inflight.append(task);
            } else {
                task.mutex.lock();
                task.done = true;
                task.cond.signal();
                task.mutex.unlock();
                task.deinit();
            }
        }
    }

    fn onRpcJobUpdated(context: ?*anyopaque, job_id: RpcJobId, state: RpcJobState) void {
        const self = context orelse return;
        const win_state: *WindowState = @ptrCast(@alignCast(self));

        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        if (win_state.ws_connections.items.len == 0) return;

        const payload = std.json.Stringify.valueAlloc(win_state.allocator, .{
            .type = "rpc_job_update",
            .job_id = job_id,
            .state = @tagName(state),
        }, .{}) catch return;
        defer win_state.allocator.free(payload);

        var idx: usize = 0;
        while (idx < win_state.ws_connections.items.len) {
            const entry = win_state.ws_connections.items[idx];
            win_state.sendWsTextLocked(entry.stream, payload) catch {
                win_state.closeWsConnectionLocked(entry.connection_id);
                continue;
            };
            idx += 1;
        }
    }

    fn pushBackendCloseSignalLocked(self: *WindowState, reason: []const u8) !u64 {
        if (self.ws_connections.items.len == 0) return 0;

        const signal_id = self.next_close_signal_id;
        self.next_close_signal_id += 1;

        const payload = try std.json.Stringify.valueAlloc(self.allocator, .{
            .type = "backend_close",
            .id = signal_id,
            .reason = reason,
        }, .{});
        defer self.allocator.free(payload);

        var sent_any = false;
        var idx: usize = 0;
        while (idx < self.ws_connections.items.len) {
            const entry = self.ws_connections.items[idx];
            self.sendWsTextLocked(entry.stream, payload) catch |err| {
                if (self.rpc_state.log_enabled) {
                    std.debug.print(
                        "[webui.ws] close signal write failed connection_id={d} err={s}\n",
                        .{ entry.connection_id, @errorName(err) },
                    );
                }
                self.closeWsConnectionLocked(entry.connection_id);
                continue;
            };
            sent_any = true;
            idx += 1;
        }

        if (!sent_any) return 0;
        return signal_id;
    }

    fn waitForCloseAckLocked(self: *WindowState, signal_id: u64, timeout_ms: u32) bool {
        if (signal_id == 0) return false;
        const timeout_ns: u64 = @as(u64, timeout_ms) * std.time.ns_per_ms;
        const deadline = std.time.nanoTimestamp() + @as(i128, @intCast(timeout_ns));

        while (self.last_close_ack_id < signal_id) {
            const now = std.time.nanoTimestamp();
            if (now >= deadline) break;
            const remaining = @as(u64, @intCast(deadline - now));
            self.close_ack_cond.timedWait(&self.state_mutex, remaining) catch break;
        }
        return self.last_close_ack_id >= signal_id;
    }

    fn notifyFrontendCloseLocked(self: *WindowState, reason: []const u8, timeout_ms: u32) void {
        const signal_id = self.pushBackendCloseSignalLocked(reason) catch 0;
        if (signal_id == 0) return;

        const acked = self.waitForCloseAckLocked(signal_id, timeout_ms);
        if (self.rpc_state.log_enabled) {
            std.debug.print(
                "[webui.ws] close signal id={d} acked={any}\n",
                .{ signal_id, acked },
            );
        }
    }

    fn removeScriptPendingLocked(self: *WindowState, task: *ScriptTask) bool {
        for (self.script_pending.items, 0..) |pending, idx| {
            if (pending != task) continue;
            _ = self.script_pending.orderedRemove(idx);
            return true;
        }
        return false;
    }

    fn removeScriptInflightLocked(self: *WindowState, task: *ScriptTask) bool {
        for (self.script_inflight.items, 0..) |inflight, idx| {
            if (inflight != task) continue;
            _ = self.script_inflight.orderedRemove(idx);
            return true;
        }
        return false;
    }

    fn completeScriptTaskLocked(
        self: *WindowState,
        task_id: u64,
        js_error: bool,
        value_json: ?[]const u8,
        error_message: ?[]const u8,
    ) !bool {
        for (self.script_inflight.items, 0..) |task, idx| {
            if (task.id != task_id) continue;
            _ = self.script_inflight.orderedRemove(idx);

            task.mutex.lock();
            defer task.mutex.unlock();

            if (task.value_json) |buf| {
                task.allocator.free(buf);
                task.value_json = null;
            }
            if (task.error_message) |buf| {
                task.allocator.free(buf);
                task.error_message = null;
            }

            if (value_json) |value| {
                task.value_json = try task.allocator.dupe(u8, value);
            }
            if (error_message) |msg| {
                task.error_message = try task.allocator.dupe(u8, msg);
            }

            task.js_error = js_error;
            task.done = true;
            task.cond.signal();
            return true;
        }
        return false;
    }

    fn markScriptTimedOutLocked(self: *WindowState, task: *ScriptTask) void {
        _ = self.removeScriptPendingLocked(task);
        _ = self.removeScriptInflightLocked(task);
        task.mutex.lock();
        task.timed_out = true;
        task.done = true;
        task.cond.signal();
        task.mutex.unlock();
    }

    fn handleWebSocketClientMessage(self: *WindowState, data: []const u8) !void {
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, data, .{}) catch return;
        defer parsed.deinit();

        if (parsed.value != .object) return;
        const msg_type_value = parsed.value.object.get("type") orelse return;
        if (msg_type_value != .string) return;

        if (std.mem.eql(u8, msg_type_value.string, "close_ack")) {
            const id_value = parsed.value.object.get("id") orelse return;
            const ack_id: u64 = switch (id_value) {
                .integer => |v| @as(u64, @intCast(v)),
                .float => |v| @as(u64, @intFromFloat(v)),
                else => return,
            };

            self.state_mutex.lock();
            if (ack_id > self.last_close_ack_id) {
                self.last_close_ack_id = ack_id;
            }
            self.close_ack_cond.broadcast();
            self.state_mutex.unlock();
            return;
        }

        if (std.mem.eql(u8, msg_type_value.string, "lifecycle")) {
            const event_value = parsed.value.object.get("event") orelse return;
            if (event_value != .string) return;
            if (!std.mem.eql(u8, event_value.string, "window_closing")) return;

            self.state_mutex.lock();
            self.requestLifecycleCloseFromFrontend();
            self.state_mutex.unlock();
            return;
        }

        if (!std.mem.eql(u8, msg_type_value.string, "script_response")) return;

        const id_value = parsed.value.object.get("id") orelse return;
        const task_id: u64 = switch (id_value) {
            .integer => |v| @as(u64, @intCast(v)),
            .float => |v| @as(u64, @intFromFloat(v)),
            else => return,
        };

        const js_error = if (parsed.value.object.get("js_error")) |err_val|
            switch (err_val) {
                .bool => |b| b,
                else => false,
            }
        else
            false;

        const value_json = if (parsed.value.object.get("value")) |value|
            try std.json.Stringify.valueAlloc(self.allocator, value, .{})
        else
            null;
        defer if (value_json) |buf| self.allocator.free(buf);

        const error_message = if (parsed.value.object.get("error_message")) |err_msg|
            switch (err_msg) {
                .string => |msg| msg,
                else => null,
            }
        else
            null;

        self.state_mutex.lock();
        _ = try self.completeScriptTaskLocked(task_id, js_error, value_json, error_message);
        self.state_mutex.unlock();
    }

    fn deinit(self: *WindowState, allocator: std.mem.Allocator) void {
        self.stopServer();

        allocator.free(self.title);

        if (self.last_html) |buf| allocator.free(buf);
        if (self.last_file) |buf| allocator.free(buf);
        if (self.last_url) |buf| allocator.free(buf);
        if (self.style_icon_bytes) |buf| allocator.free(buf);
        if (self.style_icon_mime) |buf| allocator.free(buf);

        for (self.client_sessions.items) |session| allocator.free(session.token);
        self.client_sessions.deinit();

        for (self.script_pending.items) |task| task.deinit();
        self.script_pending.deinit();

        for (self.script_inflight.items) |task| {
            task.mutex.lock();
            task.timed_out = true;
            task.done = true;
            task.cond.broadcast();
            task.mutex.unlock();
            task.deinit();
        }
        self.script_inflight.deinit();
        self.ws_connections.deinit();

        self.terminateLaunchedBrowser(allocator);
        self.backend.destroyWindow();
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

        self.connection_mutex.lock();
        while (self.active_connection_workers > 0) {
            self.connection_cond.timedWait(&self.connection_mutex, 10 * std.time.ns_per_ms) catch {};
        }
        self.connection_mutex.unlock();

        self.state_mutex.lock();
        self.closeAllWsConnectionsLocked();
        self.state_mutex.unlock();
    }

    fn serverThreadMain(self: *WindowState) void {
        const bind_host = if (self.server_bind_public) "0.0.0.0" else "127.0.0.1";
        const address = std.net.Address.parseIp4(bind_host, self.server_port) catch {
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
        self.server_port = server.listen_address.getPort();
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

            self.connection_mutex.lock();
            self.active_connection_workers += 1;
            self.connection_mutex.unlock();

            const thread = std.Thread.spawn(.{}, connectionThreadMain, .{ self, conn.stream }) catch {
                self.connection_mutex.lock();
                self.active_connection_workers -= 1;
                self.connection_cond.broadcast();
                self.connection_mutex.unlock();
                conn.stream.close();
                continue;
            };
            thread.detach();
        }
    }

    fn connectionThreadMain(self: *WindowState, stream: std.net.Stream) void {
        defer {
            self.connection_mutex.lock();
            if (self.active_connection_workers > 0) {
                self.active_connection_workers -= 1;
            }
            self.connection_cond.broadcast();
            self.connection_mutex.unlock();
        }

        const transfer_ownership = handleConnection(self, std.heap.page_allocator, stream) catch {
            stream.close();
            return;
        };
        if (!transfer_ownership) {
            stream.close();
        }
    }
};

pub const App = struct {
    allocator: std.mem.Allocator,
    options: AppOptions,
    tls_state: tls_runtime.Runtime,
    windows: std.array_list.Managed(WindowState),
    shutdown_requested: bool,
    next_window_id: usize,
    diagnostic_callback: DiagnosticCallbackState,

    pub fn init(allocator: std.mem.Allocator, options: AppOptions) !App {
        var resolved_options = options;
        if (resolved_options.enable_tls and !resolved_options.tls.enabled) resolved_options.tls.enabled = true;
        if (resolved_options.tls.enabled and !resolved_options.enable_tls) resolved_options.enable_tls = true;

        core_runtime.initializeRuntime(resolved_options.tls.enabled, resolved_options.enable_webui_log);
        const tls_state = try tls_runtime.Runtime.init(allocator, resolved_options.tls);
        if (resolved_options.tls.enabled and resolved_options.enable_webui_log) {
            std.debug.print(
                "[webui.warning] TLS certificates/runtime state are configured, but active HTTP transport remains plaintext in this build.\n",
                .{},
            );
        }
        return .{
            .allocator = allocator,
            .options = resolved_options,
            .tls_state = tls_state,
            .windows = std.array_list.Managed(WindowState).init(allocator),
            .shutdown_requested = false,
            .next_window_id = 1,
            .diagnostic_callback = .{},
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
        self.tls_state.deinit();
    }

    pub fn setTlsCertificate(self: *App, cert_pem: []const u8, key_pem: []const u8) !void {
        try self.tls_state.setCertificate(cert_pem, key_pem);
        self.options.enable_tls = true;
        self.options.tls.enabled = true;
    }

    pub fn tlsInfo(self: *const App) TlsInfo {
        return self.tls_state.info();
    }

    pub fn onDiagnostic(self: *App, handler: DiagnosticHandler, context: ?*anyopaque) void {
        self.diagnostic_callback = .{
            .handler = handler,
            .context = context,
        };
        for (self.windows.items) |*state| {
            state.state_mutex.lock();
            state.diagnostic_callback = &self.diagnostic_callback;
            state.state_mutex.unlock();
        }
    }

    fn emitDiagnostic(
        self: *App,
        window_id: usize,
        code: []const u8,
        category: DiagnosticCategory,
        severity: DiagnosticSeverity,
        message: []const u8,
    ) void {
        if (self.diagnostic_callback.handler) |handler| {
            const diag = Diagnostic{
                .code = code,
                .category = category,
                .severity = severity,
                .message = message,
                .window_id = window_id,
                .timestamp_ms = std.time.milliTimestamp(),
            };
            handler(self.diagnostic_callback.context, &diag);
        }
    }

    fn firstDiagnosticCallbackBindingMismatch(self: *const App) ?DiagnosticCallbackBindingMismatch {
        const expected = @intFromPtr(&self.diagnostic_callback);
        for (self.windows.items) |*state| {
            const actual = @intFromPtr(state.diagnostic_callback);
            if (actual != expected) {
                return .{
                    .window_id = state.id,
                    .expected_ptr = expected,
                    .actual_ptr = actual,
                };
            }
        }
        return null;
    }

    fn hasStableDiagnosticCallbackBindings(self: *const App) bool {
        return self.firstDiagnosticCallbackBindingMismatch() == null;
    }

    fn checkPinnedMoveInvariant(self: *App, owner: PinnedStructOwner, fail_fast: bool) bool {
        if (comptime !pinnedMoveGuardEnabled()) return true;
        if (self.diagnostic_callback.handler == null) return true;

        const mismatch = self.firstDiagnosticCallbackBindingMismatch() orelse return true;
        const code = switch (owner) {
            .app => "lifecycle.pinned_struct_moved.app",
            .service => "lifecycle.pinned_struct_moved.service",
        };
        const owner_label = switch (owner) {
            .app => "App",
            .service => "Service",
        };
        var message_buf: [320]u8 = undefined;
        const message = std.fmt.bufPrint(
            &message_buf,
            "{s} was moved after window initialization. Keep initialized structs in final storage and pass pointers only (window_id={d}, expected=0x{x}, actual=0x{x}).",
            .{ owner_label, mismatch.window_id, mismatch.expected_ptr, mismatch.actual_ptr },
        ) catch "Pinned struct move detected. Keep initialized structs in final storage and pass pointers only.";
        self.emitDiagnostic(mismatch.window_id, code, .lifecycle, .err, message);
        if (fail_fast) std.debug.panic("{s}", .{message});
        return false;
    }

    fn enforcePinnedMoveInvariant(self: *App, owner: PinnedStructOwner) void {
        _ = self.checkPinnedMoveInvariant(owner, true);
    }

    pub fn newWindow(self: *App, options: WindowOptions) !Window {
        self.enforcePinnedMoveInvariant(.app);
        const id = options.window_id orelse self.next_window_id;
        if (id == 0) return error.InvalidWindowId;

        if (options.window_id) |explicit_id| {
            if (explicit_id >= self.next_window_id) {
                self.next_window_id = explicit_id + 1;
            }
        } else {
            self.next_window_id += 1;
        }

        try self.windows.append(try WindowState.init(self.allocator, id, options, self.options, &self.diagnostic_callback));
        for (self.windows.items, 0..) |*state, idx_iter| {
            _ = idx_iter;
            state.rpc_state.job_notify = WindowState.onRpcJobUpdated;
            state.rpc_state.job_notify_context = state;
        }
        const idx = self.windows.items.len - 1;

        return .{
            .app = self,
            .index = idx,
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
        self.enforcePinnedMoveInvariant(.app);
        if (self.shutdown_requested) return;

        for (self.windows.items) |*state| {
            if (!state.shown or state.connected_emitted) continue;

            if (state.last_html != null or state.last_file != null) {
                try state.ensureServerStarted();
            }

            if (state.isNativeWindowActive()) {
                state.backend.pumpEvents() catch {};
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
        self.enforcePinnedMoveInvariant(.app);
        self.shutdown_requested = true;

        for (self.windows.items) |*state| {
            state.state_mutex.lock();
            state.close_requested.store(true, .release);
            state.notifyFrontendCloseLocked("app-shutdown", 250);
            state.state_mutex.unlock();
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
        self.app.enforcePinnedMoveInvariant(.app);
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
        if (win_state.isNativeWindowActive()) {
            if (win_state.last_url) |url| {
                _ = win_state.backend.showContent(.{ .url = url }) catch {};
            }
        }

        self.emitRuntimeDiagnostics();
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
        self.app.enforcePinnedMoveInvariant(.app);
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
        if (win_state.isNativeWindowActive()) {
            if (win_state.last_url) |url| {
                _ = win_state.backend.showContent(.{ .url = url }) catch {};
            }
        }

        self.emitRuntimeDiagnostics();
        self.emit(.navigation, "show-file", path);
    }

    pub fn showUrl(self: *Window, url: []const u8) !void {
        self.app.enforcePinnedMoveInvariant(.app);
        if (!isLikelyUrl(url)) return error.InvalidUrl;

        const win_state = self.state();

        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();

        try replaceOwned(self.app.allocator, &win_state.last_url, url);
        win_state.shown = true;

        if (win_state.isNativeWindowActive()) {
            _ = win_state.backend.showContent(.{ .url = url }) catch {};
        }

        if (win_state.shouldAttemptBrowserSpawnLocked(self.app.allocator, false)) {
            const launch_options = win_state.effectiveBrowserLaunchOptions(self.app.options.browser_launch);
            if (core_runtime.openInBrowser(self.app.allocator, url, win_state.current_style, launch_options)) |launch| {
                win_state.setLaunchedBrowserLaunch(self.app.allocator, launch);
            } else |err| {
                _ = win_state.resolveAfterBrowserLaunchFailure(win_state.runtime_render_state.active_surface);
                if (win_state.rpc_state.log_enabled) {
                    std.debug.print("[webui.browser] launch failed error={s}\n", .{@errorName(err)});
                }
                if (win_state.runtime_render_state.active_surface == .browser_window and win_state.launch_policy.app_mode_required) return err;
            }
        }

        self.emitRuntimeDiagnostics();
        self.emit(.navigation, "show-url", url);
    }

    pub fn navigate(self: *Window, url: []const u8) !void {
        self.app.enforcePinnedMoveInvariant(.app);
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

    pub fn runScript(self: *Window, script: []const u8, options: ScriptOptions) !void {
        if (script.len == 0) return error.EmptyScript;

        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();

        const target_connection: ?usize = switch (options.target) {
            .window_default => null,
            .client_connection => |connection_id| connection_id,
        };
        _ = try win_state.queueScriptLocked(self.app.allocator, script, target_connection, false);
    }

    pub fn evalScript(
        self: *Window,
        allocator: std.mem.Allocator,
        script: []const u8,
        options: ScriptOptions,
    ) !ScriptEvalResult {
        if (script.len == 0) return error.EmptyScript;

        const win_state = self.state();

        win_state.state_mutex.lock();
        const target_connection: ?usize = switch (options.target) {
            .window_default => null,
            .client_connection => |connection_id| connection_id,
        };
        const task = try win_state.queueScriptLocked(self.app.allocator, script, target_connection, true);
        win_state.state_mutex.unlock();

        var timed_out = false;
        task.mutex.lock();

        if (options.timeout_ms) |timeout_ms| {
            const timeout_ns: u64 = @as(u64, timeout_ms) * std.time.ns_per_ms;
            const deadline = std.time.nanoTimestamp() + @as(i128, @intCast(timeout_ns));
            while (!task.done) {
                const now = std.time.nanoTimestamp();
                if (now >= deadline) {
                    timed_out = true;
                    break;
                }
                const remaining = @as(u64, @intCast(deadline - now));
                task.cond.timedWait(&task.mutex, remaining) catch {};
            }
        } else {
            while (!task.done) task.cond.wait(&task.mutex);
        }
        const finished = task.done;
        task.mutex.unlock();

        if (timed_out and !finished) {
            win_state.state_mutex.lock();
            win_state.markScriptTimedOutLocked(task);
            win_state.state_mutex.unlock();
        }

        task.mutex.lock();
        const result = ScriptEvalResult{
            .ok = !task.js_error and !timed_out,
            .timed_out = timed_out or task.timed_out,
            .js_error = task.js_error,
            .value = if (task.value_json) |value| try allocator.dupe(u8, value) else null,
            .error_message = if (task.error_message) |msg| try allocator.dupe(u8, msg) else null,
        };
        task.mutex.unlock();

        win_state.state_mutex.lock();
        _ = win_state.removeScriptPendingLocked(task);
        _ = win_state.removeScriptInflightLocked(task);
        win_state.state_mutex.unlock();
        task.deinit();

        return result;
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
        self.app.enforcePinnedMoveInvariant(.app);
        const win_state = self.state();
        if (!win_state.shouldServeBrowser()) return error.TransportNotBrowserRenderable;

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
        self.app.enforcePinnedMoveInvariant(.app);
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        if (!win_state.shouldServeBrowser()) return error.TransportNotBrowserRenderable;

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

    pub fn runtimeRenderState(self: *Window) RuntimeRenderState {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        return win_state.runtime_render_state;
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

    pub fn probeCapabilities(self: *Window) EffectiveCapabilities {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();

        const ordered = launchPolicyOrder(win_state.launch_policy);
        var predicted_surface: LaunchSurface = .web_url;
        var selected_index: usize = 0;
        var found = false;
        for (ordered, 0..) |candidate, idx| {
            if (candidate == null) continue;
            switch (candidate.?) {
                .native_webview => {
                    if (!win_state.backend.isNative()) continue;
                    predicted_surface = .native_webview;
                    selected_index = idx;
                    found = true;
                    break;
                },
                .browser_window, .web_url => {
                    predicted_surface = candidate.?;
                    selected_index = idx;
                    found = true;
                    break;
                },
            }
        }

        const predicted_transport: TransportMode = switch (predicted_surface) {
            .native_webview => .native_webview,
            .browser_window, .web_url => .browser_fallback,
        };

        const caps = win_state.capabilities();
        return .{
            .transport_if_shown = predicted_transport,
            .surface_if_shown = predicted_surface,
            .supports_native_window_controls = window_style_types.hasCapability(.native_minmax, caps),
            .supports_transparency = window_style_types.hasCapability(.native_transparency, caps),
            .supports_frameless = window_style_types.hasCapability(.native_frameless, caps),
            .fallback_expected = !found or selected_index != 0,
        };
    }

    pub fn rpcPollJob(self: *Window, allocator: std.mem.Allocator, job_id: RpcJobId) !RpcJobStatus {
        return self.state().rpc_state.pollJob(allocator, job_id);
    }

    pub fn rpcCancelJob(self: *Window, job_id: RpcJobId) !bool {
        return self.state().rpc_state.cancelJob(job_id);
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

    fn emitRuntimeDiagnostics(self: *Window) void {
        const win_state = self.state();
        const render_state = win_state.runtime_render_state;

        const transport_code, const transport_message = switch (render_state.active_transport) {
            .native_webview => .{ "transport.active.native_webview", "Native webview transport selected" },
            .browser_fallback => .{ "transport.active.browser_fallback", "Browser fallback transport selected" },
        };
        self.app.emitDiagnostic(self.id, transport_code, .transport, .info, transport_message);

        if (render_state.fallback_applied) {
            const reason = render_state.fallback_reason orelse .native_backend_unavailable;
            const code = switch (reason) {
                .native_backend_unavailable => "fallback.native_backend_unavailable",
                .unsupported_style => "fallback.unsupported_style",
                .launch_failed => "fallback.launch_failed",
                .dependency_missing => "fallback.dependency_missing",
            };
            const message = switch (reason) {
                .native_backend_unavailable => "Native backend unavailable; browser fallback applied",
                .unsupported_style => "Requested style unsupported; browser fallback applied",
                .launch_failed => "Browser launch failed while resolving launch policy",
                .dependency_missing => "Runtime dependency missing; browser fallback applied",
            };
            self.app.emitDiagnostic(self.id, code, .transport, .warn, message);
        }

        if (render_state.using_system_fallback_launcher) {
            self.app.emitDiagnostic(
                self.id,
                "browser.system_fallback_launcher",
                .browser_launch,
                .info,
                "System fallback launcher was used",
            );
        }
    }
};

pub const Service = struct {
    app: App,
    window_index: usize,
    window_id: usize,

    pub inline fn init(allocator: std.mem.Allocator, comptime rpc_methods: type, options: ServiceOptions) !Service {
        var service: Service = undefined;
        service.app = try App.init(allocator, options.app);
        errdefer service.app.deinit();

        var main_window = try service.app.newWindow(options.window);
        try main_window.bindRpc(rpc_methods, options.rpc);

        service.window_index = main_window.index;
        service.window_id = main_window.id;
        return service;
    }

    pub fn initDefault(allocator: std.mem.Allocator, comptime rpc_methods: type) !Service {
        return init(allocator, rpc_methods, .{});
    }

    pub fn deinit(self: *Service) void {
        self.app.deinit();
    }

    pub fn window(self: *Service) Window {
        self.enforcePinnedMoveInvariant();
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

    pub fn setTlsCertificate(self: *Service, cert_pem: []const u8, key_pem: []const u8) !void {
        try self.app.setTlsCertificate(cert_pem, key_pem);
    }

    pub fn tlsInfo(self: *Service) TlsInfo {
        return self.app.tlsInfo();
    }

    pub fn onDiagnostic(self: *Service, handler: DiagnosticHandler, context: ?*anyopaque) void {
        self.app.onDiagnostic(handler, context);
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

    pub fn runtimeRenderState(self: *Service) RuntimeRenderState {
        var win = self.window();
        return win.runtimeRenderState();
    }

    pub fn probeCapabilities(self: *Service) EffectiveCapabilities {
        var win = self.window();
        return win.probeCapabilities();
    }

    pub fn listRuntimeRequirements(self: *Service, allocator: std.mem.Allocator) ![]RuntimeRequirement {
        var win = self.window();
        const win_state = win.state();
        win_state.state_mutex.lock();
        const native_available = win_state.backend.isNative();
        const policy = self.app.options.launch_policy;
        win_state.state_mutex.unlock();

        const reqs = try runtime_requirements.list(allocator, .{
            .uses_native_webview = launchPolicyContains(policy, .native_webview),
            .uses_managed_browser = launchPolicyContains(policy, .browser_window),
            .uses_web_url = launchPolicyContains(policy, .web_url),
            .app_mode_required = policy.app_mode_required,
            .native_backend_available = native_available,
        });
        for (reqs) |req| {
            if (req.required and !req.available) {
                const message = req.details orelse "required runtime dependency unavailable";
                self.app.emitDiagnostic(self.window_id, req.name, .lifecycle, .warn, message);
            }
        }
        return reqs;
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

    pub fn runScript(self: *Service, script: []const u8, options: ScriptOptions) !void {
        var win = self.window();
        try win.runScript(script, options);
    }

    pub fn evalScript(
        self: *Service,
        allocator: std.mem.Allocator,
        script: []const u8,
        options: ScriptOptions,
    ) !ScriptEvalResult {
        var win = self.window();
        return win.evalScript(allocator, script, options);
    }

    pub fn rpcPollJob(self: *Service, allocator: std.mem.Allocator, job_id: RpcJobId) !RpcJobStatus {
        var win = self.window();
        return win.rpcPollJob(allocator, job_id);
    }

    pub fn rpcCancelJob(self: *Service, job_id: RpcJobId) !bool {
        var win = self.window();
        return win.rpcCancelJob(job_id);
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

    fn hasStableDiagnosticCallbackBindings(self: *const Service) bool {
        return self.app.hasStableDiagnosticCallbackBindings();
    }

    fn checkPinnedMoveInvariant(self: *Service, fail_fast: bool) bool {
        return self.app.checkPinnedMoveInvariant(.service, fail_fast);
    }

    fn enforcePinnedMoveInvariant(self: *Service) void {
        _ = self.checkPinnedMoveInvariant(true);
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
        self.state.execution_mode = options.execution_mode;
        self.state.job_queue_capacity = options.job_queue_capacity;
        self.state.job_default_timeout_ms = options.job_default_timeout_ms;
        self.state.job_result_ttl_ms = options.job_result_ttl_ms;
        self.state.job_poll_min_ms = options.job_poll_min_ms;
        self.state.job_poll_max_ms = options.job_poll_max_ms;
        self.state.push_job_updates = options.push_job_updates;

        if (self.state.dispatcher_mode == .threaded) {
            try self.state.ensureWorkerStarted();
        }
        if (self.state.execution_mode == .queued_async) {
            try self.state.ensureJobWorkerStarted();
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
    headers: []const u8,
    body: []const u8,
};

const WsInboundType = enum {
    text,
    binary,
    ping,
    pong,
    close,
};

const WsInboundFrame = struct {
    kind: WsInboundType,
    payload: []u8,
};

fn readSocketExact(handle: std.posix.socket_t, out: []u8) !void {
    var offset: usize = 0;
    while (offset < out.len) {
        const n = std.posix.recv(handle, out[offset..], 0) catch |err| switch (err) {
            error.WouldBlock => {
                std.Thread.sleep(std.time.ns_per_ms);
                continue;
            },
            error.ConnectionResetByPeer,
            error.ConnectionTimedOut,
            error.SocketNotConnected,
            => return error.Closed,
            else => return err,
        };
        if (n == 0) return error.Closed;
        offset += n;
    }
}

fn decodeWsOpcode(byte: u8) !WsInboundType {
    return switch (byte & 0x0F) {
        0x1 => .text,
        0x2 => .binary,
        0x8 => .close,
        0x9 => .ping,
        0xA => .pong,
        else => error.UnsupportedWebSocketOpcode,
    };
}

fn readWsInboundFrameAlloc(allocator: std.mem.Allocator, stream: std.net.Stream, max_payload_size: usize) !WsInboundFrame {
    var header: [2]u8 = undefined;
    try readSocketExact(stream.handle, &header);

    const fin = (header[0] & 0x80) != 0;
    if (!fin) return error.UnsupportedWebSocketFragmentation;

    const kind = try decodeWsOpcode(header[0]);
    const masked = (header[1] & 0x80) != 0;
    if (!masked) return error.InvalidWebSocketMasking;

    var payload_len_u64: u64 = header[1] & 0x7F;
    if (payload_len_u64 == 126) {
        var ext: [2]u8 = undefined;
        try readSocketExact(stream.handle, &ext);
        payload_len_u64 = (@as(u64, ext[0]) << 8) | @as(u64, ext[1]);
    } else if (payload_len_u64 == 127) {
        var ext: [8]u8 = undefined;
        try readSocketExact(stream.handle, &ext);
        payload_len_u64 =
            (@as(u64, ext[0]) << 56) |
            (@as(u64, ext[1]) << 48) |
            (@as(u64, ext[2]) << 40) |
            (@as(u64, ext[3]) << 32) |
            (@as(u64, ext[4]) << 24) |
            (@as(u64, ext[5]) << 16) |
            (@as(u64, ext[6]) << 8) |
            (@as(u64, ext[7]));
    }

    if (payload_len_u64 > max_payload_size) return error.WebSocketMessageTooLarge;
    const payload_len: usize = @intCast(payload_len_u64);

    var masking_key: [4]u8 = undefined;
    try readSocketExact(stream.handle, &masking_key);

    const payload = try allocator.alloc(u8, payload_len);
    errdefer allocator.free(payload);

    if (payload_len > 0) {
        try readSocketExact(stream.handle, payload);
        for (payload, 0..) |byte, i| {
            payload[i] = byte ^ masking_key[i & 3];
        }
    }

    return .{
        .kind = kind,
        .payload = payload,
    };
}

fn containsTokenIgnoreCase(value: []const u8, token: []const u8) bool {
    var it = std.mem.splitScalar(u8, value, ',');
    while (it.next()) |part| {
        const normalized = std.mem.trim(u8, part, " \t");
        if (std.ascii.eqlIgnoreCase(normalized, token)) return true;
    }
    return false;
}

fn writeWebSocketHandshakeResponse(stream: std.net.Stream, sec_key: []const u8) !void {
    var sha1_digest: [20]u8 = undefined;
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(sec_key);
    hasher.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    hasher.final(&sha1_digest);

    var accept_key: [28]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(&accept_key, &sha1_digest);

    var response_buf: [512]u8 = undefined;
    const response = try std.fmt.bufPrint(
        &response_buf,
        "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: {s}\r\n\r\n",
        .{accept_key},
    );

    try WindowState.writeSocketAll(stream.handle, response);
}

fn wsConnectionThreadMain(state: *WindowState, stream: std.net.Stream, connection_id: usize) void {
    defer {
        state.state_mutex.lock();
        state.unregisterWsConnectionLocked(connection_id);
        state.state_mutex.unlock();
        stream.close();
        state.emitDiagnostic("websocket.disconnected", .websocket, .info, "WebSocket client disconnected");

        if (state.rpc_state.log_enabled) {
            std.debug.print("[webui.ws] disconnected connection_id={d}\n", .{connection_id});
        }
    }

    while (!state.server_stop.load(.acquire)) {
        const frame = readWsInboundFrameAlloc(state.allocator, stream, 8 * 1024 * 1024) catch |err| {
            if (state.rpc_state.log_enabled and err != error.Closed) {
                std.debug.print("[webui.ws] read failed connection_id={d} err={s}\n", .{ connection_id, @errorName(err) });
            }
            if (err != error.Closed) {
                state.emitDiagnostic("websocket.read_error", .websocket, .warn, @errorName(err));
            }
            return;
        };
        defer state.allocator.free(frame.payload);

        switch (frame.kind) {
            .text, .binary => {
                state.handleWebSocketClientMessage(frame.payload) catch |err| {
                    if (state.rpc_state.log_enabled) {
                        std.debug.print("[webui.ws] message handling failed connection_id={d} err={s}\n", .{ connection_id, @errorName(err) });
                    }
                };
            },
            .ping => {
                WindowState.writeWsFrame(stream, .pong, frame.payload) catch return;
            },
            .pong => {},
            .close => {
                WindowState.writeWsFrame(stream, .close, frame.payload) catch {};
                return;
            },
        }
    }
}

fn handleWebSocketUpgradeRoute(state: *WindowState, stream: std.net.Stream, request: HttpRequest, path_only: []const u8) !bool {
    if (!std.mem.eql(u8, request.method, "GET")) return false;
    if (!std.mem.eql(u8, path_only, "/webui/ws")) return false;

    const upgrade = httpHeaderValue(request.headers, "Upgrade") orelse {
        try writeHttpResponse(stream, 400, "text/plain; charset=utf-8", "missing Upgrade header");
        return false;
    };
    if (!std.ascii.eqlIgnoreCase(upgrade, "websocket")) {
        try writeHttpResponse(stream, 400, "text/plain; charset=utf-8", "invalid Upgrade header");
        return false;
    }

    const connection = httpHeaderValue(request.headers, "Connection") orelse {
        try writeHttpResponse(stream, 400, "text/plain; charset=utf-8", "missing Connection header");
        return false;
    };
    if (!containsTokenIgnoreCase(connection, "upgrade")) {
        try writeHttpResponse(stream, 400, "text/plain; charset=utf-8", "invalid Connection header");
        return false;
    }

    const version = httpHeaderValue(request.headers, "Sec-WebSocket-Version") orelse {
        try writeHttpResponse(stream, 400, "text/plain; charset=utf-8", "missing Sec-WebSocket-Version header");
        return false;
    };
    if (!std.mem.eql(u8, std.mem.trim(u8, version, " \t"), "13")) {
        try writeHttpResponse(stream, 400, "text/plain; charset=utf-8", "unsupported websocket version");
        return false;
    }

    const sec_key = httpHeaderValue(request.headers, "Sec-WebSocket-Key") orelse {
        try writeHttpResponse(stream, 400, "text/plain; charset=utf-8", "missing Sec-WebSocket-Key header");
        return false;
    };

    try writeWebSocketHandshakeResponse(stream, sec_key);

    const token = wsClientTokenFromUrl(request.path);
    var connection_id: usize = 0;
    state.state_mutex.lock();
    {
        const client_ref = try state.findOrCreateClientSessionLocked(token);
        connection_id = client_ref.connection_id;
        try state.registerWsConnectionLocked(connection_id, stream);
        try state.dispatchPendingScriptTasksLocked();
    }
    state.state_mutex.unlock();

    if (state.rpc_state.log_enabled) {
        std.debug.print("[webui.ws] connected connection_id={d}\n", .{connection_id});
    }
    state.emitDiagnostic("websocket.connected", .websocket, .info, "WebSocket client connected");

    const thread = try std.Thread.spawn(.{}, wsConnectionThreadMain, .{ state, stream, connection_id });
    thread.detach();
    return true;
}

fn handleConnection(state: *WindowState, allocator: std.mem.Allocator, stream: std.net.Stream) !bool {
    const request = try readHttpRequest(allocator, stream);
    defer allocator.free(request.raw);

    const path_only = pathWithoutQuery(request.path);
    if (try handleWebSocketUpgradeRoute(state, stream, request, path_only)) return true;

    if (try handleBridgeScriptRoute(state, allocator, stream, request.method, path_only)) return false;
    if (try handleRpcRoute(state, allocator, stream, request.method, path_only, request.headers, request.body)) return false;
    if (try handleRpcJobRoute(state, allocator, stream, request.method, request.path, path_only)) return false;
    if (try handleRpcJobCancelRoute(state, allocator, stream, request.method, path_only, request.body)) return false;
    if (try handleLifecycleRoute(state, allocator, stream, request.method, path_only, request.headers, request.body)) return false;
    if (try handleScriptResponseRoute(state, allocator, stream, request.method, path_only, request.body)) return false;
    if (try handleWindowControlRoute(state, allocator, stream, request.method, path_only, request.body)) return false;
    if (try handleWindowStyleRoute(state, allocator, stream, request.method, path_only, request.body)) return false;
    if (try handleWindowContentRoute(state, allocator, stream, request.method, path_only)) return false;

    try writeHttpResponse(stream, 404, "text/plain; charset=utf-8", "not found");
    return false;
}

fn handleLifecycleRoute(
    state: *WindowState,
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    method: []const u8,
    path_only: []const u8,
    headers: []const u8,
    body: []const u8,
) !bool {
    if (!std.mem.eql(u8, method, "POST")) return false;
    if (!std.mem.eql(u8, path_only, "/webui/lifecycle")) return false;

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch null;
    var logged_event = false;
    const client_token = httpHeaderValue(headers, "x-webui-client-id") orelse default_client_token;
    state.state_mutex.lock();
    _ = state.findOrCreateClientSessionLocked(client_token) catch null;
    state.state_mutex.unlock();
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
                    if (state.rpc_state.log_enabled) {
                        std.debug.print("[webui.lifecycle] event={s}\n", .{event_value.string});
                        logged_event = true;
                    }
                }
            }
        }
    }

    if (state.rpc_state.log_enabled and !logged_event) {
        std.debug.print("[webui.lifecycle] body={s}\n", .{body});
    }

    try writeHttpResponse(stream, 200, "application/json; charset=utf-8", "{\"ok\":true}");
    return true;
}

fn handleScriptResponseRoute(
    state: *WindowState,
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    method: []const u8,
    path_only: []const u8,
    body: []const u8,
) !bool {
    if (!std.mem.eql(u8, method, "POST")) return false;
    if (!std.mem.eql(u8, path_only, "/webui/script/response")) return false;

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        try writeHttpResponse(stream, 400, "application/json; charset=utf-8", "{\"error\":\"invalid_script_response\"}");
        return true;
    };
    defer parsed.deinit();

    if (parsed.value != .object) {
        try writeHttpResponse(stream, 400, "application/json; charset=utf-8", "{\"error\":\"invalid_script_response\"}");
        return true;
    }

    const id_value = parsed.value.object.get("id") orelse {
        try writeHttpResponse(stream, 400, "application/json; charset=utf-8", "{\"error\":\"missing_script_id\"}");
        return true;
    };

    const task_id: u64 = switch (id_value) {
        .integer => |v| @as(u64, @intCast(v)),
        .float => |v| @as(u64, @intFromFloat(v)),
        else => {
            try writeHttpResponse(stream, 400, "application/json; charset=utf-8", "{\"error\":\"invalid_script_id\"}");
            return true;
        },
    };

    const js_error = if (parsed.value.object.get("js_error")) |err_val|
        switch (err_val) {
            .bool => |b| b,
            else => false,
        }
    else
        false;

    const value_json = if (parsed.value.object.get("value")) |value|
        try std.json.Stringify.valueAlloc(allocator, value, .{})
    else
        null;
    defer if (value_json) |buf| allocator.free(buf);

    const error_message = if (parsed.value.object.get("error_message")) |err_msg|
        switch (err_msg) {
            .string => |msg| msg,
            else => null,
        }
    else
        null;

    state.state_mutex.lock();
    const completed = state.completeScriptTaskLocked(task_id, js_error, value_json, error_message) catch {
        state.state_mutex.unlock();
        try writeHttpResponse(stream, 500, "application/json; charset=utf-8", "{\"error\":\"script_completion_failed\"}");
        return true;
    };
    state.state_mutex.unlock();

    if (!completed) {
        try writeHttpResponse(stream, 404, "application/json; charset=utf-8", "{\"error\":\"script_not_found\"}");
        return true;
    }

    try writeHttpResponse(stream, 200, "application/json; charset=utf-8", "{\"ok\":true}");
    return true;
}

fn pathWithoutQuery(path: []const u8) []const u8 {
    return if (std.mem.indexOfScalar(u8, path, '?')) |q| path[0..q] else path;
}

fn wsClientTokenFromUrl(url: []const u8) []const u8 {
    const query_start = std.mem.indexOfScalar(u8, url, '?') orelse return default_client_token;
    var pair_it = std.mem.splitScalar(u8, url[query_start + 1 ..], '&');
    while (pair_it.next()) |pair| {
        if (pair.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        const key = pair[0..eq];
        if (!std.mem.eql(u8, key, "client_id")) continue;
        const value = pair[eq + 1 ..];
        if (value.len == 0) return default_client_token;
        return value;
    }
    return default_client_token;
}

fn httpHeaderValue(headers: []const u8, name: []const u8) ?[]const u8 {
    var it = std.mem.splitSequence(u8, headers, "\r\n");
    while (it.next()) |line| {
        if (line.len == 0) continue;
        const sep = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const header_name = std.mem.trim(u8, line[0..sep], " \t");
        if (!std.ascii.eqlIgnoreCase(header_name, name)) continue;
        return std.mem.trim(u8, line[sep + 1 ..], " \t");
    }
    return null;
}

fn handleBridgeScriptRoute(
    state: *WindowState,
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    method: []const u8,
    path_only: []const u8,
) !bool {
    if (!std.mem.eql(u8, method, "GET")) return false;
    const script_route = state.rpc_state.bridge_options.script_route;
    if (!std.mem.eql(u8, path_only, script_route)) return false;

    const script_copy = blk: {
        state.rpc_state.invoke_mutex.lock();
        defer state.rpc_state.invoke_mutex.unlock();

        if (state.rpc_state.generated_script == null) {
            try state.rpc_state.rebuildScript(allocator, state.rpc_state.bridge_options);
        }
        const script = state.rpc_state.generated_script orelse bridge_template.default_script;
        break :blk try allocator.dupe(u8, script);
    };
    defer allocator.free(script_copy);

    try writeHttpResponse(stream, 200, "application/javascript; charset=utf-8", script_copy);
    return true;
}

fn handleRpcRoute(
    state: *WindowState,
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    method: []const u8,
    path_only: []const u8,
    headers: []const u8,
    body: []const u8,
) !bool {
    if (!std.mem.eql(u8, method, "POST")) return false;
    if (!std.mem.eql(u8, path_only, state.rpc_state.bridge_options.rpc_route)) return false;

    if (state.rpc_state.log_enabled) {
        std.debug.print("[webui.rpc] raw body={s}\n", .{body});
    }

    const client_token = httpHeaderValue(headers, "x-webui-client-id") orelse default_client_token;
    state.state_mutex.lock();
    const client_ref = state.findOrCreateClientSessionLocked(client_token) catch null;
    state.state_mutex.unlock();

    if (state.rpc_state.execution_mode == .queued_async) {
        const job = state.rpc_state.enqueueJob(allocator, body) catch |err| {
            state.emitDiagnostic("rpc.enqueue.error", .rpc, .warn, @errorName(err));
            const err_body = try std.fmt.allocPrint(allocator, "{{\"error\":\"{s}\"}}", .{@errorName(err)});
            defer allocator.free(err_body);
            try writeHttpResponse(stream, 400, "application/json; charset=utf-8", err_body);
            return true;
        };

        const payload = try std.json.Stringify.valueAlloc(allocator, .{
            .job_id = job.id,
            .state = @tagName(job.state),
            .poll_min_ms = state.rpc_state.job_poll_min_ms,
            .poll_max_ms = state.rpc_state.job_poll_max_ms,
        }, .{});
        defer allocator.free(payload);

        try writeHttpResponse(stream, 200, "application/json; charset=utf-8", payload);
        return true;
    }

    state.rpc_state.invoke_mutex.lock();
    const payload = state.rpc_state.invokeFromJsonPayload(allocator, body) catch |err| {
        state.rpc_state.invoke_mutex.unlock();
        state.emitDiagnostic("rpc.dispatch.error", .rpc, .warn, @errorName(err));
        const err_body = try std.fmt.allocPrint(allocator, "{{\"error\":\"{s}\"}}", .{@errorName(err)});
        defer allocator.free(err_body);
        if (state.rpc_state.log_enabled) {
            std.debug.print("[webui.rpc] error={s}\n", .{@errorName(err)});
        }
        try writeHttpResponse(stream, 400, "application/json; charset=utf-8", err_body);
        return true;
    };
    state.rpc_state.invoke_mutex.unlock();
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
            .client_id = if (client_ref) |ref| ref.client_id else null,
            .connection_id = if (client_ref) |ref| ref.connection_id else null,
        };
        handler(state.event_callback.context, &event);
    }

    try writeHttpResponse(stream, 200, "application/json; charset=utf-8", payload);
    return true;
}

fn rpcJobIdFromPath(path: []const u8) ?RpcJobId {
    const q = std.mem.indexOfScalar(u8, path, '?') orelse return null;
    var pair_it = std.mem.splitScalar(u8, path[q + 1 ..], '&');
    while (pair_it.next()) |pair| {
        if (pair.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        if (!std.mem.eql(u8, pair[0..eq], "id")) continue;
        return std.fmt.parseInt(u64, pair[eq + 1 ..], 10) catch null;
    }
    return null;
}

fn handleRpcJobRoute(
    state: *WindowState,
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    method: []const u8,
    path: []const u8,
    path_only: []const u8,
) !bool {
    if (!std.mem.eql(u8, method, "GET")) return false;
    if (!std.mem.eql(u8, path_only, "/rpc/job")) return false;

    const job_id = rpcJobIdFromPath(path) orelse {
        try writeHttpResponse(stream, 400, "application/json; charset=utf-8", "{\"error\":\"missing_job_id\"}");
        return true;
    };

    const status = state.rpc_state.pollJob(allocator, job_id) catch |err| {
        const payload = try std.fmt.allocPrint(allocator, "{{\"error\":\"{s}\"}}", .{@errorName(err)});
        defer allocator.free(payload);
        try writeHttpResponse(stream, 404, "application/json; charset=utf-8", payload);
        return true;
    };
    defer {
        if (status.value_json) |v| allocator.free(v);
        if (status.error_message) |e| allocator.free(e);
    }

    const payload = try std.json.Stringify.valueAlloc(allocator, .{
        .job_id = status.id,
        .state = @tagName(status.state),
        .value = status.value_json,
        .error_message = status.error_message,
        .created_ms = status.created_ms,
        .updated_ms = status.updated_ms,
    }, .{});
    defer allocator.free(payload);
    try writeHttpResponse(stream, 200, "application/json; charset=utf-8", payload);
    return true;
}

fn handleRpcJobCancelRoute(
    state: *WindowState,
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    method: []const u8,
    path_only: []const u8,
    body: []const u8,
) !bool {
    if (!std.mem.eql(u8, method, "POST")) return false;
    if (!std.mem.eql(u8, path_only, "/rpc/job/cancel")) return false;

    const Req = struct { job_id: RpcJobId };
    var parsed = std.json.parseFromSlice(Req, allocator, body, .{ .ignore_unknown_fields = true }) catch {
        try writeHttpResponse(stream, 400, "application/json; charset=utf-8", "{\"error\":\"invalid_cancel_request\"}");
        return true;
    };
    defer parsed.deinit();

    const canceled = state.rpc_state.cancelJob(parsed.value.job_id) catch false;
    const payload = try std.json.Stringify.valueAlloc(allocator, .{
        .job_id = parsed.value.job_id,
        .canceled = canceled,
    }, .{});
    defer allocator.free(payload);
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
        const read_n = std.posix.recv(stream.handle, &scratch, 0) catch |err| switch (err) {
            error.WouldBlock => {
                std.Thread.sleep(std.time.ns_per_ms);
                continue;
            },
            error.ConnectionResetByPeer,
            error.ConnectionTimedOut,
            error.SocketNotConnected,
            => break,
            else => return err,
        };
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
    const headers_start = first_line_end + 2;
    const headers_end = end_idx - 4;
    const headers = if (headers_start <= headers_end) raw[headers_start..headers_end] else "";

    return .{
        .raw = raw,
        .method = method,
        .path = path,
        .headers = headers,
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
        204 => "No Content",
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

    try WindowState.writeSocketAll(stream.handle, header);
    try WindowState.writeSocketAll(stream.handle, body);
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
        const n = if (builtin.os.tag == .windows)
            std.posix.recv(stream.handle, &scratch, 0) catch |err| switch (err) {
                error.WouldBlock => {
                    std.Thread.sleep(std.time.ns_per_ms);
                    continue;
                },
                error.ConnectionResetByPeer,
                error.ConnectionTimedOut,
                error.SocketNotConnected,
                => break,
                else => return err,
            }
        else
            stream.read(&scratch) catch |err| switch (err) {
                error.WouldBlock => {
                    std.Thread.sleep(std.time.ns_per_ms);
                    continue;
                },
                error.ConnectionResetByPeer,
                error.ConnectionTimedOut,
                error.SocketNotConnected,
                => break,
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
    return httpRoundTripWithHeaders(allocator, port, method, path, body, &.{});
}

fn httpRoundTripWithHeaders(
    allocator: std.mem.Allocator,
    port: u16,
    method: []const u8,
    path: []const u8,
    body: ?[]const u8,
    extra_headers: []const []const u8,
) ![]u8 {
    const address = try std.net.Address.parseIp4("127.0.0.1", port);
    const stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();

    var extra = std.array_list.Managed(u8).init(allocator);
    defer extra.deinit();
    for (extra_headers) |header| {
        try extra.appendSlice(header);
        try extra.appendSlice("\r\n");
    }

    const request = if (body) |b|
        try std.fmt.allocPrint(
            allocator,
            "{s} {s} HTTP/1.1\r\nHost: 127.0.0.1\r\n{s}Content-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
            .{ method, path, extra.items, b.len, b },
        )
    else
        try std.fmt.allocPrint(
            allocator,
            "{s} {s} HTTP/1.1\r\nHost: 127.0.0.1\r\n{s}Connection: close\r\n\r\n",
            .{ method, path, extra.items },
        );
    defer allocator.free(request);

    try stream.writeAll(request);
    return readAllFromStream(allocator, stream, 1024 * 1024);
}

fn readHttpHeadersFromStream(allocator: std.mem.Allocator, stream: std.net.Stream, max_bytes: usize) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    var scratch: [512]u8 = undefined;
    while (out.items.len < max_bytes) {
        const n = std.posix.recv(stream.handle, &scratch, 0) catch |err| switch (err) {
            error.WouldBlock => {
                std.Thread.sleep(std.time.ns_per_ms);
                continue;
            },
            error.ConnectionResetByPeer,
            error.ConnectionTimedOut,
            error.SocketNotConnected,
            => break,
            else => return err,
        };
        if (n == 0) break;
        if (out.items.len + n > max_bytes) return error.ResponseTooLarge;
        try out.appendSlice(scratch[0..n]);
        if (std.mem.indexOf(u8, out.items, "\r\n\r\n") != null) break;
    }

    return out.toOwnedSlice();
}

fn httpResponseBody(response: []const u8) []const u8 {
    const header_end = std.mem.indexOf(u8, response, "\r\n\r\n") orelse return "";
    return response[header_end + 4 ..];
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
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
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
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
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

test "public network mode binds server with public listen policy" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
        .public_network = true,
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "PublicNetwork" });
    try win.showHtml("<html><body>public-network-ok</body></html>");
    try app.run();

    try std.testing.expect(win.state().server_bind_public);
    const response = try httpRoundTrip(gpa.allocator(), win.state().server_port, "GET", "/", null);
    defer gpa.allocator().free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "public-network-ok") != null);
}

test "websocket upgrade uses same http server port" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "WsSamePort" });
    try win.showHtml("<html><body>ws-same-port</body></html>");
    try app.run();

    const address = try std.net.Address.parseIp4("127.0.0.1", win.state().server_port);
    const stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();

    try stream.writeAll(
        "GET /webui/ws?client_id=test-client HTTP/1.1\r\n" ++
            "Host: 127.0.0.1\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
            "Sec-WebSocket-Version: 13\r\n" ++
            "\r\n",
    );

    const response = try readHttpHeadersFromStream(gpa.allocator(), stream, 64 * 1024);
    defer gpa.allocator().free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "HTTP/1.1 101 Switching Protocols") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "Upgrade: websocket") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=") != null);
}

test "lifecycle route stays responsive during long running rpc" {
    const DemoRpc = struct {
        pub fn slow() []const u8 {
            std.Thread.sleep(900 * std.time.ns_per_ms);
            return "done";
        }
    };

    const RpcCallCtx = struct {
        allocator: std.mem.Allocator,
        port: u16,
        response: ?[]u8 = null,
        err: ?anyerror = null,

        fn run(ctx: *@This()) void {
            const result = httpRoundTrip(ctx.allocator, ctx.port, "POST", "/rpc", "{\"name\":\"slow\",\"args\":[]}");
            if (result) |response| {
                ctx.response = response;
            } else |err| {
                ctx.err = err;
            }
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "LifecycleResponsive" });
    try win.bindRpc(DemoRpc, .{
        .bridge_options = .{ .rpc_route = "/rpc" },
    });
    try win.showHtml("<html><body>lifecycle-responsive</body></html>");
    try app.run();

    var rpc_call_ctx = RpcCallCtx{
        .allocator = gpa.allocator(),
        .port = win.state().server_port,
    };
    const rpc_thread = try std.Thread.spawn(.{}, RpcCallCtx.run, .{&rpc_call_ctx});
    errdefer rpc_thread.join();

    std.Thread.sleep(40 * std.time.ns_per_ms);

    const started_ns = std.time.nanoTimestamp();
    const lifecycle_response = try httpRoundTrip(
        gpa.allocator(),
        win.state().server_port,
        "POST",
        "/webui/lifecycle",
        "{\"event\":\"ping\"}",
    );
    defer gpa.allocator().free(lifecycle_response);
    const elapsed_ms = @as(i64, @intCast(@divTrunc(std.time.nanoTimestamp() - started_ns, std.time.ns_per_ms)));

    try std.testing.expect(std.mem.indexOf(u8, lifecycle_response, "HTTP/1.1 200 OK") != null);
    try std.testing.expect(elapsed_ms < 400);

    rpc_thread.join();

    if (rpc_call_ctx.err) |err| return err;
    const rpc_response = rpc_call_ctx.response orelse return error.InvalidRpcResult;
    defer gpa.allocator().free(rpc_response);
    try std.testing.expect(std.mem.indexOf(u8, rpc_response, "\"value\":\"done\"") != null);
}

test "native_webview launch order keeps local runtime reachable" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .native_webview, .second = .web_url, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "NativeFallback" });
    try win.showHtml("<html><body>native-fallback-ok</body></html>");
    try app.run();

    const render_state = win.runtimeRenderState();
    if (render_state.active_surface != .native_webview) {
        try std.testing.expectEqual(@as(LaunchSurface, .web_url), render_state.active_surface);
    }

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

test "native_webview only mode still exposes local runtime url" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .native_webview, .second = null, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "NativeOnly" });
    const local_url = try win.browserUrl();
    defer gpa.allocator().free(local_url);
    try std.testing.expect(std.mem.startsWith(u8, local_url, "http://127.0.0.1:"));
}

test "linked child exit requests close immediately" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .native_webview, .second = .web_url, .third = null },
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

test "shutdown in web mode does not terminate tracked browser child process" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "ShutdownWebModeNoKill" });
    try win.showHtml("<html><body>shutdown-web-mode</body></html>");
    try app.run();

    var child = std.process.Child.init(&.{ "sh", "-c", "sleep 5" }, gpa.allocator());
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    defer {
        core_runtime.terminateBrowserProcess(gpa.allocator(), @as(i64, @intCast(child.id)));
        _ = child.wait() catch {};
    }

    win.state().state_mutex.lock();
    win.state().launched_browser_pid = @as(i64, @intCast(child.id));
    win.state().launched_browser_is_child = true;
    win.state().launched_browser_lifecycle_linked = true;
    win.state().state_mutex.unlock();

    app.shutdown();
    std.Thread.sleep(20 * std.time.ns_per_ms);

    try std.testing.expect(core_runtime.isProcessAlive(@as(i64, @intCast(child.id))));
}

test "shutdown in webview mode terminates tracked browser child process" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .native_webview, .second = .web_url, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "ShutdownWebviewModeKill" });
    try win.showHtml("<html><body>shutdown-webview-mode</body></html>");
    try app.run();

    var child = std.process.Child.init(&.{ "sh", "-c", "sleep 5" }, gpa.allocator());
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    defer {
        core_runtime.terminateBrowserProcess(gpa.allocator(), @as(i64, @intCast(child.id)));
        _ = child.wait() catch {};
    }

    const child_pid_i64: i64 = @as(i64, @intCast(child.id));
    win.state().state_mutex.lock();
    win.state().launched_browser_pid = child_pid_i64;
    win.state().launched_browser_is_child = true;
    win.state().launched_browser_lifecycle_linked = true;
    win.state().state_mutex.unlock();

    app.shutdown();

    var alive = core_runtime.isProcessAlive(child_pid_i64);
    var attempts: usize = 0;
    while (alive and attempts < 100) : (attempts += 1) {
        std.Thread.sleep(10 * std.time.ns_per_ms);
        alive = core_runtime.isProcessAlive(child_pid_i64);
    }

    try std.testing.expect(!alive);
}

test "browser spawn decision matrix across launch modes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app_web_url = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
    });
    defer app_web_url.deinit();
    var win_web_url = try app_web_url.newWindow(.{ .title = "SpawnMatrixWebUrl" });
    win_web_url.state().state_mutex.lock();
    const web_url_attempt = win_web_url.state().shouldAttemptBrowserSpawnLocked(gpa.allocator(), true);
    win_web_url.state().state_mutex.unlock();
    try std.testing.expect(!web_url_attempt);

    var app_browser = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .browser_window, .second = .web_url, .third = null },
    });
    defer app_browser.deinit();
    var win_browser = try app_browser.newWindow(.{ .title = "SpawnMatrixBrowser" });
    win_browser.state().state_mutex.lock();
    const browser_attempt = win_browser.state().shouldAttemptBrowserSpawnLocked(gpa.allocator(), true);
    win_browser.state().state_mutex.unlock();
    try std.testing.expect(browser_attempt);

    var app_native_only = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .native_webview, .second = null, .third = null },
    });
    defer app_native_only.deinit();
    var win_native_only = try app_native_only.newWindow(.{ .title = "SpawnMatrixNativeOnly" });
    win_native_only.state().state_mutex.lock();
    const native_only_attempt = win_native_only.state().shouldAttemptBrowserSpawnLocked(gpa.allocator(), true);
    win_native_only.state().state_mutex.unlock();
    try std.testing.expect(native_only_attempt);

    var app_dual = try App.init(gpa.allocator(), .{
        .launch_policy = .{
            .first = .native_webview,
            .second = .browser_window,
            .third = .web_url,
            .allow_dual_surface = true,
        },
    });
    defer app_dual.deinit();
    var win_dual = try app_dual.newWindow(.{ .title = "SpawnMatrixDual" });
    win_dual.state().state_mutex.lock();
    const dual_attempt = win_dual.state().shouldAttemptBrowserSpawnLocked(gpa.allocator(), true);
    win_dual.state().state_mutex.unlock();
    try std.testing.expect(dual_attempt);
}

test "local render spawn is skipped while tracked browser process is alive" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .browser_window, .second = .web_url, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "SpawnSkipAlivePid" });

    var child = std.process.Child.init(&.{ "sh", "-c", "sleep 5" }, gpa.allocator());
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    defer {
        core_runtime.terminateBrowserProcess(gpa.allocator(), @as(i64, @intCast(child.id)));
        _ = child.wait() catch {};
    }

    const child_pid_i64: i64 = @as(i64, @intCast(child.id));
    win.state().state_mutex.lock();
    win.state().launched_browser_pid = child_pid_i64;
    const attempt = win.state().shouldAttemptBrowserSpawnLocked(gpa.allocator(), true);
    const tracked_after = win.state().launched_browser_pid;
    win.state().state_mutex.unlock();

    try std.testing.expect(!attempt);
    try std.testing.expect(tracked_after != null);
    try std.testing.expectEqual(child_pid_i64, tracked_after.?);
    try std.testing.expect(core_runtime.isProcessAlive(child_pid_i64));
}

test "local render spawn clears stale tracked browser process before relaunch" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .browser_window, .second = .web_url, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "SpawnClearDeadPid" });

    var child = std.process.Child.init(&.{ "sh", "-c", "exit 0" }, gpa.allocator());
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    _ = try child.wait();

    const dead_pid_i64: i64 = @as(i64, @intCast(child.id));
    win.state().state_mutex.lock();
    win.state().launched_browser_pid = dead_pid_i64;
    const attempt = win.state().shouldAttemptBrowserSpawnLocked(gpa.allocator(), true);
    const tracked_after = win.state().launched_browser_pid;
    win.state().state_mutex.unlock();

    try std.testing.expect(attempt);
    try std.testing.expect(tracked_after == null);
}

test "native webview mode bootstraps host process spawn when backend is not ready" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .native_webview, .second = .web_url, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "NativeBootstrapSpawn" });
    win.state().state_mutex.lock();
    const active_surface = win.state().runtime_render_state.active_surface;
    const should_serve = win.state().shouldServeBrowser();
    const should_spawn = win.state().shouldAttemptBrowserSpawnLocked(gpa.allocator(), true);
    win.state().state_mutex.unlock();

    if (active_surface == .native_webview) {
        try std.testing.expect(should_serve);
        try std.testing.expect(should_spawn);
    } else {
        try std.testing.expect(active_surface == .web_url or active_surface == .browser_window);
    }
}

test "effective browser launch options reserve native host bootstrap for webview surface" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app_browser = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .browser_window, .second = .web_url, .third = null },
    });
    defer app_browser.deinit();
    var win_browser = try app_browser.newWindow(.{ .title = "EffectiveLaunchBrowser" });

    win_browser.state().state_mutex.lock();
    const browser_base: BrowserLaunchOptions = .{
        .surface_mode = .native_webview_host,
        .fallback_mode = .strict,
    };
    const browser_effective = win_browser.state().effectiveBrowserLaunchOptions(browser_base);
    win_browser.state().state_mutex.unlock();

    try std.testing.expectEqual(@as(BrowserSurfaceMode, .app_window), browser_effective.surface_mode);
    try std.testing.expectEqual(@as(BrowserFallbackMode, .strict), browser_effective.fallback_mode);

    var app_native = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .native_webview, .second = .web_url, .third = null },
    });
    defer app_native.deinit();
    var win_native = try app_native.newWindow(.{ .title = "EffectiveLaunchNative" });

    win_native.state().state_mutex.lock();
    const native_effective = win_native.state().effectiveBrowserLaunchOptions(.{
        .surface_mode = .tab,
        .fallback_mode = .allow_system,
    });
    win_native.state().state_mutex.unlock();

    try std.testing.expectEqual(@as(BrowserSurfaceMode, .native_webview_host), native_effective.surface_mode);
    try std.testing.expectEqual(@as(BrowserFallbackMode, .strict), native_effective.fallback_mode);
}

test "browser launch failure fallback advances from active launch surface" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{
            .first = .native_webview,
            .second = .browser_window,
            .third = .web_url,
        },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "LaunchFailureFallbackOrder" });
    win.state().state_mutex.lock();
    defer win.state().state_mutex.unlock();

    win.state().runtime_render_state.active_surface = .native_webview;
    win.state().runtime_render_state.active_transport = .native_webview;
    try std.testing.expect(win.state().resolveAfterBrowserLaunchFailure(.native_webview));
    try std.testing.expectEqual(@as(LaunchSurface, .browser_window), win.state().runtime_render_state.active_surface);
    try std.testing.expectEqual(@as(TransportMode, .browser_fallback), win.state().runtime_render_state.active_transport);
    try std.testing.expect(win.state().runtime_render_state.fallback_applied);
    try std.testing.expectEqual(@as(?FallbackReason, .launch_failed), win.state().runtime_render_state.fallback_reason);

    try std.testing.expect(win.state().resolveAfterBrowserLaunchFailure(.browser_window));
    try std.testing.expectEqual(@as(LaunchSurface, .web_url), win.state().runtime_render_state.active_surface);
    try std.testing.expect(!win.state().resolveAfterBrowserLaunchFailure(.web_url));
}

test "window_closing lifecycle event is ignored while tracked browser pid is alive" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
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
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
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
    try std.testing.expect(close_result.emulation == null);
    try std.testing.expect(win.state().close_requested.load(.acquire));
}

test "close control remains backend-driven when emulation is disabled" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
        .window_fallback_emulation = false,
    });
    defer app.deinit();

    var win = try app.newWindow(.{});
    const close_result = try win.control(.close);
    try std.testing.expect(close_result.success);
    try std.testing.expect(close_result.closed);
    try std.testing.expect(close_result.emulation == null);
}

test "native backend unavailability returns warnings and falls back to emulation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .native_webview, .second = .web_url, .third = null },
        .window_fallback_emulation = true,
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
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
        .window_fallback_emulation = true,
    });
    defer app_default.deinit();
    var win_default = try app_default.newWindow(.{});
    const caps_default = win_default.capabilities();
    try std.testing.expect(caps_default.len > 0);
    try std.testing.expect(window_style_types.hasCapability(.native_frameless, caps_default));

    var app_disabled = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
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
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
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

    const close_res = try httpRoundTrip(gpa.allocator(), win.state().server_port, "POST", "/webui/window/control", "{\"cmd\":\"close\"}");
    defer gpa.allocator().free(close_res);
    try std.testing.expect(std.mem.indexOf(u8, close_res, "\"closed\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, close_res, "\"emulation\":null") != null);
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

test "rpc event carries client and connection identifiers" {
    const DemoRpc = struct {
        pub fn ping() []const u8 {
            return "pong";
        }
    };

    const Capture = struct {
        var seen: bool = false;
        var client_id: ?usize = null;
        var connection_id: ?usize = null;

        fn onEvent(_: ?*anyopaque, event: *const Event) void {
            if (event.kind != .rpc) return;
            seen = true;
            client_id = event.client_id;
            connection_id = event.connection_id;
        }
    };

    Capture.seen = false;
    Capture.client_id = null;
    Capture.connection_id = null;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{});
    try win.bindRpc(DemoRpc, .{});
    win.onEvent(Capture.onEvent, null);
    try win.showHtml("<html><body>rpc-client-meta</body></html>");
    try app.run();

    const rpc_response = try httpRoundTripWithHeaders(
        gpa.allocator(),
        win.state().server_port,
        "POST",
        "/webui/rpc",
        "{\"name\":\"ping\",\"args\":[]}",
        &.{"x-webui-client-id: rpc-meta-client"},
    );
    defer gpa.allocator().free(rpc_response);
    try std.testing.expect(std.mem.indexOf(u8, rpc_response, "\"value\":\"pong\"") != null);
    try std.testing.expect(Capture.seen);
    try std.testing.expect(Capture.client_id != null);
    try std.testing.expect(Capture.connection_id != null);
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
        .app = .{
            .launch_policy = .webUrlOnly(),
        },
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

test "evalScript times out when no client is polling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{});
    const result = try win.evalScript(gpa.allocator(), "return 1 + 1;", .{
        .timeout_ms = 20,
    });
    defer {
        if (result.value) |value| gpa.allocator().free(value);
        if (result.error_message) |msg| gpa.allocator().free(msg);
    }

    try std.testing.expect(!result.ok);
    try std.testing.expect(result.timed_out);
    try std.testing.expect(!result.js_error);
    try std.testing.expect(result.value == null);
}

test "script response route completes queued eval task" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "ScriptQueue" });
    try win.showHtml("<html><body>script-route</body></html>");
    try app.run();

    const state = win.state();
    state.state_mutex.lock();
    const task = try state.queueScriptLocked(gpa.allocator(), "return 6 * 7;", null, true);
    const moved = state.removeScriptPendingLocked(task);
    try std.testing.expect(moved);
    try state.script_inflight.append(task);
    state.state_mutex.unlock();

    const completion_body = try std.fmt.allocPrint(
        gpa.allocator(),
        "{{\"id\":{d},\"js_error\":false,\"value\":42}}",
        .{task.id},
    );
    defer gpa.allocator().free(completion_body);

    const complete_response = try httpRoundTripWithHeaders(
        gpa.allocator(),
        state.server_port,
        "POST",
        "/webui/script/response",
        completion_body,
        &.{"x-webui-client-id: script-test-client"},
    );
    defer gpa.allocator().free(complete_response);
    try std.testing.expect(std.mem.indexOf(u8, complete_response, "HTTP/1.1 200 OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, complete_response, "{\"ok\":true}") != null);

    task.mutex.lock();
    const done = task.done;
    const value = task.value_json;
    task.mutex.unlock();
    try std.testing.expect(done);
    try std.testing.expect(value != null);
    try std.testing.expect(std.mem.eql(u8, value.?, "42"));

    task.deinit();
}

test "runtime render state and capability probe expose launch policy selection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{
            .first = .web_url,
            .second = null,
            .third = null,
        },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "RenderStateProbe" });
    const probe = win.probeCapabilities();
    try std.testing.expectEqual(@as(TransportMode, .browser_fallback), probe.transport_if_shown);
    try std.testing.expect(!probe.fallback_expected);

    try win.showHtml("<html><body>render-state</body></html>");
    try app.run();

    const state = win.runtimeRenderState();
    try std.testing.expectEqual(@as(TransportMode, .browser_fallback), state.active_transport);
    try std.testing.expectEqual(@as(LaunchSurface, .web_url), state.active_surface);
    try std.testing.expect(!state.fallback_applied);
    try std.testing.expect(state.fallback_reason == null);
    try std.testing.expectEqual(@as(LaunchSurface, .web_url), state.launch_policy.first);
}

test "diagnostic callback emits typed transport diagnostics" {
    const Capture = struct {
        var count: usize = 0;
        var saw_transport: bool = false;
        var saw_fallback: bool = false;

        fn onDiagnostic(_: ?*anyopaque, diagnostic: *const Diagnostic) void {
            count += 1;
            if (std.mem.startsWith(u8, diagnostic.code, "transport.active.")) saw_transport = true;
            if (std.mem.startsWith(u8, diagnostic.code, "fallback.")) saw_fallback = true;
        }
    };

    Capture.count = 0;
    Capture.saw_transport = false;
    Capture.saw_fallback = false;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{
            .first = .web_url,
            .second = null,
            .third = null,
        },
    });
    defer app.deinit();
    app.onDiagnostic(Capture.onDiagnostic, null);

    var win = try app.newWindow(.{ .title = "DiagnosticCapture" });
    try win.showHtml("<html><body>diagnostic-capture</body></html>");
    try app.run();

    try std.testing.expect(Capture.count > 0);
    try std.testing.expect(Capture.saw_transport);
    try std.testing.expect(!Capture.saw_fallback);
}

test "service init keeps diagnostic callback binding invariant stable" {
    const NoopDiagnostic = struct {
        fn onDiagnostic(_: ?*anyopaque, _: *const Diagnostic) void {}
    };

    const rpc_methods = struct {
        pub fn ping() []const u8 {
            return "pong";
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var service = try Service.init(gpa.allocator(), rpc_methods, .{
        .app = .{
            .launch_policy = .{
                .first = .web_url,
                .second = null,
                .third = null,
            },
        },
    });
    defer service.deinit();
    service.onDiagnostic(NoopDiagnostic.onDiagnostic, null);

    try std.testing.expect(service.hasStableDiagnosticCallbackBindings());
    try std.testing.expect(service.checkPinnedMoveInvariant(false));
}

test "service move is detected by diagnostic callback binding invariant" {
    if (!pinnedMoveGuardEnabled()) return;

    const NoopDiagnostic = struct {
        fn onDiagnostic(_: ?*anyopaque, _: *const Diagnostic) void {}
    };

    const rpc_methods = struct {
        pub fn ping() []const u8 {
            return "pong";
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var service = try Service.init(gpa.allocator(), rpc_methods, .{
        .app = .{
            .launch_policy = .{
                .first = .web_url,
                .second = null,
                .third = null,
            },
        },
    });
    service.onDiagnostic(NoopDiagnostic.onDiagnostic, null);

    var moved = service;
    try std.testing.expect(!moved.hasStableDiagnosticCallbackBindings());
    try std.testing.expect(!moved.checkPinnedMoveInvariant(false));
    moved.deinit();
}

test "service move guard emits typed diagnostic on mismatch" {
    if (!pinnedMoveGuardEnabled()) return;

    const Capture = struct {
        var count: usize = 0;
        var saw_code: bool = false;
        var saw_category: bool = false;
        var saw_severity: bool = false;

        fn onDiagnostic(_: ?*anyopaque, diagnostic: *const Diagnostic) void {
            count += 1;
            if (std.mem.eql(u8, diagnostic.code, "lifecycle.pinned_struct_moved.service")) saw_code = true;
            if (diagnostic.category == .lifecycle) saw_category = true;
            if (diagnostic.severity == .err) saw_severity = true;
        }
    };

    Capture.count = 0;
    Capture.saw_code = false;
    Capture.saw_category = false;
    Capture.saw_severity = false;

    const rpc_methods = struct {
        pub fn ping() []const u8 {
            return "pong";
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var service = try Service.init(gpa.allocator(), rpc_methods, .{
        .app = .{
            .launch_policy = .{
                .first = .web_url,
                .second = null,
                .third = null,
            },
        },
    });
    service.onDiagnostic(Capture.onDiagnostic, null);

    var moved = service;

    try std.testing.expect(!moved.checkPinnedMoveInvariant(false));
    try std.testing.expect(Capture.count > 0);
    try std.testing.expect(Capture.saw_code);
    try std.testing.expect(Capture.saw_category);
    try std.testing.expect(Capture.saw_severity);
    moved.deinit();
}

test "normal service flow does not emit pinned move diagnostics" {
    const Capture = struct {
        var pinned_count: usize = 0;

        fn onDiagnostic(_: ?*anyopaque, diagnostic: *const Diagnostic) void {
            if (std.mem.startsWith(u8, diagnostic.code, "lifecycle.pinned_struct_moved.")) pinned_count += 1;
        }
    };

    Capture.pinned_count = 0;

    const rpc_methods = struct {
        pub fn ping() []const u8 {
            return "pong";
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var service = try Service.init(gpa.allocator(), rpc_methods, .{
        .app = .{
            .launch_policy = .{
                .first = .web_url,
                .second = null,
                .third = null,
            },
        },
    });
    defer service.deinit();
    service.onDiagnostic(Capture.onDiagnostic, null);

    try service.showHtml("<html><body>move-safe</body></html>");
    try service.run();
    try std.testing.expectEqual(@as(usize, 0), Capture.pinned_count);
}

test "service requirement listing and probe are available before show" {
    const rpc_methods = struct {
        pub fn ping() []const u8 {
            return "pong";
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var service = try Service.init(gpa.allocator(), rpc_methods, .{
        .app = .{
            .launch_policy = .{
                .first = .web_url,
                .second = null,
                .third = null,
            },
        },
    });
    defer service.deinit();

    const probe = service.probeCapabilities();
    try std.testing.expectEqual(@as(TransportMode, .browser_fallback), probe.transport_if_shown);

    const reqs = try service.listRuntimeRequirements(gpa.allocator());
    defer gpa.allocator().free(reqs);
    try std.testing.expect(reqs.len > 0);

    var found_native = false;
    for (reqs) |req| {
        if (std.mem.eql(u8, req.name, "native_webview_backend")) {
            found_native = true;
            try std.testing.expect(!req.required);
            break;
        }
    }
    try std.testing.expect(found_native);
}

test "async rpc jobs support poll and cancel" {
    const DemoRpc = struct {
        pub fn delayedAdd(a: i64, b: i64, delay_ms: i64) i64 {
            const delay = if (delay_ms < 0) @as(u64, 0) else @as(u64, @intCast(delay_ms));
            std.Thread.sleep(delay * std.time.ns_per_ms);
            return a + b;
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{
            .first = .web_url,
            .second = null,
            .third = null,
        },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "AsyncJobs" });
    try win.bindRpc(DemoRpc, .{
        .bridge_options = .{ .rpc_route = "/rpc" },
        .execution_mode = .queued_async,
        .job_poll_min_ms = 10,
        .job_poll_max_ms = 40,
    });
    try win.showHtml("<html><body>async-jobs</body></html>");
    try app.run();

    const first = try win.state().rpc_state.enqueueJob(gpa.allocator(), "{\"name\":\"delayedAdd\",\"args\":[20,22,40]}");
    try std.testing.expectEqual(@as(RpcJobState, .queued), first.state);

    var completed = false;
    var attempts: usize = 0;
    while (attempts < 120) : (attempts += 1) {
        const status = try win.rpcPollJob(gpa.allocator(), first.id);
        defer {
            if (status.value_json) |value| gpa.allocator().free(value);
            if (status.error_message) |msg| gpa.allocator().free(msg);
        }

        switch (status.state) {
            .completed => {
                completed = true;
                try std.testing.expect(status.value_json != null);
                try std.testing.expect(std.mem.indexOf(u8, status.value_json.?, "\"value\":42") != null);
                break;
            },
            .failed, .timed_out, .canceled => return error.InvalidRpcResult,
            else => std.Thread.sleep(5 * std.time.ns_per_ms),
        }
    }
    try std.testing.expect(completed);

    const blocker = try win.state().rpc_state.enqueueJob(gpa.allocator(), "{\"name\":\"delayedAdd\",\"args\":[1,1,220]}");
    const queued = try win.state().rpc_state.enqueueJob(gpa.allocator(), "{\"name\":\"delayedAdd\",\"args\":[2,2,5]}");
    _ = blocker;

    try std.testing.expect(try win.rpcCancelJob(queued.id));
    const canceled_status = try win.rpcPollJob(gpa.allocator(), queued.id);
    defer {
        if (canceled_status.value_json) |value| gpa.allocator().free(value);
        if (canceled_status.error_message) |msg| gpa.allocator().free(msg);
    }
    try std.testing.expectEqual(@as(RpcJobState, .canceled), canceled_status.state);
}

test "async rpc job routes roundtrip via http endpoints" {
    const DemoRpc = struct {
        pub fn ping() []const u8 {
            return "pong";
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{
            .first = .web_url,
            .second = null,
            .third = null,
        },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "AsyncRouteRoundtrip" });
    try win.bindRpc(DemoRpc, .{
        .bridge_options = .{ .rpc_route = "/rpc" },
        .execution_mode = .queued_async,
    });
    try win.showHtml("<html><body>async-route-roundtrip</body></html>");
    try app.run();

    const enqueue_response = try httpRoundTrip(gpa.allocator(), win.state().server_port, "POST", "/rpc", "{\"name\":\"ping\",\"args\":[]}");
    defer gpa.allocator().free(enqueue_response);
    try std.testing.expect(std.mem.indexOf(u8, enqueue_response, "\"job_id\":") != null);

    const body = httpResponseBody(enqueue_response);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa.allocator(), body, .{});
    defer parsed.deinit();
    const job_id_value = parsed.value.object.get("job_id") orelse return error.InvalidHttpRequest;
    const job_id: u64 = switch (job_id_value) {
        .integer => |v| @as(u64, @intCast(v)),
        .float => |v| @as(u64, @intFromFloat(v)),
        else => return error.InvalidHttpRequest,
    };

    var done = false;
    var attempts: usize = 0;
    while (attempts < 80) : (attempts += 1) {
        const status_path = try std.fmt.allocPrint(gpa.allocator(), "/rpc/job?id={d}", .{job_id});
        defer gpa.allocator().free(status_path);
        const status_response = try httpRoundTrip(
            gpa.allocator(),
            win.state().server_port,
            "GET",
            status_path,
            null,
        );
        defer gpa.allocator().free(status_response);
        if (std.mem.indexOf(u8, status_response, "\"state\":\"completed\"") != null) {
            done = true;
            break;
        }
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }
    try std.testing.expect(done);

    const cancel_body = try std.fmt.allocPrint(gpa.allocator(), "{{\"job_id\":{d}}}", .{job_id});
    defer gpa.allocator().free(cancel_body);
    const cancel_response = try httpRoundTrip(gpa.allocator(), win.state().server_port, "POST", "/rpc/job/cancel", cancel_body);
    defer gpa.allocator().free(cancel_response);
    try std.testing.expect(std.mem.indexOf(u8, cancel_response, "\"canceled\":false") != null);
}

test "threaded dispatcher stress handles concurrent http rpc requests" {
    const DemoRpc = struct {
        pub fn mul(a: i64, b: i64) i64 {
            std.Thread.sleep(std.time.ns_per_ms);
            return a * b;
        }
    };

    const Shared = struct { failed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false) };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{
            .first = .web_url,
            .second = null,
            .third = null,
        },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "ThreadedStressHttp" });
    var registry = win.rpc();
    try registry.register(DemoRpc, .{
        .bridge_options = .{ .rpc_route = "/rpc" },
        .dispatcher_mode = .threaded,
        .threaded_poll_interval_ns = std.time.ns_per_ms,
    });
    try win.showHtml("<html><body>threaded-stress-http</body></html>");
    try app.run();

    const Ctx = struct {
        port: u16,
        start: i64,
        shared: *Shared,
    };
    const Worker = struct {
        fn run(ctx: *Ctx) void {
            var gpa_thread = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa_thread.deinit();
            const allocator = gpa_thread.allocator();

            var i: usize = 0;
            while (i < 24) : (i += 1) {
                const lhs: i64 = ctx.start + @as(i64, @intCast(i));
                const payload = std.fmt.allocPrint(allocator, "{{\"name\":\"mul\",\"args\":[{d},3]}}", .{lhs}) catch {
                    ctx.shared.failed.store(true, .release);
                    return;
                };
                defer allocator.free(payload);

                const response = httpRoundTrip(allocator, ctx.port, "POST", "/rpc", payload) catch {
                    ctx.shared.failed.store(true, .release);
                    return;
                };
                defer allocator.free(response);

                const needle = std.fmt.allocPrint(allocator, "\"value\":{d}", .{lhs * 3}) catch {
                    ctx.shared.failed.store(true, .release);
                    return;
                };
                defer allocator.free(needle);

                if (std.mem.indexOf(u8, response, needle) == null) {
                    ctx.shared.failed.store(true, .release);
                    return;
                }
            }
        }
    };

    var shared = Shared{};
    var contexts: [6]Ctx = undefined;
    var threads: [6]std.Thread = undefined;
    for (&contexts, 0..) |*ctx, idx| {
        ctx.* = .{
            .port = win.state().server_port,
            .start = 100 + @as(i64, @intCast(idx * 32)),
            .shared = &shared,
        };
        threads[idx] = try std.Thread.spawn(.{}, Worker.run, .{ctx});
    }

    for (threads) |thread| thread.join();
    try std.testing.expect(!shared.failed.load(.acquire));
}

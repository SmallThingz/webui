const std = @import("std");
const build_options = @import("build_options");

const browser_discovery = @import("../ported/browser_discovery.zig");
const core_runtime = @import("../ported/webui.zig");
const runtime_requirements = @import("runtime_requirements.zig");
const window_style_types = @import("window_style.zig");
const logging = @import("logging.zig");

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

pub const RpcOptions = struct {
    dispatcher_mode: DispatcherMode = .threaded,
    custom_dispatcher: ?CustomDispatcher = null,
    custom_context: ?*anyopaque = null,
    bridge_options: BridgeOptions = .{},
    threaded_poll_interval_ns: u64 = 2 * std.time.ns_per_ms,
};

pub const AppOptions = struct {
    launch_policy: LaunchPolicy = .{},
    enable_tls: bool = build_options.enable_tls,
    tls: @import("../network/tls_runtime.zig").TlsOptions = .{
        .enabled = build_options.enable_tls,
    },
    enable_webui_log: bool = build_options.enable_webui_log,
    log_sink: logging.Sink = .{},
    public_network: bool = false,
    browser_launch: core_runtime.BrowserLaunchOptions = .{},
    window_fallback_emulation: bool = true,
};

pub const WindowOptions = struct {
    window_id: ?usize = null,
    title: []const u8 = "WebUI Zig",
    style: window_style_types.WindowStyle = .{},
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

pub const FrontendCallResult = struct {
    connection_id: usize,
    result: ScriptEvalResult,
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
    process_signals: bool = true,
};

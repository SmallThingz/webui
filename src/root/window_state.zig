const std = @import("std");
const builtin = @import("builtin");

const core_runtime = @import("../ported/webui.zig");
const browser_discovery = @import("../ported/browser_discovery.zig");
const webview_backend = @import("../ported/webview.zig");
const https_server = @import("../network/https_server.zig");
const window_style_types = @import("window_style.zig");
const api_types = @import("api_types.zig");
const launch_policy = @import("launch_policy.zig");
const rpc_runtime = @import("rpc_runtime.zig");
const root_utils = @import("utils.zig");
const net_io = @import("net_io.zig");
const server_routes = @import("server_routes.zig");

const LaunchPolicy = api_types.LaunchPolicy;
const LaunchSurface = api_types.LaunchSurface;
const RuntimeRenderState = api_types.RuntimeRenderState;
const FallbackReason = api_types.FallbackReason;
const Diagnostic = api_types.Diagnostic;
const DiagnosticCategory = api_types.DiagnosticCategory;
const DiagnosticSeverity = api_types.DiagnosticSeverity;
const EventKind = api_types.EventKind;
const Event = api_types.Event;
const EventHandler = api_types.EventHandler;
const RawHandler = api_types.RawHandler;
const AppOptions = api_types.AppOptions;
const WindowOptions = api_types.WindowOptions;
const WindowControlResult = api_types.WindowControlResult;

const WindowStyle = window_style_types.WindowStyle;
const WindowControl = window_style_types.WindowControl;
const WindowCapability = window_style_types.WindowCapability;
const CloseHandler = window_style_types.CloseHandler;

const BrowserLaunchOptions = core_runtime.BrowserLaunchOptions;
const BrowserLaunchProfileOwnership = core_runtime.BrowserLaunchProfileOwnership;

const launchPolicyOrder = launch_policy.order;
const launchPolicyContains = launch_policy.contains;
const launchPolicyNextAfter = launch_policy.nextAfter;

const replaceOwned = root_utils.replaceOwned;
const isHttpUrl = root_utils.isHttpUrl;

pub const EventCallbackState = struct {
    handler: ?EventHandler = null,
    context: ?*anyopaque = null,
};

pub const DiagnosticHandler = *const fn (context: ?*anyopaque, diagnostic: *const Diagnostic) void;

pub const DiagnosticCallbackState = struct {
    handler: ?DiagnosticHandler = null,
    context: ?*anyopaque = null,
};

pub const RawCallbackState = struct {
    handler: ?RawHandler = null,
    context: ?*anyopaque = null,
};

pub const CloseCallbackState = struct {
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

const RpcRegistryState = rpc_runtime.State;

pub const ClientSession = struct {
    token: []u8,
    client_id: usize,
    connection_id: usize,
    last_seen_ms: i64,
};

pub const ScriptTask = struct {
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

    pub fn init(
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

    pub fn deinit(self: *ScriptTask) void {
        self.allocator.free(self.script);
        if (self.value_json) |value| self.allocator.free(value);
        if (self.error_message) |msg| self.allocator.free(msg);
        self.allocator.destroy(self);
    }
};

pub const FrontendRpcTask = struct {
    allocator: std.mem.Allocator,
    id: u64,
    target_connection: ?usize,
    function_name: []u8,
    args_json: []u8,
    expect_result: bool,
    done: bool = false,
    timed_out: bool = false,
    js_error: bool = false,
    value_json: ?[]u8 = null,
    error_message: ?[]u8 = null,
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},

    pub fn init(
        allocator: std.mem.Allocator,
        id: u64,
        function_name: []const u8,
        args_json: []const u8,
        target_connection: ?usize,
        expect_result: bool,
    ) !*FrontendRpcTask {
        const task = try allocator.create(FrontendRpcTask);
        task.* = .{
            .allocator = allocator,
            .id = id,
            .target_connection = target_connection,
            .function_name = try allocator.dupe(u8, function_name),
            .args_json = try allocator.dupe(u8, args_json),
            .expect_result = expect_result,
        };
        return task;
    }

    pub fn deinit(self: *FrontendRpcTask) void {
        self.allocator.free(self.function_name);
        self.allocator.free(self.args_json);
        if (self.value_json) |value| self.allocator.free(value);
        if (self.error_message) |msg| self.allocator.free(msg);
        self.allocator.destroy(self);
    }
};

pub const default_client_token = "default-client";

pub const WsTransport = union(enum) {
    plain: std.net.Stream,
    tls: *https_server.Connection,

    pub fn read(self: *WsTransport, buffer: []u8) !usize {
        return switch (self.*) {
            .plain => |stream| stream.read(buffer),
            .tls => |conn| conn.read(buffer),
        };
    }

    pub fn writeAll(self: *WsTransport, bytes: []const u8) !void {
        return switch (self.*) {
            .plain => |stream| stream.writeAll(bytes),
            .tls => |conn| conn.writeAll(bytes),
        };
    }

    pub fn shutdown(self: *WsTransport) void {
        switch (self.*) {
            .plain => |stream| stream.close(),
            .tls => |conn| {
                conn.close();
            },
        }
    }

    pub fn destroy(self: *WsTransport, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .plain => {},
            .tls => |conn| allocator.destroy(conn),
        }
    }
};

pub const WsConnectionState = struct {
    connection_id: usize,
    transport: WsTransport,
};

pub const WindowState = struct {
    allocator: std.mem.Allocator,
    id: usize,
    title: []u8,
    diagnostic_callback: *DiagnosticCallbackState,
    launch_policy: LaunchPolicy,
    runtime_render_state: RuntimeRenderState,
    window_fallback_emulation: bool,
    server_port: u16,
    server_tls_enabled: bool,
    server_tls_cert_pem: ?[]const u8,
    server_tls_key_pem: ?[]const u8,
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
    next_frontend_rpc_id: u64,
    frontend_rpc_pending: std.array_list.Managed(*FrontendRpcTask),
    frontend_rpc_inflight: std.array_list.Managed(*FrontendRpcTask),
    next_close_signal_id: u64,
    last_close_ack_id: u64,
    close_ack_cond: std.Thread.Condition,
    lifecycle_close_pending: bool,
    lifecycle_close_deadline_ms: i64,
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

    // Browser window unload fires for both tab close and page refresh. We keep
    // a short grace window so refresh/reload reconnects do not kill the backend.
    const lifecycle_close_grace_ms: i64 = 2500;

    pub fn init(
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
            .server_tls_enabled = app_options.tls.enabled and app_options.tls.cert_pem != null and app_options.tls.key_pem != null,
            .server_tls_cert_pem = app_options.tls.cert_pem,
            .server_tls_key_pem = app_options.tls.key_pem,
            .server_bind_public = app_options.public_network,
            .last_html = null,
            .last_file = null,
            .last_url = null,
            .shown = false,
            .connected_emitted = false,
            .event_callback = .{},
            .raw_callback = .{},
            .close_callback = .{},
            .rpc_state = RpcRegistryState.init(allocator, .{
                .enabled = app_options.enable_webui_log,
                .sink = app_options.log_sink,
            }),
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
            .next_frontend_rpc_id = 1,
            .frontend_rpc_pending = std.array_list.Managed(*FrontendRpcTask).init(allocator),
            .frontend_rpc_inflight = std.array_list.Managed(*FrontendRpcTask).init(allocator),
            .next_close_signal_id = 1,
            .last_close_ack_id = 0,
            .close_ack_cond = .{},
            .lifecycle_close_pending = false,
            .lifecycle_close_deadline_ms = 0,
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
        errdefer state.deinit(allocator);

        state.backend.setLinuxWebViewTarget(app_options.linux_webview_target);
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
                    } else {
                        return err;
                    }
                } else {
                    return err;
                }
                if (backendWarningForError(err, state.window_fallback_emulation)) |warning| {
                    state.rpc_state.logf(.warn, "[webui.warning] window={d} {s}\n", .{ state.id, warning });
                }
            };
            state.backend.applyStyle(state.current_style) catch |err| {
                if (backendWarningForError(err, state.window_fallback_emulation)) |warning| {
                    state.rpc_state.logf(.warn, "[webui.warning] window={d} {s}\n", .{ state.id, warning });
                }
            };
        }
        return state;
    }

    pub fn resolveActiveTransportLocked(self: *WindowState) void {
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

    pub fn setStyleOwned(self: *WindowState, allocator: std.mem.Allocator, style: WindowStyle) !void {
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

    pub fn isNativeWindowActive(self: *const WindowState) bool {
        return self.runtime_render_state.active_transport == .native_webview and self.backend.isNative();
    }

    pub fn capabilities(self: *const WindowState) []const WindowCapability {
        if (self.isNativeWindowActive()) {
            if (self.native_capabilities.len > 0) return self.native_capabilities;
            if (self.window_fallback_emulation) return emulated_capabilities[0..];
            return &.{};
        }
        if (self.window_fallback_emulation) return emulated_capabilities[0..];
        return &.{};
    }

    pub fn emit(self: *WindowState, kind: EventKind, name: []const u8, payload: []const u8) void {
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

    pub fn requestClose(self: *WindowState) bool {
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

    pub fn clearWarning(self: *WindowState) void {
        self.last_warning = null;
    }

    pub fn setWarning(self: *WindowState, message: []const u8) void {
        self.last_warning = message;
        self.rpc_state.logf(.warn, "[webui.warning] window={d} {s}\n", .{ self.id, message });
        self.emit(.window_state, "warning", message);
    }

    pub fn setWarningFromBackendError(self: *WindowState, err: anyerror) bool {
        if (backendWarningForError(err, self.window_fallback_emulation)) |message| {
            self.setWarning(message);
            return true;
        }
        return false;
    }

    pub fn applyStyle(self: *WindowState, allocator: std.mem.Allocator, style: WindowStyle) !void {
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

    pub fn control(self: *WindowState, cmd: WindowControl) !WindowControlResult {
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

    pub fn emitDiagnostic(
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

    pub fn shouldServeBrowser(self: *const WindowState) bool {
        if (self.runtime_render_state.active_surface != .native_webview) return true;
        // Native-webview mode still needs the local HTTP/WebSocket runtime so the
        // host process can render and communicate with this window.
        return true;
    }

    pub fn setLaunchedBrowserLaunch(self: *WindowState, allocator: std.mem.Allocator, launch: core_runtime.BrowserLaunch) void {
        self.cleanupBrowserProfileDir(allocator);
        const requested_surface = self.runtime_render_state.active_surface;
        const launched_surface: LaunchSurface = switch (launch.surface_mode) {
            .native_webview_host => .native_webview,
            .app_window => .browser_window,
            .tab => .web_url,
        };

        if (launch.pid) |pid| {
            if (self.launched_browser_pid) |existing| {
                if (existing != pid) {
                    self.rpc_state.logf(.info, "[webui.browser] replacing tracked pid old={d} new={d}\n", .{ existing, pid });
                    core_runtime.terminateBrowserProcess(allocator, existing);
                }
            }
            if (self.launched_browser_pid == null) {
                self.rpc_state.logf(.info, "[webui.browser] tracking launched browser pid={d} kind={s}\n", .{
                    pid,
                    if (launch.kind) |kind| @tagName(kind) else "unknown",
                });
            }
            self.launched_browser_pid = pid;
        } else {
            if (self.launched_browser_pid) |existing| {
                self.rpc_state.logf(.info, "[webui.browser] replacing tracked pid old={d} with untracked browser launch\n", .{existing});
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

        if (requested_surface != launched_surface) {
            self.runtime_render_state.fallback_applied = true;
            self.runtime_render_state.fallback_reason = switch (requested_surface) {
                .native_webview => .native_backend_unavailable,
                .browser_window, .web_url => .launch_failed,
            };
            self.runtime_render_state.active_surface = launched_surface;
            self.runtime_render_state.active_transport = switch (launched_surface) {
                .native_webview => .native_webview,
                .browser_window, .web_url => .browser_fallback,
            };
            self.emit(.window_state, "fallback-applied", @tagName(launched_surface));
        } else {
            self.runtime_render_state.active_surface = launched_surface;
            self.runtime_render_state.active_transport = switch (launched_surface) {
                .native_webview => .native_webview,
                .browser_window, .web_url => .browser_fallback,
            };
        }

        if (launch.used_system_fallback) {
            self.rpc_state.logf(.warn, "[webui.browser] system fallback launcher was used (tab-style window may appear)\n", .{});
        }

        self.backend.attachBrowserProcess(launch.kind, launch.pid, launch.is_child_process);
        self.native_capabilities = self.backend.capabilities();
        if (self.isNativeWindowActive()) {
            self.backend.applyStyle(self.current_style) catch |err| {
                _ = self.setWarningFromBackendError(err);
            };
        }
    }

    pub fn cleanupBrowserProfileDir(self: *WindowState, allocator: std.mem.Allocator) void {
        if (self.launched_browser_profile_dir) |dir| {
            core_runtime.cleanupBrowserProfileDir(allocator, dir, self.launched_browser_profile_ownership);
            self.launched_browser_profile_dir = null;
            self.launched_browser_profile_ownership = .none;
        }
    }

    pub fn releaseBrowserProfileDirWithoutDelete(self: *WindowState, allocator: std.mem.Allocator) void {
        if (self.launched_browser_profile_dir) |dir| {
            allocator.free(dir);
            self.launched_browser_profile_dir = null;
            self.launched_browser_profile_ownership = .none;
        }
    }

    pub fn clearTrackedBrowserState(self: *WindowState, allocator: std.mem.Allocator) void {
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

    pub fn clearTrackedBrowserStateWithoutDelete(self: *WindowState, allocator: std.mem.Allocator) void {
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

    pub fn shouldTerminateTrackedBrowserProcess(self: *const WindowState) bool {
        // Browser/web-first runs should close the browser tab via lifecycle signal,
        // not force-kill the whole browser process.
        return self.launch_policy.first == .native_webview;
    }

    pub fn markClosedFromTrackedBrowserExit(self: *WindowState, allocator: std.mem.Allocator, event_name: []const u8) void {
        self.clearTrackedBrowserState(allocator);
        if (!self.close_requested.load(.acquire)) {
            self.close_requested.store(true, .release);
            self.emit(.close_requested, event_name, "");
        }
    }

    pub fn reconcileChildExit(self: *WindowState, allocator: std.mem.Allocator) void {
        self.reconcilePendingLifecycleCloseLocked();

        const pid = self.launched_browser_pid orelse return;

        // IMPORTANT:
        // In browser/web modes, the PID we track can be a short-lived launcher process
        // (or helper) rather than the long-lived browser tab/window process.
        // We must not close the backend just because that PID exits.
        // Only native-webview-first mode treats tracked process death as a terminal close.
        const should_close_on_pid_exit = self.launch_policy.first == .native_webview;

        if (self.launched_browser_lifecycle_linked and core_runtime.linkedChildExited(pid)) {
            if (should_close_on_pid_exit) {
                self.markClosedFromTrackedBrowserExit(allocator, "child-exited");
            } else {
                self.clearTrackedBrowserState(allocator);
                self.emit(.window_state, "browser-detached", "child-exited");
            }
            return;
        }

        if (!core_runtime.isProcessAlive(pid)) {
            if (should_close_on_pid_exit) {
                self.markClosedFromTrackedBrowserExit(allocator, "browser-exited");
            } else {
                self.clearTrackedBrowserState(allocator);
                self.emit(.window_state, "browser-detached", "browser-exited");
            }
        }
    }

    pub fn requestLifecycleCloseFromFrontend(self: *WindowState) void {
        // Frontend lifecycle close is only used for browser-window mode.
        // For browser refresh, this should *not* terminate backend immediately.
        if (self.runtime_render_state.active_surface != .browser_window) return;

        if (self.launched_browser_pid) |pid| {
            if (core_runtime.isProcessAlive(pid)) {
                self.rpc_state.logf(.debug, "[webui.lifecycle] browser-window close requested while tracked pid alive pid={d}\n", .{pid});
            }
        }

        self.scheduleLifecycleCloseLocked();
    }

    pub fn terminateLaunchedBrowser(self: *WindowState, allocator: std.mem.Allocator) void {
        const should_terminate = self.shouldTerminateTrackedBrowserProcess();
        if (self.launched_browser_pid) |pid| {
            if (should_terminate) {
                self.rpc_state.logf(.info, "[webui.browser] terminating tracked browser pid={d}\n", .{pid});
                core_runtime.terminateBrowserProcess(allocator, pid);
            } else {
                self.rpc_state.logf(
                    .debug,
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

    pub fn localRenderUrl(self: *const WindowState, allocator: std.mem.Allocator) ![]u8 {
        const scheme = if (self.server_tls_enabled) "https" else "http";
        return std.fmt.allocPrint(allocator, "{s}://127.0.0.1:{d}/", .{ scheme, self.server_port });
    }

    pub fn effectiveBrowserLaunchOptions(self: *const WindowState, base: BrowserLaunchOptions) BrowserLaunchOptions {
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

    pub fn shouldOpenBrowser(self: *const WindowState) bool {
        if (self.runtime_render_state.active_surface == .browser_window) return true;
        if (self.runtime_render_state.active_surface == .native_webview) {
            // Native launch may require host bootstrap on first render.
            if (!self.backend.isReady()) return true;
            if (!self.launch_policy.allow_dual_surface) return false;
            return launchPolicyContains(self.launch_policy, .browser_window);
        }
        return false;
    }

    pub fn shouldAttemptBrowserSpawnLocked(
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

    pub fn resolveAfterBrowserLaunchFailure(self: *WindowState, failed_surface: LaunchSurface) bool {
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

    pub fn ensureBrowserRenderState(self: *WindowState, allocator: std.mem.Allocator, app_options: AppOptions) !void {
        if (!self.shouldServeBrowser()) return;
        try self.ensureServerStarted();
        try self.ensureServerReachable();

        const url = try self.localRenderUrl(allocator);
        defer allocator.free(url);
        try replaceOwned(allocator, &self.last_url, url);

        // Prevent automated browser popups during `zig test`; tests can still
        // exercise HTTP/WS routes via the local URL and explicit APIs.
        if (builtin.is_test) return;

        if (self.shouldAttemptBrowserSpawnLocked(allocator, true)) {
            const launch_options = self.effectiveBrowserLaunchOptions(app_options.browser_launch);
            if (core_runtime.openInBrowser(allocator, url, self.current_style, launch_options)) |launch| {
                self.setLaunchedBrowserLaunch(allocator, launch);
            } else |err| {
                _ = self.resolveAfterBrowserLaunchFailure(self.runtime_render_state.active_surface);
                self.rpc_state.logf(.warn, "[webui.browser] launch failed error={s}\n", .{@errorName(err)});
                if (self.runtime_render_state.active_surface != .browser_window) return;
                if (self.launch_policy.app_mode_required) return err;
            }
        }
    }

    const ClientRef = struct {
        client_id: usize,
        connection_id: usize,
    };

    pub fn findOrCreateClientSessionLocked(self: *WindowState, token: []const u8) !ClientRef {
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

    pub fn queueScriptLocked(
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

    pub fn queueFrontendRpcLocked(
        self: *WindowState,
        allocator: std.mem.Allocator,
        function_name: []const u8,
        args_json: []const u8,
        target_connection: ?usize,
        expect_result: bool,
    ) !*FrontendRpcTask {
        const task = try FrontendRpcTask.init(
            allocator,
            self.next_frontend_rpc_id,
            function_name,
            args_json,
            target_connection,
            expect_result,
        );
        self.next_frontend_rpc_id += 1;
        try self.frontend_rpc_pending.append(task);
        try self.dispatchPendingFrontendRpcTasksLocked();
        return task;
    }

    pub fn sendWsTextLocked(_: *WindowState, transport: *WsTransport, payload: []const u8) !void {
        try net_io.writeWsFrameAny(transport, .text, payload);
    }

    pub fn registerWsConnectionLocked(self: *WindowState, connection_id: usize, transport_value: anytype) !void {
        // Reconnect during unload/refresh grace period means the page is back.
        // Cancel any pending lifecycle close request.
        self.cancelPendingLifecycleCloseLocked("websocket-connected");
        const transport: WsTransport = switch (@TypeOf(transport_value)) {
            std.net.Stream => .{ .plain = transport_value },
            *https_server.Connection => .{ .tls = transport_value },
            else => @compileError("unsupported websocket transport type"),
        };

        for (self.ws_connections.items) |*entry| {
            if (entry.connection_id != connection_id) continue;
            entry.transport.shutdown();
            entry.transport = transport;
            try self.dispatchPendingScriptTasksLocked();
            try self.dispatchPendingFrontendRpcTasksLocked();
            return;
        }
        try self.ws_connections.append(.{
            .connection_id = connection_id,
            .transport = transport,
        });
        try self.dispatchPendingScriptTasksLocked();
        try self.dispatchPendingFrontendRpcTasksLocked();
    }

    pub fn unregisterWsConnectionLocked(self: *WindowState, connection_id: usize) void {
        for (self.ws_connections.items, 0..) |entry, idx| {
            if (entry.connection_id != connection_id) continue;
            _ = self.ws_connections.orderedRemove(idx);
            return;
        }
    }

    pub fn noteWsDisconnectLocked(self: *WindowState, reason: []const u8) void {
        // Browser-window lifecycle should terminate backend when the window is
        // gone, even when explicit lifecycle "window_closing" is not delivered
        // (for example some browser/window-manager close paths).
        // Keep grace semantics so refresh/reload reconnect can cancel shutdown.
        if (self.runtime_render_state.active_surface != .browser_window) return;
        if (self.close_requested.load(.acquire)) return;
        if (self.ws_connections.items.len != 0) return;
        self.rpc_state.logf(.debug, "[webui.lifecycle] scheduling close from ws disconnect reason={s}\n", .{reason});
        self.scheduleLifecycleCloseLocked();
    }

    pub fn closeWsConnectionLocked(self: *WindowState, connection_id: usize) void {
        for (self.ws_connections.items, 0..) |*entry, idx| {
            if (entry.connection_id != connection_id) continue;
            entry.transport.shutdown();
            _ = self.ws_connections.orderedRemove(idx);
            return;
        }
    }

    pub fn closeAllWsConnectionsLocked(self: *WindowState) void {
        for (self.ws_connections.items) |*entry| {
            entry.transport.shutdown();
        }
        self.ws_connections.clearRetainingCapacity();
    }

    pub fn findWsConnectionByIdLocked(self: *WindowState, connection_id: usize) ?*WsConnectionState {
        for (self.ws_connections.items) |*entry| {
            if (entry.connection_id == connection_id) return entry;
        }
        return null;
    }

    pub fn firstWsConnectionLocked(self: *WindowState) ?*WsConnectionState {
        if (self.ws_connections.items.len == 0) return null;
        return &self.ws_connections.items[0];
    }

    pub fn clientIdForConnectionLocked(self: *const WindowState, connection_id: usize) ?usize {
        for (self.client_sessions.items) |session| {
            if (session.connection_id == connection_id) return session.client_id;
        }
        return null;
    }

    pub fn dispatchPendingScriptTasksLocked(self: *WindowState) !void {
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

            self.sendWsTextLocked(&entry.transport, payload) catch |err| {
                self.rpc_state.logf(
                    .warn,
                    "[webui.ws] send failed connection_id={d} err={s}\n",
                    .{ entry.connection_id, @errorName(err) },
                );
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

    fn buildFrontendRpcRequestPayload(
        self: *WindowState,
        task: *FrontendRpcTask,
        connection_id: usize,
        client_id: usize,
    ) ![]u8 {
        const fn_name_json = try std.json.Stringify.valueAlloc(self.allocator, task.function_name, .{});
        defer self.allocator.free(fn_name_json);

        var payload = std.array_list.Managed(u8).init(self.allocator);
        errdefer payload.deinit();
        const writer = payload.writer();

        try writer.writeAll("{\"type\":\"frontend_rpc_request\",\"id\":");
        try writer.print("{d}", .{task.id});
        try writer.writeAll(",\"name\":");
        try writer.writeAll(fn_name_json);
        try writer.writeAll(",\"args\":");
        try writer.writeAll(task.args_json);
        try writer.writeAll(",\"expect_result\":");
        try writer.writeAll(if (task.expect_result) "true" else "false");
        try writer.writeAll(",\"client_id\":");
        try writer.print("{d}", .{client_id});
        try writer.writeAll(",\"connection_id\":");
        try writer.print("{d}", .{connection_id});
        try writer.writeAll("}");

        return payload.toOwnedSlice();
    }

    pub fn dispatchPendingFrontendRpcTasksLocked(self: *WindowState) !void {
        var idx: usize = 0;
        while (idx < self.frontend_rpc_pending.items.len) {
            const task = self.frontend_rpc_pending.items[idx];

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
            const payload = try self.buildFrontendRpcRequestPayload(task, entry.connection_id, client_id);
            defer self.allocator.free(payload);

            self.sendWsTextLocked(&entry.transport, payload) catch |err| {
                self.rpc_state.logf(
                    .warn,
                    "[webui.ws] frontend rpc send failed connection_id={d} err={s}\n",
                    .{ entry.connection_id, @errorName(err) },
                );
                self.closeWsConnectionLocked(entry.connection_id);
                idx += 1;
                continue;
            };

            _ = self.frontend_rpc_pending.orderedRemove(idx);

            if (task.expect_result) {
                try self.frontend_rpc_inflight.append(task);
            } else {
                task.mutex.lock();
                task.done = true;
                task.cond.signal();
                task.mutex.unlock();
                task.deinit();
            }
        }
    }

    pub fn pushBackendCloseSignalLocked(self: *WindowState, reason: []const u8) !u64 {
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
            const entry = &self.ws_connections.items[idx];
            self.sendWsTextLocked(&entry.transport, payload) catch |err| {
                self.rpc_state.logf(
                    .warn,
                    "[webui.ws] close signal write failed connection_id={d} err={s}\n",
                    .{ entry.connection_id, @errorName(err) },
                );
                self.closeWsConnectionLocked(entry.connection_id);
                continue;
            };
            sent_any = true;
            idx += 1;
        }

        if (!sent_any) return 0;
        return signal_id;
    }

    pub fn waitForCloseAckLocked(self: *WindowState, signal_id: u64, timeout_ms: u32) bool {
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

    fn scheduleLifecycleCloseLocked(self: *WindowState) void {
        if (self.close_requested.load(.acquire)) return;
        self.lifecycle_close_pending = true;
        self.lifecycle_close_deadline_ms = std.time.milliTimestamp() + lifecycle_close_grace_ms;
        self.rpc_state.logf(
            .debug,
            "[webui.lifecycle] scheduled browser-window close grace_ms={d}\n",
            .{lifecycle_close_grace_ms},
        );
    }

    fn cancelPendingLifecycleCloseLocked(self: *WindowState, reason: []const u8) void {
        if (!self.lifecycle_close_pending) return;
        self.lifecycle_close_pending = false;
        self.lifecycle_close_deadline_ms = 0;
        self.rpc_state.logf(.debug, "[webui.lifecycle] canceled pending close reason={s}\n", .{reason});
    }

    fn reconcilePendingLifecycleCloseLocked(self: *WindowState) void {
        if (!self.lifecycle_close_pending) return;
        if (self.runtime_render_state.active_surface != .browser_window) {
            self.cancelPendingLifecycleCloseLocked("non-browser-surface");
            return;
        }
        if (self.close_requested.load(.acquire)) {
            self.cancelPendingLifecycleCloseLocked("close-already-requested");
            return;
        }
        if (self.ws_connections.items.len > 0) {
            self.cancelPendingLifecycleCloseLocked("websocket-reconnected");
            return;
        }
        if (std.time.milliTimestamp() < self.lifecycle_close_deadline_ms) return;

        self.lifecycle_close_pending = false;
        self.lifecycle_close_deadline_ms = 0;
        self.rpc_state.logf(.debug, "[webui.lifecycle] pending close grace elapsed; requesting close\n", .{});
        _ = self.requestClose();
    }

    pub fn notifyFrontendCloseLocked(self: *WindowState, reason: []const u8, timeout_ms: u32) void {
        const signal_id = self.pushBackendCloseSignalLocked(reason) catch 0;
        if (signal_id == 0) return;

        const acked = self.waitForCloseAckLocked(signal_id, timeout_ms);
        self.rpc_state.logf(
            .debug,
            "[webui.ws] close signal id={d} acked={any}\n",
            .{ signal_id, acked },
        );
    }

    pub fn removeScriptPendingLocked(self: *WindowState, task: *ScriptTask) bool {
        for (self.script_pending.items, 0..) |pending, idx| {
            if (pending != task) continue;
            _ = self.script_pending.orderedRemove(idx);
            return true;
        }
        return false;
    }

    pub fn removeScriptInflightLocked(self: *WindowState, task: *ScriptTask) bool {
        for (self.script_inflight.items, 0..) |inflight, idx| {
            if (inflight != task) continue;
            _ = self.script_inflight.orderedRemove(idx);
            return true;
        }
        return false;
    }

    pub fn completeScriptTaskLocked(
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

    pub fn markScriptTimedOutLocked(self: *WindowState, task: *ScriptTask) void {
        _ = self.removeScriptPendingLocked(task);
        _ = self.removeScriptInflightLocked(task);
        task.mutex.lock();
        task.timed_out = true;
        task.done = true;
        task.cond.signal();
        task.mutex.unlock();
    }

    pub fn removeFrontendRpcPendingLocked(self: *WindowState, task: *FrontendRpcTask) bool {
        for (self.frontend_rpc_pending.items, 0..) |pending, idx| {
            if (pending != task) continue;
            _ = self.frontend_rpc_pending.orderedRemove(idx);
            return true;
        }
        return false;
    }

    pub fn removeFrontendRpcInflightLocked(self: *WindowState, task: *FrontendRpcTask) bool {
        for (self.frontend_rpc_inflight.items, 0..) |inflight, idx| {
            if (inflight != task) continue;
            _ = self.frontend_rpc_inflight.orderedRemove(idx);
            return true;
        }
        return false;
    }

    pub fn completeFrontendRpcTaskLocked(
        self: *WindowState,
        task_id: u64,
        js_error: bool,
        value_json: ?[]const u8,
        error_message: ?[]const u8,
    ) !bool {
        for (self.frontend_rpc_inflight.items, 0..) |task, idx| {
            if (task.id != task_id) continue;
            _ = self.frontend_rpc_inflight.orderedRemove(idx);

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

    pub fn markFrontendRpcTimedOutLocked(self: *WindowState, task: *FrontendRpcTask) void {
        _ = self.removeFrontendRpcPendingLocked(task);
        _ = self.removeFrontendRpcInflightLocked(task);
        task.mutex.lock();
        task.timed_out = true;
        task.done = true;
        task.cond.signal();
        task.mutex.unlock();
    }

    pub fn handleWebSocketClientMessage(self: *WindowState, _: usize, data: []const u8) !void {
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

        if (std.mem.eql(u8, msg_type_value.string, "frontend_rpc_response")) {
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
            _ = try self.completeFrontendRpcTaskLocked(task_id, js_error, value_json, error_message);
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

    pub fn deinit(self: *WindowState, allocator: std.mem.Allocator) void {
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

        for (self.frontend_rpc_pending.items) |task| task.deinit();
        self.frontend_rpc_pending.deinit();

        for (self.frontend_rpc_inflight.items) |task| {
            task.mutex.lock();
            task.timed_out = true;
            task.done = true;
            task.cond.broadcast();
            task.mutex.unlock();
            task.deinit();
        }
        self.frontend_rpc_inflight.deinit();
        self.ws_connections.deinit();

        self.terminateLaunchedBrowser(allocator);
        self.backend.destroyWindow();
        self.backend.deinit();
        self.rpc_state.deinit(allocator);
    }

    pub fn ensureServerStarted(self: *WindowState) !void {
        if (self.server_thread != null) return;
        if (self.server_tls_enabled and (self.server_tls_cert_pem == null or self.server_tls_key_pem == null)) {
            return error.TlsCertificateMissing;
        }

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

    pub fn ensureServerReachable(self: *WindowState) !void {
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

    pub fn stopServer(self: *WindowState) void {
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

    pub fn serverThreadMain(self: *WindowState) void {
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

    pub fn connectionThreadMain(self: *WindowState, stream: std.net.Stream) void {
        defer {
            self.connection_mutex.lock();
            if (self.active_connection_workers > 0) {
                self.active_connection_workers -= 1;
            }
            self.connection_cond.broadcast();
            self.connection_mutex.unlock();
        }

        if (self.server_tls_enabled) {
            const first_byte = https_server.peekFirstByte(stream) catch null;
            if (first_byte) |byte| {
                if (!https_server.looksLikeTlsClientHello(byte)) {
                    const request = net_io.readHttpRequest(std.heap.page_allocator, stream) catch {
                        stream.close();
                        return;
                    };
                    defer std.heap.page_allocator.free(request.raw);

                    const fallback_host = std.fmt.allocPrint(std.heap.page_allocator, "127.0.0.1:{d}", .{self.server_port}) catch {
                        stream.close();
                        return;
                    };
                    defer std.heap.page_allocator.free(fallback_host);
                    const host = net_io.httpHeaderValue(request.headers, "Host") orelse fallback_host;

                    const redirect_url = std.fmt.allocPrint(std.heap.page_allocator, "https://{s}{s}", .{ host, request.path }) catch {
                        stream.close();
                        return;
                    };
                    defer std.heap.page_allocator.free(redirect_url);

                    net_io.writeHttpRedirectAny(stream, redirect_url) catch {};
                    stream.close();
                    return;
                }
            }

            const cert_pem = self.server_tls_cert_pem orelse {
                stream.close();
                return;
            };
            const key_pem = self.server_tls_key_pem orelse {
                stream.close();
                return;
            };

            const tls_conn = std.heap.page_allocator.create(https_server.Connection) catch {
                stream.close();
                return;
            };
            tls_conn.* = https_server.Connection.initServer(std.heap.page_allocator, stream, cert_pem, key_pem) catch |err| {
                self.emitDiagnostic("tls.handshake.error", .tls, .warn, @errorName(err));
                std.heap.page_allocator.destroy(tls_conn);
                stream.close();
                return;
            };

            const transfer_tls_ownership = server_routes.handleConnection(self, std.heap.page_allocator, tls_conn, default_client_token) catch {
                tls_conn.close();
                std.heap.page_allocator.destroy(tls_conn);
                return;
            };
            if (!transfer_tls_ownership) {
                tls_conn.close();
                std.heap.page_allocator.destroy(tls_conn);
            }
            return;
        }

        const transfer_plain_ownership = server_routes.handleConnection(self, std.heap.page_allocator, stream, default_client_token) catch {
            stream.close();
            return;
        };
        if (!transfer_plain_ownership) {
            stream.close();
        }
    }
};

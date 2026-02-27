const std = @import("std");
const builtin = @import("builtin");

const bridge_template = @import("bridge/template.zig");
const bridge_runtime_helpers = @import("bridge/runtime_helpers.zig");
const core_runtime = @import("ported/webui.zig");
const civetweb = @import("network/civetweb.zig");
const tls_runtime = @import("network/tls_runtime.zig");
pub const process_signals = @import("process_signals.zig");
const window_style_types = @import("window_style.zig");
const api_types = @import("root/api_types.zig");
const launch_policy = @import("root/launch_policy.zig");
const rpc_reflect = @import("root/rpc_reflect.zig");
const rpc_runtime = @import("root/rpc_runtime.zig");
const root_utils = @import("root/utils.zig");
const net_io = @import("root/net_io.zig");
const window_state = @import("root/window_state.zig");
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

pub const BuildFlags = api_types.BuildFlags;
pub const DispatcherMode = api_types.DispatcherMode;
pub const TransportMode = api_types.TransportMode;
pub const LaunchSurface = api_types.LaunchSurface;
pub const LaunchPolicy = api_types.LaunchPolicy;
pub const FallbackReason = api_types.FallbackReason;
pub const RuntimeRenderState = api_types.RuntimeRenderState;
pub const DiagnosticCategory = api_types.DiagnosticCategory;
pub const DiagnosticSeverity = api_types.DiagnosticSeverity;
pub const Diagnostic = api_types.Diagnostic;
pub const EventKind = api_types.EventKind;
pub const BridgeOptions = api_types.BridgeOptions;
pub const Event = api_types.Event;
pub const EventHandler = api_types.EventHandler;
pub const RawHandler = api_types.RawHandler;
pub const RpcInvokeFn = api_types.RpcInvokeFn;
pub const CustomDispatcher = api_types.CustomDispatcher;
pub const RpcOptions = api_types.RpcOptions;
pub const AppOptions = api_types.AppOptions;
pub const WindowOptions = api_types.WindowOptions;
pub const WindowContent = api_types.WindowContent;
pub const WindowControlResult = api_types.WindowControlResult;
pub const ScriptTarget = api_types.ScriptTarget;
pub const ScriptOptions = api_types.ScriptOptions;
pub const ScriptEvalResult = api_types.ScriptEvalResult;
pub const RuntimeRequirement = api_types.RuntimeRequirement;
pub const EffectiveCapabilities = api_types.EffectiveCapabilities;
pub const ServiceOptions = api_types.ServiceOptions;

pub const test_helpers = struct {
    pub const readAllFromStream = net_io.readAllFromStream;
    pub const httpRoundTrip = net_io.httpRoundTrip;
    pub const httpRoundTripWithHeaders = net_io.httpRoundTripWithHeaders;
    pub const readHttpHeadersFromStream = net_io.readHttpHeadersFromStream;
};

const launchPolicyOrder = launch_policy.order;
const launchPolicyContains = launch_policy.contains;
const launchPolicyNextAfter = launch_policy.nextAfter;

const RpcRegistryState = rpc_runtime.State;

pub const DiagnosticHandler = window_state.DiagnosticHandler;
const DiagnosticCallbackState = window_state.DiagnosticCallbackState;
const WindowState = window_state.WindowState;

const PinnedStructOwner = enum {
    app,
    service,
};

const DiagnosticCallbackBindingMismatch = struct {
    window_id: usize,
    expected_ptr: usize,
    actual_ptr: usize,
};

pub fn pinnedMoveGuardEnabled() bool {
    return switch (builtin.mode) {
        .Debug, .ReleaseSafe => true,
        .ReleaseFast, .ReleaseSmall => false,
    };
}

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

    fn refreshRenderedContentLocked(self: *Window, win_state: *WindowState) !void {
        try win_state.ensureBrowserRenderState(self.app.allocator, self.app.options);
        if (win_state.isNativeWindowActive()) {
            if (win_state.last_url) |url| {
                _ = win_state.backend.showContent(.{ .url = url }) catch {};
            }
        }
    }

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

        try self.refreshRenderedContentLocked(win_state);

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

        try self.refreshRenderedContentLocked(win_state);

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

    pub fn rpcClientScript(self: *Window) []const u8 {
        return self.rpc().generatedClientScript();
    }

    pub fn rpcTypeDeclarations(self: *Window) []const u8 {
        return self.rpc().generatedTypeScriptDeclarations();
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

    pub fn state(self: *Window) *WindowState {
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
        // Reconcile tracked process state every loop.
        // `reconcileChildExit()` is mode-aware and only turns PID exit into app close
        // for native-webview-first mode. Browser/web modes only detach PID tracking.
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

    pub fn rpcClientScript(self: *Service) []const u8 {
        var win = self.window();
        return win.rpcClientScript();
    }

    pub fn rpcTypeDeclarations(self: *Service) []const u8 {
        var win = self.window();
        return win.rpcTypeDeclarations();
    }

    pub fn generatedClientScriptComptime(comptime rpc_methods: type, comptime options: BridgeOptions) []const u8 {
        return RpcRegistry.generatedClientScriptComptime(rpc_methods, options);
    }

    pub fn generatedTypeScriptDeclarationsComptime(comptime rpc_methods: type, comptime options: BridgeOptions) []const u8 {
        return RpcRegistry.generatedTypeScriptDeclarationsComptime(rpc_methods, options);
    }

    pub fn hasStableDiagnosticCallbackBindings(self: *const Service) bool {
        return self.app.hasStableDiagnosticCallbackBindings();
    }

    pub fn checkPinnedMoveInvariant(self: *Service, fail_fast: bool) bool {
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
        if (!std.mem.eql(u8, options.bridge_options.namespace, "webuiRpc") or
            !std.mem.eql(u8, options.bridge_options.script_route, "/webui_bridge.js") or
            !std.mem.eql(u8, options.bridge_options.rpc_route, "/webui/rpc"))
        {
            return error.BridgeOptionsMustUseDefaultsForComptimeGeneration;
        }

        self.state.bridge_options = options.bridge_options;
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
        self.state.generated_script = RpcRegistry.generatedClientScriptComptime(RpcStruct, .{});
        self.state.generated_typescript = RpcRegistry.generatedTypeScriptDeclarationsComptime(RpcStruct, .{});
    }

    pub fn generatedClientScript(self: RpcRegistry) []const u8 {
        return self.state.generated_script;
    }

    pub fn generatedClientScriptComptime(comptime RpcStruct: type, comptime options: BridgeOptions) []const u8 {
        return bridge_template.renderComptime(RpcStruct, .{
            .namespace = options.namespace,
            .rpc_route = options.rpc_route,
        });
    }

    pub fn writeGeneratedClientScript(self: RpcRegistry, output_path: []const u8) !void {
        if (std.fs.path.dirname(output_path)) |dir_name| {
            try std.fs.cwd().makePath(dir_name);
        }
        const file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(self.generatedClientScript());
    }

    pub fn generatedTypeScriptDeclarations(self: RpcRegistry) []const u8 {
        return self.state.generated_typescript;
    }

    pub fn generatedTypeScriptDeclarationsComptime(comptime RpcStruct: type, comptime options: BridgeOptions) []const u8 {
        return bridge_template.renderTypeScriptDeclarationsComptime(RpcStruct, .{
            .namespace = options.namespace,
            .rpc_route = options.rpc_route,
        });
    }

    pub fn writeGeneratedTypeScriptDeclarations(self: RpcRegistry, output_path: []const u8) !void {
        const script = self.generatedTypeScriptDeclarations();
        if (std.fs.path.dirname(output_path)) |dir_name| {
            try std.fs.cwd().makePath(dir_name);
        }
        const file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(script);
    }
};

const buildTsArgSignature = rpc_reflect.buildTsArgSignature;
const tsTypeNameForReturn = rpc_reflect.tsTypeNameForReturn;
const makeInvoker = rpc_reflect.makeInvoker;
const replaceOwned = root_utils.replaceOwned;
const isLikelyUrl = root_utils.isLikelyUrl;

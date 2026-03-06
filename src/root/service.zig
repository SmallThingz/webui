const std = @import("std");

const api_types = @import("api_types.zig");
const app_mod = @import("app.zig");
const launch_policy = @import("launch_policy.zig");
const process_signals = @import("process_signals.zig");
const rpc_registry_mod = @import("rpc_registry.zig");
const runtime_requirements = @import("runtime_requirements.zig");
const window_mod = @import("window.zig");

const App = app_mod.App;
const BrowserLaunchOptions = @import("../ported/webui.zig").BrowserLaunchOptions;
const CloseHandler = @import("window_style.zig").CloseHandler;
const DiagnosticHandler = @import("window_state.zig").DiagnosticHandler;
const EffectiveCapabilities = api_types.EffectiveCapabilities;
const EventHandler = api_types.EventHandler;
const FrontendCallResult = api_types.FrontendCallResult;
const RawHandler = api_types.RawHandler;
const RpcOptions = api_types.RpcOptions;
const RuntimeRenderState = api_types.RuntimeRenderState;
const RuntimeRequirement = api_types.RuntimeRequirement;
const ScriptEvalResult = api_types.ScriptEvalResult;
const ScriptOptions = api_types.ScriptOptions;
const ServiceOptions = api_types.ServiceOptions;
const TlsInfo = @import("../network/tls_runtime.zig").TlsInfo;
const Window = window_mod.Window;
const WindowCapability = @import("window_style.zig").WindowCapability;
const WindowContent = api_types.WindowContent;
const WindowControl = @import("window_style.zig").WindowControl;
const WindowControlResult = api_types.WindowControlResult;
const WindowStyle = @import("window_style.zig").WindowStyle;

/// Bundles an `App` with a primary window and optional signal handling for simple applications.
pub const Service = struct {
    app: App,
    window_index: usize,
    window_id: usize,
    process_signals_enabled: bool,

    /// Initializes a service, creates the primary window, and binds the provided RPC methods.
    pub inline fn init(allocator: std.mem.Allocator, comptime rpc_methods: type, options: ServiceOptions) !Service {
        var service: Service = undefined;
        service.app = try App.init(allocator, options.app);
        errdefer service.app.deinit();

        var main_window = try service.app.newWindow(options.window);
        try main_window.bindRpc(rpc_methods, options.rpc);

        service.window_index = main_window.index;
        service.window_id = main_window.id;
        service.process_signals_enabled = options.process_signals;
        if (service.process_signals_enabled) {
            process_signals.install();
        }
        return service;
    }

    /// Initializes a service with default options.
    pub fn initDefault(allocator: std.mem.Allocator, comptime rpc_methods: type) !Service {
        return init(allocator, rpc_methods, .{});
    }

    /// Releases all service-owned resources.
    pub fn deinit(self: *Service) void {
        self.app.deinit();
    }

    /// Returns the primary window handle.
    pub fn window(self: *Service) Window {
        self.enforcePinnedMoveInvariant();
        return .{
            .app = &self.app,
            .index = self.window_index,
            .id = self.window_id,
        };
    }

    /// Runs the underlying app startup sequence.
    pub fn run(self: *Service) !void {
        try self.app.run();
    }

    /// Returns whether the service should exit based on signals, native close, or tracked process state.
    pub fn shouldExit(self: *Service) bool {
        if (self.process_signals_enabled and process_signals.stopRequested()) {
            self.app.shutdown();
            return true;
        }
        if (self.app.shutdown_requested) return true;
        var win = self.window();
        const state = win.state();
        state.state_mutex.lock();
        defer state.state_mutex.unlock();
        if (state.isNativeWindowActive()) {
            state.backend.pumpEvents() catch |err| {
                if (err == error.NativeWindowClosed) {
                    _ = state.requestClose();
                }
            };
        }
        state.reconcileChildExit(self.app.allocator);
        return state.close_requested.load(.acquire);
    }

    /// Enables or disables process signal integration.
    pub fn setProcessSignalsEnabled(self: *Service, enabled: bool) void {
        self.process_signals_enabled = enabled;
        if (enabled) process_signals.install();
    }

    /// Shuts down the underlying app.
    pub fn shutdown(self: *Service) void {
        self.app.shutdown();
    }

    /// Sets the TLS certificate pair used by the app.
    pub fn setTlsCertificate(self: *Service, cert_pem: []const u8, key_pem: []const u8) !void {
        try self.app.setTlsCertificate(cert_pem, key_pem);
    }

    /// Returns the effective TLS runtime state.
    pub fn tlsInfo(self: *Service) TlsInfo {
        return self.app.tlsInfo();
    }

    /// Installs a diagnostic callback.
    pub fn onDiagnostic(self: *Service, handler: DiagnosticHandler, context: ?*anyopaque) void {
        self.app.onDiagnostic(handler, context);
    }

    /// Shows HTML, a file, or a URL in the primary window.
    pub fn show(self: *Service, content: WindowContent) !void {
        var win = self.window();
        try win.show(content);
    }

    /// Shows raw HTML in the primary window.
    pub fn showHtml(self: *Service, html: []const u8) !void {
        var win = self.window();
        try win.showHtml(html);
    }

    /// Shows a local file in the primary window.
    pub fn showFile(self: *Service, path: []const u8) !void {
        var win = self.window();
        try win.showFile(path);
    }

    /// Shows a URL in the primary window.
    pub fn showUrl(self: *Service, url: []const u8) !void {
        var win = self.window();
        try win.showUrl(url);
    }

    /// Navigates the primary window to a URL.
    pub fn navigate(self: *Service, url: []const u8) !void {
        var win = self.window();
        try win.navigate(url);
    }

    /// Applies native style changes to the primary window.
    pub fn applyStyle(self: *Service, style: WindowStyle) !void {
        var win = self.window();
        try win.applyStyle(style);
    }

    /// Returns the current primary window style.
    pub fn currentStyle(self: *Service) WindowStyle {
        var win = self.window();
        return win.currentStyle();
    }

    /// Returns the last warning emitted by the primary window, if any.
    pub fn lastWarning(self: *Service) ?[]const u8 {
        var win = self.window();
        return win.lastWarning();
    }

    /// Clears the primary window warning.
    pub fn clearWarning(self: *Service) void {
        var win = self.window();
        win.clearWarning();
    }

    /// Sends a native window control command to the primary window.
    pub fn control(self: *Service, cmd: WindowControl) !WindowControlResult {
        var win = self.window();
        return win.control(cmd);
    }

    /// Installs a close handler on the primary window.
    pub fn setCloseHandler(self: *Service, handler: CloseHandler, context: ?*anyopaque) void {
        var win = self.window();
        win.setCloseHandler(handler, context);
    }

    /// Removes any close handler from the primary window.
    pub fn clearCloseHandler(self: *Service) void {
        var win = self.window();
        win.clearCloseHandler();
    }

    /// Returns the current capability set for the primary window.
    pub fn capabilities(self: *Service) []const WindowCapability {
        var win = self.window();
        return win.capabilities();
    }

    /// Returns the current runtime render state for the primary window.
    pub fn runtimeRenderState(self: *Service) RuntimeRenderState {
        var win = self.window();
        return win.runtimeRenderState();
    }

    /// Predicts capability and fallback behavior for the primary window.
    pub fn probeCapabilities(self: *Service) EffectiveCapabilities {
        var win = self.window();
        return win.probeCapabilities();
    }

    /// Lists runtime dependencies that affect the primary window's launch policy.
    pub fn listRuntimeRequirements(self: *Service, allocator: std.mem.Allocator) ![]RuntimeRequirement {
        var win = self.window();
        const win_state = win.state();
        win_state.state_mutex.lock();
        const native_available = win_state.backend.isNative();
        const policy = self.app.options.launch_policy;
        win_state.state_mutex.unlock();

        const reqs = try runtime_requirements.list(allocator, .{
            .uses_native_webview = launch_policy.contains(policy, .native_webview),
            .uses_managed_browser = launch_policy.contains(policy, .browser_window),
            .uses_web_url = launch_policy.contains(policy, .web_url),
            .app_mode_required = policy.app_mode_required,
            .native_backend_available = native_available,
            .linux_webview_target = self.app.options.linux_webview_target,
        });
        for (reqs) |req| {
            if (req.required and !req.available) {
                const message = req.details orelse "required runtime dependency unavailable";
                self.app.emitDiagnostic(self.window_id, req.name, .lifecycle, .warn, message);
            }
        }
        return reqs;
    }

    /// Installs an event callback on the primary window.
    pub fn onEvent(self: *Service, handler: EventHandler, context: ?*anyopaque) void {
        var win = self.window();
        win.onEvent(handler, context);
    }

    /// Installs a raw-byte callback on the primary window.
    pub fn onRaw(self: *Service, handler: RawHandler, context: ?*anyopaque) void {
        var win = self.window();
        win.onRaw(handler, context);
    }

    /// Sends raw bytes through the primary window's raw callback channel.
    pub fn sendRaw(self: *Service, bytes: []const u8) !void {
        var win = self.window();
        try win.sendRaw(bytes);
    }

    /// Queues JavaScript to run on the frontend without waiting for a result.
    pub fn runScript(self: *Service, script: []const u8, options: ScriptOptions) !void {
        var win = self.window();
        try win.runScript(script, options);
    }

    /// Invokes a frontend function and waits for a single result.
    pub fn callFrontend(
        self: *Service,
        allocator: std.mem.Allocator,
        function_name: []const u8,
        args: anytype,
        options: ScriptOptions,
    ) !ScriptEvalResult {
        var win = self.window();
        return win.callFrontend(allocator, function_name, args, options);
    }

    /// Invokes a frontend function without waiting for a result.
    pub fn callFrontendFireAndForget(
        self: *Service,
        function_name: []const u8,
        args: anytype,
        options: ScriptOptions,
    ) !void {
        var win = self.window();
        try win.callFrontendFireAndForget(function_name, args, options);
    }

    /// Invokes a frontend function on specific connections.
    pub fn callFrontendOnConnections(
        self: *Service,
        function_name: []const u8,
        args: anytype,
        connection_ids: []const usize,
    ) !void {
        var win = self.window();
        try win.callFrontendOnConnections(function_name, args, connection_ids);
    }

    /// Invokes a frontend function on all connected clients.
    pub fn callFrontendAll(self: *Service, function_name: []const u8, args: anytype) !void {
        var win = self.window();
        try win.callFrontendAll(function_name, args);
    }

    /// Invokes a frontend function on specific connections and waits for all results.
    pub fn callFrontendAwaitConnections(
        self: *Service,
        allocator: std.mem.Allocator,
        function_name: []const u8,
        args: anytype,
        connection_ids: []const usize,
        timeout_ms: ?u32,
    ) ![]FrontendCallResult {
        var win = self.window();
        return win.callFrontendAwaitConnections(allocator, function_name, args, connection_ids, timeout_ms);
    }

    /// Invokes a frontend function on all clients and waits for all results.
    pub fn callFrontendAwaitAll(
        self: *Service,
        allocator: std.mem.Allocator,
        function_name: []const u8,
        args: anytype,
        timeout_ms: ?u32,
    ) ![]FrontendCallResult {
        var win = self.window();
        return win.callFrontendAwaitAll(allocator, function_name, args, timeout_ms);
    }

    /// Evaluates JavaScript on the frontend and waits for a result.
    pub fn evalScript(
        self: *Service,
        allocator: std.mem.Allocator,
        script: []const u8,
        options: ScriptOptions,
    ) !ScriptEvalResult {
        var win = self.window();
        return win.evalScript(allocator, script, options);
    }

    /// Returns the served browser URL for the primary window.
    pub fn browserUrl(self: *Service) ![]u8 {
        var win = self.window();
        return win.browserUrl();
    }

    /// Opens the primary window in a browser using the app default launch options.
    pub fn openInBrowser(self: *Service) !void {
        var win = self.window();
        try win.openInBrowser();
    }

    /// Opens the primary window in a browser using explicit launch options.
    pub fn openInBrowserWithOptions(self: *Service, launch_options: BrowserLaunchOptions) !void {
        var win = self.window();
        try win.openInBrowserWithOptions(launch_options);
    }

    /// Returns the generated JavaScript RPC client bridge for the primary window.
    pub fn rpcClientScript(self: *Service) []const u8 {
        var win = self.window();
        return win.rpcClientScript();
    }

    /// Returns the generated TypeScript declarations for the primary window's RPC bridge.
    pub fn rpcTypeDeclarations(self: *Service) []const u8 {
        var win = self.window();
        return win.rpcTypeDeclarations();
    }

    /// Generates the JavaScript RPC client bridge at comptime for `rpc_methods`.
    pub fn generatedClientScriptComptime(comptime rpc_methods: type, comptime options: api_types.BridgeOptions) []const u8 {
        return rpc_registry_mod.RpcRegistry.generatedClientScriptComptime(rpc_methods, options);
    }

    /// Generates TypeScript declarations at comptime for `rpc_methods`.
    pub fn generatedTypeScriptDeclarationsComptime(comptime rpc_methods: type, comptime options: api_types.BridgeOptions) []const u8 {
        return rpc_registry_mod.RpcRegistry.generatedTypeScriptDeclarationsComptime(rpc_methods, options);
    }

    /// Returns whether the pinned-diagnostic binding is still stable.
    pub fn hasStableDiagnosticCallbackBindings(self: *const Service) bool {
        return self.app.hasStableDiagnosticCallbackBindings();
    }

    /// Checks whether the service has been moved after window initialization.
    pub fn checkPinnedMoveInvariant(self: *Service, fail_fast: bool) bool {
        return self.app.checkPinnedMoveInvariant(.service, fail_fast);
    }

    fn enforcePinnedMoveInvariant(self: *Service) void {
        _ = self.checkPinnedMoveInvariant(true);
    }
};

const std = @import("std");

const bridge_runtime_helpers = @import("bridge/runtime_helpers.zig");
const core_runtime = @import("ported/webui.zig");
const civetweb = @import("network/civetweb.zig");
const tls_runtime = @import("network/tls_runtime.zig");
const api_types = @import("root/api_types.zig");
const app_mod = @import("root/app.zig");
const logging_types = @import("root/logging.zig");
const net_io = @import("root/net_io.zig");
const rpc_registry_mod = @import("root/rpc_registry.zig");
const service_mod = @import("root/service.zig");
const window_mod = @import("root/window.zig");
const window_state = @import("root/window_state.zig");
const window_style_types = @import("root/window_style.zig");

pub const process_signals = @import("root/process_signals.zig");

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
pub const LogLevel = logging_types.Level;
pub const LogHandler = logging_types.Handler;
pub const LogSink = logging_types.Sink;

/// Creates a log sink from a handler and opaque context pointer.
pub fn logSink(comptime handler: LogHandler, context: ?*anyopaque) LogSink {
    return .{ .handler = handler, .context = context };
}

/// Resolves the preferred base directory prefix for browser/webview profile storage.
pub fn resolveProfileBasePrefix(allocator: std.mem.Allocator) ![]u8 {
    return core_runtime.resolveProfileBasePrefix(allocator);
}

/// Resolves the default managed profile path used for native webview mode.
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
pub const LinuxWebViewTarget = api_types.LinuxWebViewTarget;
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
pub const FrontendCallResult = api_types.FrontendCallResult;
pub const RuntimeRequirement = api_types.RuntimeRequirement;
pub const EffectiveCapabilities = api_types.EffectiveCapabilities;
pub const ServiceOptions = api_types.ServiceOptions;

pub const test_helpers = struct {
    pub const readAllFromStream = net_io.readAllFromStream;
    pub const httpRoundTrip = net_io.httpRoundTrip;
    pub const httpRoundTripWithHeaders = net_io.httpRoundTripWithHeaders;
    pub const readHttpHeadersFromStream = net_io.readHttpHeadersFromStream;
    pub const httpResponseBody = net_io.httpResponseBody;
};

pub const DiagnosticHandler = window_state.DiagnosticHandler;

/// Returns whether pinned-move diagnostics are enabled in the current build mode.
pub fn pinnedMoveGuardEnabled() bool {
    return window_mod.pinnedMoveGuardEnabled();
}

pub const App = app_mod.App;
pub const Window = window_mod.Window;
pub const Service = service_mod.Service;
pub const RpcRegistry = rpc_registry_mod.RpcRegistry;

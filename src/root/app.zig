const std = @import("std");
const builtin = @import("builtin");

const core_runtime = @import("../ported/webui.zig");
const tls_runtime = @import("../network/tls_runtime.zig");
const api_types = @import("api_types.zig");
const window_mod = @import("window.zig");
const window_state = @import("window_state.zig");

const AppOptions = api_types.AppOptions;
const Diagnostic = api_types.Diagnostic;
const DiagnosticCategory = api_types.DiagnosticCategory;
const DiagnosticSeverity = api_types.DiagnosticSeverity;
const Event = api_types.Event;
const EventKind = api_types.EventKind;
const EventHandler = api_types.EventHandler;
const TlsInfo = tls_runtime.TlsInfo;
const Window = window_mod.Window;
const WindowOptions = api_types.WindowOptions;
const WindowState = window_state.WindowState;
const DiagnosticHandler = window_state.DiagnosticHandler;
const DiagnosticCallbackState = window_state.DiagnosticCallbackState;

pub const PinnedStructOwner = enum {
    app,
    service,
};

const DiagnosticCallbackBindingMismatch = struct {
    window_id: usize,
    expected_ptr: usize,
    actual_ptr: usize,
};

/// Owns application-global configuration, windows, TLS state, and lifecycle control.
pub const App = struct {
    allocator: std.mem.Allocator,
    options: AppOptions,
    tls_state: tls_runtime.Runtime,
    windows: std.array_list.Managed(*WindowState),
    shutdown_requested: bool,
    next_window_id: usize,
    diagnostic_callback: DiagnosticCallbackState,

    /// Initializes an app with explicit options.
    pub fn init(allocator: std.mem.Allocator, options: AppOptions) !App {
        var resolved_options = options;
        if (resolved_options.enable_tls and !resolved_options.tls.enabled) resolved_options.tls.enabled = true;
        if (resolved_options.tls.enabled and !resolved_options.enable_tls) resolved_options.enable_tls = true;

        core_runtime.initializeRuntime(resolved_options.tls.enabled, resolved_options.enable_webui_log);
        const tls_state = try tls_runtime.Runtime.init(allocator, resolved_options.tls);
        if (tls_state.cert_pem) |cert| {
            resolved_options.tls.cert_pem = cert;
        }
        if (tls_state.key_pem) |key| {
            resolved_options.tls.key_pem = key;
        }
        return .{
            .allocator = allocator,
            .options = resolved_options,
            .tls_state = tls_state,
            .windows = std.array_list.Managed(*WindowState).init(allocator),
            .shutdown_requested = false,
            .next_window_id = 1,
            .diagnostic_callback = .{},
        };
    }

    /// Initializes an app with default options.
    pub fn initDefault(allocator: std.mem.Allocator) !App {
        return init(allocator, .{});
    }

    /// Releases all windows and app-owned resources.
    pub fn deinit(self: *App) void {
        for (self.windows.items) |state| {
            state.deinit(self.allocator);
            self.allocator.destroy(state);
        }
        self.windows.deinit();
        self.tls_state.deinit();
    }

    /// Sets the TLS certificate pair used by all managed HTTP/TLS servers.
    pub fn setTlsCertificate(self: *App, cert_pem: []const u8, key_pem: []const u8) !void {
        try self.tls_state.setCertificate(cert_pem, key_pem);
        self.options.enable_tls = true;
        self.options.tls.enabled = true;
        self.options.tls.cert_pem = self.tls_state.cert_pem;
        self.options.tls.key_pem = self.tls_state.key_pem;
        for (self.windows.items) |state| {
            state.state_mutex.lock();
            state.server_tls_enabled = self.options.tls.enabled and self.options.tls.cert_pem != null and self.options.tls.key_pem != null;
            state.server_tls_cert_pem = self.options.tls.cert_pem;
            state.server_tls_key_pem = self.options.tls.key_pem;
            state.state_mutex.unlock();
        }
    }

    /// Returns the effective TLS runtime state.
    pub fn tlsInfo(self: *const App) TlsInfo {
        return self.tls_state.info();
    }

    /// Installs a diagnostic callback and rebinds existing windows to it.
    pub fn onDiagnostic(self: *App, handler: DiagnosticHandler, context: ?*anyopaque) void {
        self.diagnostic_callback = .{
            .handler = handler,
            .context = context,
        };
        for (self.windows.items) |state| {
            state.state_mutex.lock();
            state.diagnostic_callback = &self.diagnostic_callback;
            state.state_mutex.unlock();
        }
    }

    /// Emits a diagnostic event for a specific window.
    pub fn emitDiagnostic(
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
        for (self.windows.items) |state| {
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

    /// Returns whether all windows still point at this app's diagnostic callback storage.
    pub fn hasStableDiagnosticCallbackBindings(self: *const App) bool {
        return self.firstDiagnosticCallbackBindingMismatch() == null;
    }

    /// Checks whether the app or service containing it has been moved after window initialization.
    pub fn checkPinnedMoveInvariant(self: *App, owner: PinnedStructOwner, fail_fast: bool) bool {
        if (comptime !window_mod.pinnedMoveGuardEnabled()) return true;
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

    /// Enforces the pinned-struct invariant and aborts on violation in guarded builds.
    pub fn enforcePinnedMoveInvariant(self: *App, owner: PinnedStructOwner) void {
        _ = self.checkPinnedMoveInvariant(owner, true);
    }

    /// Creates a new window with the provided options.
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

        for (self.windows.items) |state| {
            if (state.id == id) return error.InvalidWindowId;
        }

        const state = try self.allocator.create(WindowState);
        errdefer self.allocator.destroy(state);
        state.* = try WindowState.init(self.allocator, id, options, self.options, &self.diagnostic_callback);
        errdefer state.deinit(self.allocator);
        try self.windows.append(state);
        const idx = self.windows.items.len - 1;

        return .{
            .app = self,
            .index = idx,
            .id = id,
        };
    }

    /// Creates a new default window.
    pub fn window(self: *App) !Window {
        return self.newWindow(.{});
    }

    /// Creates a new window with a title.
    pub fn windowWithTitle(self: *App, title: []const u8) !Window {
        return self.newWindow(.{ .title = title });
    }

    /// Starts any pending window servers and emits initial connected/capability events.
    pub fn run(self: *App) !void {
        self.enforcePinnedMoveInvariant(.app);
        if (self.shutdown_requested) return;

        for (self.windows.items) |state| {
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

    /// Shuts down all windows, managed browser processes, and local servers.
    pub fn shutdown(self: *App) void {
        self.enforcePinnedMoveInvariant(.app);
        self.shutdown_requested = true;

        for (self.windows.items) |state| {
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

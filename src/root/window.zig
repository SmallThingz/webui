const std = @import("std");
const builtin = @import("builtin");

const app_mod = @import("app.zig");
const rpc_registry_mod = @import("rpc_registry.zig");
const core_runtime = @import("../ported/webui.zig");
const launch_policy = @import("launch_policy.zig");
const api_types = @import("api_types.zig");
const root_utils = @import("utils.zig");
const window_style_types = @import("window_style.zig");
const window_state = @import("window_state.zig");

const App = app_mod.App;
const RpcRegistry = rpc_registry_mod.RpcRegistry;
const BrowserLaunchOptions = core_runtime.BrowserLaunchOptions;
const AppOptions = api_types.AppOptions;
const DiagnosticCategory = api_types.DiagnosticCategory;
const DiagnosticSeverity = api_types.DiagnosticSeverity;
const EffectiveCapabilities = api_types.EffectiveCapabilities;
const Event = api_types.Event;
const EventHandler = api_types.EventHandler;
const EventKind = api_types.EventKind;
const FrontendCallResult = api_types.FrontendCallResult;
const RawHandler = api_types.RawHandler;
const RpcOptions = api_types.RpcOptions;
const RuntimeRenderState = api_types.RuntimeRenderState;
const ScriptEvalResult = api_types.ScriptEvalResult;
const ScriptOptions = api_types.ScriptOptions;
const WindowContent = api_types.WindowContent;
const WindowControlResult = api_types.WindowControlResult;
const CloseHandler = window_style_types.CloseHandler;
const WindowCapability = window_style_types.WindowCapability;
const WindowControl = window_style_types.WindowControl;
const WindowStyle = window_style_types.WindowStyle;
const FrontendRpcTask = window_state.FrontendRpcTask;
const ScriptTask = window_state.ScriptTask;
const WindowState = window_state.WindowState;

const launchPolicyContains = launch_policy.contains;
const launchPolicyOrder = launch_policy.order;
const replaceOwned = root_utils.replaceOwned;
const isLikelyUrl = root_utils.isLikelyUrl;

/// Returns whether pinned-move diagnostics are enabled in the current build mode.
pub fn pinnedMoveGuardEnabled() bool {
    return switch (builtin.mode) {
        .Debug, .ReleaseSafe => true,
        .ReleaseFast, .ReleaseSmall => false,
    };
}

/// Represents a single WebUI window and its associated runtime state.
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

    /// Shows raw HTML content in the window.
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

    /// Shows HTML, a file, or a URL depending on `content`.
    pub fn show(self: *Window, content: WindowContent) !void {
        switch (content) {
            .html => |html| try self.showHtml(html),
            .file => |path| try self.showFile(path),
            .url => |url| try self.showUrl(url),
        }
    }

    /// Shows a local file path in the window.
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

    /// Shows a URL in the window or external browser according to the launch policy.
    pub fn showUrl(self: *Window, url: []const u8) !void {
        self.app.enforcePinnedMoveInvariant(.app);
        if (!isLikelyUrl(url)) return error.InvalidUrl;

        const win_state = self.state();

        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();

        try replaceOwned(self.app.allocator, &win_state.last_url, url);
        if (win_state.last_html) |buf| {
            self.app.allocator.free(buf);
            win_state.last_html = null;
        }
        if (win_state.last_file) |buf| {
            self.app.allocator.free(buf);
            win_state.last_file = null;
        }
        win_state.shown = true;

        if (win_state.isNativeWindowActive()) {
            _ = win_state.backend.showContent(.{ .url = url }) catch {};
        }

        if (!builtin.is_test and win_state.shouldAttemptBrowserSpawnLocked(self.app.allocator, false)) {
            const launch_options = win_state.effectiveBrowserLaunchOptions(self.app.options.browser_launch);
            if (core_runtime.openInBrowser(self.app.allocator, url, win_state.current_style, launch_options)) |launch| {
                win_state.setLaunchedBrowserLaunch(self.app.allocator, launch);
            } else |err| {
                _ = try win_state.advanceAfterBrowserLaunchFailureLocked(win_state.runtime_render_state.active_surface);
                win_state.rpc_state.logf(.warn, "[webui.browser] launch failed error={s}\n", .{@errorName(err)});
                if (win_state.runtime_render_state.active_surface == .browser_window and win_state.launch_policy.app_mode_required) return err;
            }
        }

        self.emitRuntimeDiagnostics();
        self.emit(.navigation, "show-url", url);
    }

    /// Navigates to a URL and emits a navigation event.
    pub fn navigate(self: *Window, url: []const u8) !void {
        self.app.enforcePinnedMoveInvariant(.app);
        try self.showUrl(url);
        self.emit(.navigation, "navigate", url);
    }

    /// Installs an event callback for this window.
    pub fn onEvent(self: *Window, handler: EventHandler, context: ?*anyopaque) void {
        const win_state = self.state();
        win_state.event_callback = .{ .handler = handler, .context = context };
    }

    /// Returns the RPC registry bound to this window.
    pub fn rpc(self: *Window) RpcRegistry {
        return .{
            .allocator = self.app.allocator,
            .state = &self.state().rpc_state,
        };
    }

    /// Registers the public functions in `RpcStruct` as RPC handlers for this window.
    pub fn bindRpc(self: *Window, comptime RpcStruct: type, options: RpcOptions) !void {
        try self.rpc().register(RpcStruct, options);
    }

    /// Returns the generated JavaScript RPC client for this window.
    pub fn rpcClientScript(self: *Window) []const u8 {
        return self.rpc().generatedClientScript();
    }

    /// Returns the generated TypeScript declarations for this window's RPC client.
    pub fn rpcTypeDeclarations(self: *Window) []const u8 {
        return self.rpc().generatedTypeScriptDeclarations();
    }

    /// Queues JavaScript to run on the frontend without waiting for a result.
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

    /// Invokes a frontend function on one target and waits for a result.
    pub fn callFrontend(
        self: *Window,
        allocator: std.mem.Allocator,
        function_name: []const u8,
        args: anytype,
        options: ScriptOptions,
    ) !ScriptEvalResult {
        if (function_name.len == 0) return error.EmptyFrontendFunctionName;
        const args_json = try std.json.Stringify.valueAlloc(self.app.allocator, args, .{});
        defer self.app.allocator.free(args_json);

        const win_state = self.state();
        win_state.state_mutex.lock();
        const target_connection: ?usize = switch (options.target) {
            .window_default => null,
            .client_connection => |connection_id| connection_id,
        };
        const task = try win_state.queueFrontendRpcLocked(
            self.app.allocator,
            function_name,
            args_json,
            target_connection,
            true,
        );
        win_state.state_mutex.unlock();

        return self.awaitFrontendRpcTaskResult(allocator, win_state, task, options.timeout_ms);
    }

    /// Invokes a frontend function without waiting for a result.
    pub fn callFrontendFireAndForget(
        self: *Window,
        function_name: []const u8,
        args: anytype,
        options: ScriptOptions,
    ) !void {
        if (function_name.len == 0) return error.EmptyFrontendFunctionName;
        const args_json = try std.json.Stringify.valueAlloc(self.app.allocator, args, .{});
        defer self.app.allocator.free(args_json);

        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        const target_connection: ?usize = switch (options.target) {
            .window_default => null,
            .client_connection => |connection_id| connection_id,
        };
        _ = try win_state.queueFrontendRpcLocked(
            self.app.allocator,
            function_name,
            args_json,
            target_connection,
            false,
        );
    }

    /// Invokes a frontend function on a specific set of websocket connections.
    pub fn callFrontendOnConnections(
        self: *Window,
        function_name: []const u8,
        args: anytype,
        connection_ids: []const usize,
    ) !void {
        if (connection_ids.len == 0) return error.NoTargetConnections;
        if (function_name.len == 0) return error.EmptyFrontendFunctionName;

        const args_json = try std.json.Stringify.valueAlloc(self.app.allocator, args, .{});
        defer self.app.allocator.free(args_json);

        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        for (connection_ids) |connection_id| {
            _ = try win_state.queueFrontendRpcLocked(
                self.app.allocator,
                function_name,
                args_json,
                connection_id,
                false,
            );
        }
    }

    /// Invokes a frontend function on every connected websocket client.
    pub fn callFrontendAll(self: *Window, function_name: []const u8, args: anytype) !void {
        const connection_ids = try self.snapshotConnectedConnectionIds(self.app.allocator);
        defer self.app.allocator.free(connection_ids);
        try self.callFrontendOnConnections(function_name, args, connection_ids);
    }

    /// Invokes a frontend function on specific connections and waits for all results.
    pub fn callFrontendAwaitConnections(
        self: *Window,
        allocator: std.mem.Allocator,
        function_name: []const u8,
        args: anytype,
        connection_ids: []const usize,
        timeout_ms: ?u32,
    ) ![]FrontendCallResult {
        if (connection_ids.len == 0) return error.NoTargetConnections;
        if (function_name.len == 0) return error.EmptyFrontendFunctionName;

        const args_json = try std.json.Stringify.valueAlloc(self.app.allocator, args, .{});
        defer self.app.allocator.free(args_json);

        const win_state = self.state();
        const tasks = try allocator.alloc(*FrontendRpcTask, connection_ids.len);
        defer allocator.free(tasks);

        win_state.state_mutex.lock();
        var queued: usize = 0;
        errdefer {
            while (queued > 0) : (queued -= 1) {
                const task = tasks[queued - 1];
                _ = win_state.removeFrontendRpcPendingLocked(task);
                _ = win_state.removeFrontendRpcInflightLocked(task);
                task.deinit();
            }
            win_state.state_mutex.unlock();
        }
        for (connection_ids, 0..) |connection_id, idx| {
            tasks[idx] = try win_state.queueFrontendRpcLocked(
                self.app.allocator,
                function_name,
                args_json,
                connection_id,
                true,
            );
            queued += 1;
        }
        win_state.state_mutex.unlock();

        var built: usize = 0;
        const results = try allocator.alloc(FrontendCallResult, connection_ids.len);
        errdefer {
            for (results[0..built]) |item| {
                if (item.result.value) |value| allocator.free(value);
                if (item.result.error_message) |msg| allocator.free(msg);
            }
            allocator.free(results);
        }

        for (connection_ids, 0..) |connection_id, idx| {
            const result = try self.awaitFrontendRpcTaskResult(allocator, win_state, tasks[idx], timeout_ms);
            results[idx] = .{
                .connection_id = connection_id,
                .result = result,
            };
            built += 1;
        }

        return results;
    }

    /// Invokes a frontend function on all connected websocket clients and waits for all results.
    pub fn callFrontendAwaitAll(
        self: *Window,
        allocator: std.mem.Allocator,
        function_name: []const u8,
        args: anytype,
        timeout_ms: ?u32,
    ) ![]FrontendCallResult {
        const connection_ids = try self.snapshotConnectedConnectionIds(allocator);
        defer allocator.free(connection_ids);
        return self.callFrontendAwaitConnections(allocator, function_name, args, connection_ids, timeout_ms);
    }

    /// Evaluates JavaScript on the frontend and waits for a result.
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

        return self.awaitScriptTaskResult(allocator, win_state, task, options.timeout_ms);
    }

    fn awaitScriptTaskResult(
        self: *Window,
        allocator: std.mem.Allocator,
        win_state: *WindowState,
        task: *ScriptTask,
        timeout_ms: ?u32,
    ) !ScriptEvalResult {
        var timed_out = false;
        task.mutex.lock();

        if (timeout_ms) |timeout| {
            const timeout_ns: u64 = @as(u64, timeout) * std.time.ns_per_ms;
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

        _ = self;
        return result;
    }

    fn awaitFrontendRpcTaskResult(
        self: *Window,
        allocator: std.mem.Allocator,
        win_state: *WindowState,
        task: *FrontendRpcTask,
        timeout_ms: ?u32,
    ) !ScriptEvalResult {
        var timed_out = false;
        task.mutex.lock();

        if (timeout_ms) |timeout| {
            const timeout_ns: u64 = @as(u64, timeout) * std.time.ns_per_ms;
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
            win_state.markFrontendRpcTimedOutLocked(task);
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
        _ = win_state.removeFrontendRpcPendingLocked(task);
        _ = win_state.removeFrontendRpcInflightLocked(task);
        win_state.state_mutex.unlock();
        task.deinit();

        _ = self;
        return result;
    }

    fn snapshotConnectedConnectionIds(self: *Window, allocator: std.mem.Allocator) ![]usize {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        if (win_state.ws_connections.items.len == 0) return error.NoTargetConnections;
        const ids = try allocator.alloc(usize, win_state.ws_connections.items.len);
        for (win_state.ws_connections.items, 0..) |entry, idx| {
            ids[idx] = entry.connection_id;
        }
        return ids;
    }

    /// Sends raw bytes through the raw callback channel.
    pub fn sendRaw(self: *Window, bytes: []const u8) !void {
        const win_state = self.state();
        if (win_state.raw_callback.handler) |handler| {
            handler(win_state.raw_callback.context, bytes);
        }
        self.emit(.raw, "raw-send", bytes);
    }

    /// Installs a raw-byte callback for this window.
    pub fn onRaw(self: *Window, handler: RawHandler, context: ?*anyopaque) void {
        const win_state = self.state();
        win_state.raw_callback = .{ .handler = handler, .context = context };
    }

    /// Returns the local browser URL for the window's served content.
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

    /// Opens the served window content in a browser using the app's default launch options.
    pub fn openInBrowser(self: *Window) !void {
        return self.openInBrowserWithOptions(self.app.options.browser_launch);
    }

    /// Opens the served window content in a browser using explicit launch options.
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

    /// Applies native window style changes.
    pub fn applyStyle(self: *Window, style: WindowStyle) !void {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        try win_state.applyStyle(self.app.allocator, style);
    }

    /// Returns the current resolved window style.
    pub fn currentStyle(self: *Window) WindowStyle {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        return win_state.current_style;
    }

    /// Returns the last warning emitted for the window, if any.
    pub fn lastWarning(self: *Window) ?[]const u8 {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        return win_state.last_warning;
    }

    /// Returns the current runtime render state for the window.
    pub fn runtimeRenderState(self: *Window) RuntimeRenderState {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        return win_state.runtime_render_state;
    }

    /// Clears the last window warning.
    pub fn clearWarning(self: *Window) void {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        win_state.clearWarning();
    }

    /// Sends a native window control command.
    pub fn control(self: *Window, cmd: WindowControl) !WindowControlResult {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        return win_state.control(cmd);
    }

    /// Installs a close handler for the window.
    pub fn setCloseHandler(self: *Window, handler: CloseHandler, context: ?*anyopaque) void {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        win_state.close_callback = .{
            .handler = handler,
            .context = context,
        };
    }

    /// Removes any installed close handler.
    pub fn clearCloseHandler(self: *Window) void {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();
        win_state.close_callback = .{};
    }

    /// Returns the active capability set for the current transport.
    pub fn capabilities(self: *Window) []const WindowCapability {
        return self.state().capabilities();
    }

    /// Predicts capabilities and fallback behavior before rendering.
    pub fn probeCapabilities(self: *Window) EffectiveCapabilities {
        const win_state = self.state();
        win_state.state_mutex.lock();
        defer win_state.state_mutex.unlock();

        const ordered = launchPolicyOrder(win_state.launch_policy);
        var predicted_surface: api_types.LaunchSurface = .web_url;
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

        const predicted_transport: api_types.TransportMode = switch (predicted_surface) {
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

    /// Returns the backing mutable window state.
    pub fn state(self: *Window) *WindowState {
        return self.app.windows.items[self.index];
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

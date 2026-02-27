const std = @import("std");
const builtin = @import("builtin");
const webui = @import("webui");
const core_runtime = webui.runtime;
const App = webui.App;
const Service = webui.Service;
const LaunchSurface = webui.LaunchSurface;
const TransportMode = webui.TransportMode;
const FallbackReason = webui.FallbackReason;
const Size = webui.Size;
const Point = webui.Point;
const WindowControl = webui.WindowControl;
const WindowCapability = webui.WindowCapability;
const WindowStyle = webui.WindowStyle;
const Event = webui.Event;
const Diagnostic = webui.Diagnostic;
const DispatcherMode = webui.DispatcherMode;
const RpcInvokeFn = webui.RpcInvokeFn;
const RpcRegistry = webui.RpcRegistry;
const BrowserSurfaceMode = webui.BrowserSurfaceMode;
const BrowserFallbackMode = webui.BrowserFallbackMode;
const BrowserLaunchOptions = webui.BrowserLaunchOptions;
const runtime_helpers_js = webui.runtime_helpers_js;
const pinnedMoveGuardEnabled = webui.pinnedMoveGuardEnabled;

const readAllFromStream = webui.test_helpers.readAllFromStream;
const httpRoundTrip = webui.test_helpers.httpRoundTrip;
const httpRoundTripWithHeaders = webui.test_helpers.httpRoundTripWithHeaders;
const readHttpHeadersFromStream = webui.test_helpers.readHttpHeadersFromStream;

fn hasCapability(haystack: []const WindowCapability, needle: WindowCapability) bool {
    for (haystack) |cap| {
        if (cap == needle) return true;
    }
    return false;
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

test "window control route stays responsive during long running rpc" {
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
            const result = httpRoundTrip(ctx.allocator, ctx.port, "POST", "/webui/rpc", "{\"name\":\"slow\",\"args\":[]}");
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
        .bridge_options = .{ .rpc_route = "/webui/rpc" },
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
    const control_response = try httpRoundTrip(
        gpa.allocator(),
        win.state().server_port,
        "GET",
        "/webui/window/control",
        null,
    );
    defer gpa.allocator().free(control_response);
    const elapsed_ms = @as(i64, @intCast(@divTrunc(std.time.nanoTimestamp() - started_ns, std.time.ns_per_ms)));

    try std.testing.expect(std.mem.indexOf(u8, control_response, "HTTP/1.1 200 OK") != null);
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

test "window_closing lifecycle message is ignored while tracked browser pid is alive" {
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

    win.state().state_mutex.lock();
    win.state().requestLifecycleCloseFromFrontend();
    win.state().state_mutex.unlock();

    win.state().state_mutex.lock();
    const should_close = win.state().close_requested.load(.acquire);
    win.state().state_mutex.unlock();
    try std.testing.expect(!should_close);
}

test "window_closing lifecycle message uses grace delay in browser-window mode" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .browser_window, .second = null, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "LifecycleCloseBrowserWindow" });
    try win.showHtml("<html><body>lifecycle-close-browser-window</body></html>");
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
    win.state().runtime_render_state.active_surface = .browser_window;
    win.state().state_mutex.unlock();

    win.state().state_mutex.lock();
    win.state().requestLifecycleCloseFromFrontend();
    const pending_after_request = win.state().lifecycle_close_pending;
    const close_immediate = win.state().close_requested.load(.acquire);
    win.state().state_mutex.unlock();

    try std.testing.expect(pending_after_request);
    try std.testing.expect(!close_immediate);

    win.state().state_mutex.lock();
    win.state().lifecycle_close_deadline_ms = std.time.milliTimestamp() - 1;
    win.state().reconcileChildExit(gpa.allocator());
    const should_close = win.state().close_requested.load(.acquire);
    win.state().state_mutex.unlock();
    try std.testing.expect(should_close);
}

test "window_closing lifecycle pending close cancels on websocket reconnect" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .browser_window, .second = null, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "LifecycleCloseReconnectCancel" });
    try win.showHtml("<html><body>lifecycle-close-reconnect-cancel</body></html>");
    try app.run();

    win.state().state_mutex.lock();
    win.state().runtime_render_state.active_surface = .browser_window;
    win.state().requestLifecycleCloseFromFrontend();
    try std.testing.expect(win.state().lifecycle_close_pending);
    try std.testing.expect(!win.state().close_requested.load(.acquire));

    // Simulate reconnect before grace deadline. The socket stream handle is not
    // used by this test and is removed immediately to avoid shutdown cleanup.
    try win.state().ws_connections.append(.{
        .connection_id = 1,
        .stream = undefined,
    });
    win.state().reconcileChildExit(gpa.allocator());
    const pending_after_reconnect = win.state().lifecycle_close_pending;
    const close_after_reconnect = win.state().close_requested.load(.acquire);
    _ = win.state().ws_connections.orderedRemove(0);
    win.state().state_mutex.unlock();

    try std.testing.expect(!pending_after_reconnect);
    try std.testing.expect(!close_after_reconnect);
}

test "window_closing lifecycle message is ignored in web-url mode without tracked pid" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "LifecycleCloseWebUrlNoPid" });
    try win.showHtml("<html><body>lifecycle-close-web-url-no-pid</body></html>");
    try app.run();

    win.state().state_mutex.lock();
    win.state().runtime_render_state.active_surface = .web_url;
    win.state().requestLifecycleCloseFromFrontend();
    const pending = win.state().lifecycle_close_pending;
    const should_close = win.state().close_requested.load(.acquire);
    win.state().state_mutex.unlock();

    try std.testing.expect(!pending);
    try std.testing.expect(!should_close);
}

test "websocket disconnect schedules close in browser-window mode when last client is gone" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .browser_window, .second = null, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "WsDisconnectCloseBrowserWindow" });
    try win.showHtml("<html><body>ws-disconnect-close-browser-window</body></html>");
    try app.run();

    win.state().state_mutex.lock();
    win.state().runtime_render_state.active_surface = .browser_window;
    win.state().noteWsDisconnectLocked("test-disconnect");
    const pending_after_disconnect = win.state().lifecycle_close_pending;
    const close_immediate = win.state().close_requested.load(.acquire);
    win.state().state_mutex.unlock();

    try std.testing.expect(pending_after_disconnect);
    try std.testing.expect(!close_immediate);

    win.state().state_mutex.lock();
    win.state().lifecycle_close_deadline_ms = std.time.milliTimestamp() - 1;
    win.state().reconcileChildExit(gpa.allocator());
    const should_close = win.state().close_requested.load(.acquire);
    win.state().state_mutex.unlock();
    try std.testing.expect(should_close);
}

test "websocket disconnect does not close backend in web-url mode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try App.init(gpa.allocator(), .{
        .launch_policy = .{ .first = .web_url, .second = null, .third = null },
    });
    defer app.deinit();

    var win = try app.newWindow(.{ .title = "WsDisconnectNoCloseWebUrl" });
    try win.showHtml("<html><body>ws-disconnect-no-close-web-url</body></html>");
    try app.run();

    win.state().state_mutex.lock();
    win.state().runtime_render_state.active_surface = .web_url;
    win.state().noteWsDisconnectLocked("test-disconnect");
    const pending = win.state().lifecycle_close_pending;
    const should_close = win.state().close_requested.load(.acquire);
    win.state().state_mutex.unlock();

    try std.testing.expect(!pending);
    try std.testing.expect(!should_close);
}

test "non-linked tracked browser pid death detaches without close in web mode" {
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
    var detached = false;
    var attempts: usize = 0;
    while (attempts < 120) : (attempts += 1) {
        win.state().state_mutex.lock();
        win.state().reconcileChildExit(gpa.allocator());
        const requested = win.state().close_requested.load(.acquire);
        const tracked_pid = win.state().launched_browser_pid;
        win.state().state_mutex.unlock();
        if (requested) {
            closed = true;
            break;
        }
        if (tracked_pid == null) {
            detached = true;
            break;
        }
        std.Thread.sleep(5 * std.time.ns_per_ms);
    }

    try std.testing.expect(!closed);
    try std.testing.expect(detached);
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
    try std.testing.expect(hasCapability(caps_default, .native_frameless));

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
    try win.bindRpc(DemoRpc, .{});

    const script = win.rpcClientScript();
    try std.testing.expect(std.mem.indexOf(u8, script, "sum: async (arg0, arg1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "__webuiRpcEndpoint = \"/webui/rpc\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "globalThis.__webuiWindowControl") != null);

    const written_path = try std.fmt.allocPrint(gpa.allocator(), ".zig-cache/test_bridge_written_{d}.js", .{std.time.nanoTimestamp()});
    defer gpa.allocator().free(written_path);
    defer std.fs.cwd().deleteFile(written_path) catch {};
    try win.rpc().writeGeneratedClientScript(written_path);
    const written_script = try std.fs.cwd().readFileAlloc(gpa.allocator(), written_path, 1024 * 1024);
    defer gpa.allocator().free(written_script);
    try std.testing.expect(std.mem.indexOf(u8, written_script, "async function __webuiInvoke(endpoint, name, args)") != null);

    const dts = win.rpcTypeDeclarations();
    try std.testing.expect(std.mem.indexOf(u8, dts, "sum(...args: unknown[]): Promise<unknown>;") != null);
    try std.testing.expect(std.mem.indexOf(u8, dts, "ping(...args: unknown[]): Promise<unknown>;") != null);

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

    const script_rt = service.rpcClientScript();
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
        .rpc_route = "/webui/rpc",
    });
    const dts = RpcRegistry.generatedTypeScriptDeclarationsComptime(DemoRpc, .{
        .namespace = "demo",
        .rpc_route = "/webui/rpc",
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

test "script response websocket message completes queued eval task" {
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

    const completion_msg = try std.fmt.allocPrint(
        gpa.allocator(),
        "{{\"type\":\"script_response\",\"id\":{d},\"js_error\":false,\"value\":42}}",
        .{task.id},
    );
    defer gpa.allocator().free(completion_msg);
    try state.handleWebSocketClientMessage(1, completion_msg);

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

test "rpc route returns value directly with threaded default dispatcher" {
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

    var win = try app.newWindow(.{ .title = "RpcThreadedDefault" });
    try win.bindRpc(DemoRpc, .{
        .bridge_options = .{ .rpc_route = "/webui/rpc" },
    });
    try win.showHtml("<html><body>rpc-threaded-default</body></html>");
    try app.run();

    const response = try httpRoundTrip(
        gpa.allocator(),
        win.state().server_port,
        "POST",
        "/webui/rpc",
        "{\"name\":\"delayedAdd\",\"args\":[20,22,10]}",
    );
    defer gpa.allocator().free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"value\":42") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"job_id\"") == null);
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
        .bridge_options = .{ .rpc_route = "/webui/rpc" },
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

                const response = httpRoundTrip(allocator, ctx.port, "POST", "/webui/rpc", payload) catch {
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

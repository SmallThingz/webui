const std = @import("std");

const net_io = @import("net_io.zig");
const api_types = @import("api_types.zig");
const window_style_types = @import("window_style.zig");

pub fn handleConnection(
    state: anytype,
    allocator: std.mem.Allocator,
    conn: anytype,
    default_client_token: []const u8,
) !bool {
    const request = try net_io.readHttpRequestAny(allocator, conn);
    defer allocator.free(request.raw);

    const path_only = net_io.pathWithoutQuery(request.path);
    if (try handleWebSocketUpgradeRoute(state, conn, request, path_only, default_client_token)) return true;

    // Keep lifecycle/script/job control on WS only. Do not re-introduce HTTP fallback
    // routes for these flows, because they cause duplicate semantics and polling paths.
    if (try handleBridgeScriptRoute(state, allocator, conn, request.method, path_only)) return false;
    if (try handleRpcRoute(state, allocator, conn, request.method, path_only, request.headers, request.body, default_client_token)) return false;
    if (try handleWindowControlRoute(state, allocator, conn, request.method, path_only, request.body)) return false;
    if (try handleWindowStyleRoute(state, allocator, conn, request.method, path_only, request.body)) return false;
    if (try handleWindowContentRoute(state, allocator, conn, request.method, path_only)) return false;

    try net_io.writeHttpResponseAny(conn, 404, "text/plain; charset=utf-8", "not found");
    return false;
}

fn closeOwnedTransport(state: anytype, transport: anytype) void {
    switch (@TypeOf(transport)) {
        std.net.Stream => transport.close(),
        else => {
            transport.close();
            state.allocator.destroy(transport);
        },
    }
}

fn wsConnectionThreadMain(state: anytype, transport: anytype, connection_id: usize) void {
    defer {
        state.state_mutex.lock();
        state.unregisterWsConnectionLocked(connection_id);
        state.noteWsDisconnectLocked("websocket-disconnected");
        state.state_mutex.unlock();
        closeOwnedTransport(state, transport);
        state.emitDiagnostic("websocket.disconnected", .websocket, .info, "WebSocket client disconnected");

        state.rpc_state.logf(.info, "[webui.ws] disconnected connection_id={d}\n", .{connection_id});
    }

    while (!state.server_stop.load(.acquire)) {
        const frame = net_io.readWsInboundFrameAllocAny(state.allocator, transport, 8 * 1024 * 1024) catch |err| {
            if (err != error.Closed) {
                state.rpc_state.logf(.warn, "[webui.ws] read failed connection_id={d} err={s}\n", .{ connection_id, @errorName(err) });
            }
            if (err != error.Closed) {
                state.emitDiagnostic("websocket.read_error", .websocket, .warn, @errorName(err));
            }
            return;
        };
        defer state.allocator.free(frame.payload);

        switch (frame.kind) {
            .text, .binary => {
                state.handleWebSocketClientMessage(connection_id, frame.payload) catch |err| {
                    state.rpc_state.logf(.warn, "[webui.ws] message handling failed connection_id={d} err={s}\n", .{ connection_id, @errorName(err) });
                };
            },
            .ping => {
                net_io.writeWsFrameAny(transport, .pong, frame.payload) catch return;
            },
            .pong => {},
            .close => {
                net_io.writeWsFrameAny(transport, .close, frame.payload) catch {};
                return;
            },
        }
    }
}

fn handleWebSocketUpgradeRoute(
    state: anytype,
    conn: anytype,
    request: net_io.HttpRequest,
    path_only: []const u8,
    default_client_token: []const u8,
) !bool {
    if (!std.mem.eql(u8, request.method, "GET")) return false;
    if (!std.mem.eql(u8, path_only, "/webui/ws")) return false;

    const upgrade = net_io.httpHeaderValue(request.headers, "Upgrade") orelse {
        try net_io.writeHttpResponseAny(conn, 400, "text/plain; charset=utf-8", "missing Upgrade header");
        return false;
    };
    if (!std.ascii.eqlIgnoreCase(upgrade, "websocket")) {
        try net_io.writeHttpResponseAny(conn, 400, "text/plain; charset=utf-8", "invalid Upgrade header");
        return false;
    }

    const connection = net_io.httpHeaderValue(request.headers, "Connection") orelse {
        try net_io.writeHttpResponseAny(conn, 400, "text/plain; charset=utf-8", "missing Connection header");
        return false;
    };
    if (!net_io.containsTokenIgnoreCase(connection, "upgrade")) {
        try net_io.writeHttpResponseAny(conn, 400, "text/plain; charset=utf-8", "invalid Connection header");
        return false;
    }

    const version = net_io.httpHeaderValue(request.headers, "Sec-WebSocket-Version") orelse {
        try net_io.writeHttpResponseAny(conn, 400, "text/plain; charset=utf-8", "missing Sec-WebSocket-Version header");
        return false;
    };
    if (!std.mem.eql(u8, std.mem.trim(u8, version, " \t"), "13")) {
        try net_io.writeHttpResponseAny(conn, 400, "text/plain; charset=utf-8", "unsupported websocket version");
        return false;
    }

    const sec_key = net_io.httpHeaderValue(request.headers, "Sec-WebSocket-Key") orelse {
        try net_io.writeHttpResponseAny(conn, 400, "text/plain; charset=utf-8", "missing Sec-WebSocket-Key header");
        return false;
    };

    try net_io.writeWebSocketHandshakeResponseAny(conn, sec_key);

    const token = net_io.wsClientTokenFromUrl(request.path, default_client_token);
    var connection_id: usize = 0;
    state.state_mutex.lock();
    {
        const client_ref = try state.findOrCreateClientSessionLocked(token);
        connection_id = client_ref.connection_id;
        try state.registerWsConnectionLocked(connection_id, conn);
        try state.dispatchPendingScriptTasksLocked();
    }
    state.state_mutex.unlock();

    state.rpc_state.logf(.info, "[webui.ws] connected connection_id={d}\n", .{connection_id});
    state.emitDiagnostic("websocket.connected", .websocket, .info, "WebSocket client connected");

    const thread = try std.Thread.spawn(.{}, wsConnectionThreadMain, .{ state, conn, connection_id });
    thread.detach();
    return true;
}

fn handleBridgeScriptRoute(
    state: anytype,
    allocator: std.mem.Allocator,
    conn: anytype,
    method: []const u8,
    path_only: []const u8,
) !bool {
    _ = allocator;
    if (!std.mem.eql(u8, method, "GET")) return false;
    const script_route = state.rpc_state.bridge_options.script_route;
    if (!std.mem.eql(u8, path_only, script_route)) return false;

    // Bridge JS is pre-generated at compile time and stored in rpc_state.
    try net_io.writeHttpResponseAny(conn, 200, "application/javascript; charset=utf-8", state.rpc_state.generated_script);
    return true;
}

fn handleRpcRoute(
    state: anytype,
    allocator: std.mem.Allocator,
    conn: anytype,
    method: []const u8,
    path_only: []const u8,
    headers: []const u8,
    body: []const u8,
    default_client_token: []const u8,
) !bool {
    if (!std.mem.eql(u8, method, "POST")) return false;
    if (!std.mem.eql(u8, path_only, state.rpc_state.bridge_options.rpc_route)) return false;

    state.rpc_state.logf(.debug, "[webui.rpc] raw body={s}\n", .{body});

    const client_token = net_io.httpHeaderValue(headers, "x-webui-client-id") orelse default_client_token;
    state.state_mutex.lock();
    const client_ref = state.findOrCreateClientSessionLocked(client_token) catch null;
    state.state_mutex.unlock();

    state.rpc_state.invoke_mutex.lock();
    const payload = state.rpc_state.invokeFromJsonPayload(allocator, body) catch |err| {
        state.rpc_state.invoke_mutex.unlock();
        state.emitDiagnostic("rpc.dispatch.error", .rpc, .warn, @errorName(err));
        const status = rpcStatusForError(err);
        state.rpc_state.logf(.warn, "[webui.rpc] error={s} status={d}\n", .{ @errorName(err), status });
        try net_io.writeHttpResponseAny(conn, status, "application/json; charset=utf-8", "");
        return true;
    };
    state.rpc_state.invoke_mutex.unlock();
    defer allocator.free(payload);

    state.rpc_state.logf(.debug, "[webui.rpc] http response={s}\n", .{payload});

    if (state.event_callback.handler) |handler| {
        const event = api_types.Event{
            .window_id = state.id,
            .kind = .rpc,
            .name = "rpc",
            .payload = "rpc-dispatch",
            .client_id = if (client_ref) |ref| ref.client_id else null,
            .connection_id = if (client_ref) |ref| ref.connection_id else null,
        };
        handler(state.event_callback.context, &event);
    }

    try net_io.writeHttpResponseAny(conn, 200, "application/json; charset=utf-8", payload);
    return true;
}

fn rpcStatusForError(err: anyerror) u16 {
    return switch (err) {
        error.InvalidRpcPayload => 400,
        error.UnknownRpcFunction => 404,
        error.InvalidRpcArgCount, error.InvalidRpcArgType => 422,
        else => 500,
    };
}

fn handleWindowControlRoute(
    state: anytype,
    allocator: std.mem.Allocator,
    conn: anytype,
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
        try net_io.writeHttpResponseAny(conn, 200, "application/json; charset=utf-8", payload);
        return true;
    }

    if (!std.mem.eql(u8, method, "POST")) return false;

    const Req = struct {
        cmd: []const u8,
    };
    var parsed = std.json.parseFromSlice(Req, allocator, body, .{ .ignore_unknown_fields = true }) catch {
        try net_io.writeHttpResponseAny(conn, 400, "application/json; charset=utf-8", "");
        return true;
    };
    defer parsed.deinit();

    const cmd = std.meta.stringToEnum(window_style_types.WindowControl, parsed.value.cmd) orelse {
        try net_io.writeHttpResponseAny(conn, 422, "application/json; charset=utf-8", "");
        return true;
    };

    state.rpc_state.logf(.debug, "[webui.window] control cmd={s}\n", .{@tagName(cmd)});

    state.state_mutex.lock();
    const result = state.control(cmd) catch |err| {
        state.state_mutex.unlock();
        state.rpc_state.logf(.warn, "[webui.window] control error={s}\n", .{@errorName(err)});
        const status: u16 = switch (err) {
            error.UnsupportedWindowControl,
            error.CloseDenied,
            => 422,
            else => 500,
        };
        try net_io.writeHttpResponseAny(conn, status, "application/json; charset=utf-8", "");
        return true;
    };
    state.state_mutex.unlock();

    state.rpc_state.logf(.debug, "[webui.window] control result success={any} emulation={s} closed={any} warning={s}\n", .{
        result.success,
        result.emulation orelse "",
        result.closed,
        result.warning orelse "",
    });

    const payload = try std.json.Stringify.valueAlloc(allocator, .{
        .success = result.success,
        .emulation = result.emulation,
        .closed = result.closed,
        .warning = result.warning,
    }, .{});
    defer allocator.free(payload);
    try net_io.writeHttpResponseAny(conn, 200, "application/json; charset=utf-8", payload);
    return true;
}

fn handleWindowStyleRoute(
    state: anytype,
    allocator: std.mem.Allocator,
    conn: anytype,
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
        try net_io.writeHttpResponseAny(conn, 200, "application/json; charset=utf-8", payload);
        return true;
    }

    if (!std.mem.eql(u8, method, "POST")) return false;

    var parsed = std.json.parseFromSlice(window_style_types.WindowStyle, allocator, body, .{ .ignore_unknown_fields = true }) catch {
        try net_io.writeHttpResponseAny(conn, 400, "application/json; charset=utf-8", "");
        return true;
    };
    defer parsed.deinit();

    state.state_mutex.lock();
    state.applyStyle(allocator, parsed.value) catch |err| {
        state.state_mutex.unlock();
        state.rpc_state.logf(.warn, "[webui.window] style error={s}\n", .{@errorName(err)});
        const status: u16 = switch (err) {
            error.UnsupportedWindowStyle => 422,
            else => 500,
        };
        try net_io.writeHttpResponseAny(conn, status, "application/json; charset=utf-8", "");
        return true;
    };
    const style = state.current_style;
    state.state_mutex.unlock();

    state.rpc_state.logf(.debug, "[webui.window] style applied frameless={any} transparent={any} corner_radius={any}\n", .{
        style.frameless,
        style.transparent,
        style.corner_radius,
    });

    const payload = try std.json.Stringify.valueAlloc(allocator, style, .{});
    defer allocator.free(payload);
    try net_io.writeHttpResponseAny(conn, 200, "application/json; charset=utf-8", payload);
    return true;
}

fn isHttpUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "http://") or std.mem.startsWith(u8, url, "https://");
}

fn handleWindowContentRoute(
    state: anytype,
    allocator: std.mem.Allocator,
    conn: anytype,
    method: []const u8,
    path_only: []const u8,
) !bool {
    if (!std.mem.eql(u8, method, "GET")) return false;
    if (!std.mem.eql(u8, path_only, "/") and !std.mem.eql(u8, path_only, "/index.html")) return false;

    state.state_mutex.lock();
    defer state.state_mutex.unlock();

    if (state.last_html) |html| {
        try net_io.writeHttpResponseAny(conn, 200, "text/html; charset=utf-8", html);
        return true;
    }

    if (state.last_file) |file_path| {
        const data = std.fs.cwd().readFileAlloc(allocator, file_path, 8 * 1024 * 1024) catch {
            try net_io.writeHttpResponseAny(conn, 500, "text/plain; charset=utf-8", "failed to read file");
            return true;
        };
        defer allocator.free(data);
        try net_io.writeHttpResponseAny(conn, 200, net_io.contentTypeForPath(file_path), data);
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
            try net_io.writeHttpResponseAny(conn, 200, "text/html; charset=utf-8", redirect);
            return true;
        }
    }

    try net_io.writeHttpResponseAny(conn, 404, "text/plain; charset=utf-8", "no content");
    return true;
}

const std = @import("std");
const builtin = @import("builtin");
const websocket = @import("websocket");

pub const HttpRequest = struct {
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

pub const WsInboundFrame = struct {
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

pub fn readWsInboundFrameAlloc(allocator: std.mem.Allocator, stream: std.net.Stream, max_payload_size: usize) !WsInboundFrame {
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

pub fn containsTokenIgnoreCase(value: []const u8, token: []const u8) bool {
    var it = std.mem.splitScalar(u8, value, ',');
    while (it.next()) |part| {
        const normalized = std.mem.trim(u8, part, " \t");
        if (std.ascii.eqlIgnoreCase(normalized, token)) return true;
    }
    return false;
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

pub fn writeWebSocketHandshakeResponse(stream: std.net.Stream, sec_key: []const u8) !void {
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

    try writeSocketAll(stream.handle, response);
}

pub fn pathWithoutQuery(path: []const u8) []const u8 {
    return if (std.mem.indexOfScalar(u8, path, '?')) |q| path[0..q] else path;
}

pub fn wsClientTokenFromUrl(url: []const u8, default_client_token: []const u8) []const u8 {
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

pub fn httpHeaderValue(headers: []const u8, name: []const u8) ?[]const u8 {
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

pub fn readHttpRequest(allocator: std.mem.Allocator, stream: std.net.Stream) !HttpRequest {
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

pub fn writeHttpResponse(stream: std.net.Stream, status: u16, content_type: []const u8, body: []const u8) !void {
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

    try writeSocketAll(stream.handle, header);
    try writeSocketAll(stream.handle, body);
}

pub fn contentTypeForPath(path: []const u8) []const u8 {
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

pub fn readAllFromStream(allocator: std.mem.Allocator, stream: std.net.Stream, max_bytes: usize) ![]u8 {
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

pub fn httpRoundTrip(
    allocator: std.mem.Allocator,
    port: u16,
    method: []const u8,
    path: []const u8,
    body: ?[]const u8,
) ![]u8 {
    return httpRoundTripWithHeaders(allocator, port, method, path, body, &.{});
}

pub fn httpRoundTripWithHeaders(
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

pub fn readHttpHeadersFromStream(allocator: std.mem.Allocator, stream: std.net.Stream, max_bytes: usize) ![]u8 {
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

pub fn httpResponseBody(response: []const u8) []const u8 {
    const header_end = std.mem.indexOf(u8, response, "\r\n\r\n") orelse return "";
    return response[header_end + 4 ..];
}

const std = @import("std");
const tls = @import("tls");

pub const Connection = struct {
    stream: std.net.Stream,
    read_buffer: [tls.input_buffer_len]u8 = undefined,
    write_buffer: [tls.output_buffer_len]u8 = undefined,
    reader: std.net.Stream.Reader = undefined,
    writer: std.net.Stream.Writer = undefined,
    tls_conn: tls.Connection = undefined,

    pub fn initServer(
        allocator: std.mem.Allocator,
        stream: std.net.Stream,
        cert_pem: []const u8,
        key_pem: []const u8,
    ) !Connection {
        var conn: Connection = .{
            .stream = stream,
        };
        conn.reader = conn.stream.reader(&conn.read_buffer);
        conn.writer = conn.stream.writer(&conn.write_buffer);

        const cert_path, const key_path = try writeTempPemFiles(allocator, cert_pem, key_pem);
        defer {
            std.fs.deleteFileAbsolute(cert_path) catch {};
            std.fs.deleteFileAbsolute(key_path) catch {};
            allocator.free(cert_path);
            allocator.free(key_path);
        }

        var auth = try tls.config.CertKeyPair.fromFilePathAbsolute(allocator, cert_path, key_path);
        defer auth.deinit(allocator);

        conn.tls_conn = try tls.server(conn.reader.interface(), &conn.writer.interface, .{
            .auth = &auth,
        });
        return conn;
    }

    pub fn read(self: *Connection, buffer: []u8) !usize {
        return self.tls_conn.read(buffer);
    }

    pub fn writeAll(self: *Connection, bytes: []const u8) !void {
        try self.tls_conn.writeAll(bytes);
    }

    pub fn close(self: *Connection) void {
        self.tls_conn.close() catch {};
        self.stream.close();
    }
};

pub fn peekFirstByte(stream: std.net.Stream) !?u8 {
    var byte: [1]u8 = undefined;
    const n = std.posix.recv(stream.handle, &byte, std.posix.MSG.PEEK) catch |err| switch (err) {
        error.WouldBlock,
        error.ConnectionResetByPeer,
        error.ConnectionTimedOut,
        error.SocketNotConnected,
        => return null,
        else => return err,
    };
    if (n == 0) return null;
    return byte[0];
}

pub fn looksLikeTlsClientHello(first_byte: u8) bool {
    // TLS record content-type handshake.
    return first_byte == 0x16;
}

fn writeTempPemFiles(
    allocator: std.mem.Allocator,
    cert_pem: []const u8,
    key_pem: []const u8,
) !struct { []u8, []u8 } {
    const tmp_base = if (@import("builtin").os.tag == .windows)
        std.process.getEnvVarOwned(allocator, "TEMP") catch
            std.process.getEnvVarOwned(allocator, "TMP") catch
            try allocator.dupe(u8, "C:\\Temp")
    else
        std.process.getEnvVarOwned(allocator, "TMPDIR") catch try allocator.dupe(u8, "/tmp");
    defer allocator.free(tmp_base);

    const stamp: u64 = @intCast(@abs(std.time.nanoTimestamp()));
    const cert_path = try std.fmt.allocPrint(
        allocator,
        "{s}{c}webui-tls-cert-{d}.pem",
        .{ std.mem.trimRight(u8, tmp_base, "/\\"), std.fs.path.sep, stamp },
    );
    errdefer allocator.free(cert_path);
    const key_path = try std.fmt.allocPrint(
        allocator,
        "{s}{c}webui-tls-key-{d}.pem",
        .{ std.mem.trimRight(u8, tmp_base, "/\\"), std.fs.path.sep, stamp },
    );
    errdefer allocator.free(key_path);

    const cert_file = try std.fs.createFileAbsolute(cert_path, .{ .truncate = true });
    defer cert_file.close();
    try cert_file.writeAll(cert_pem);
    errdefer std.fs.deleteFileAbsolute(cert_path) catch {};
    const key_file = try std.fs.createFileAbsolute(key_path, .{ .truncate = true });
    defer key_file.close();
    try key_file.writeAll(key_pem);
    errdefer std.fs.deleteFileAbsolute(key_path) catch {};

    return .{ cert_path, key_path };
}

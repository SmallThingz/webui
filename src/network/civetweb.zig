const std = @import("std");

pub const types = struct {
    pub const HttpMethod = enum {
        get,
        post,
        put,
        patch,
        delete,
        options,
        head,
    };

    pub const Request = struct {
        method: HttpMethod,
        path: []const u8,
        body: []const u8,
        headers: std.StringHashMap([]const u8),

        pub fn init(allocator: std.mem.Allocator) Request {
            return .{
                .method = .get,
                .path = "/",
                .body = "",
                .headers = std.StringHashMap([]const u8).init(allocator),
            };
        }

        pub fn deinit(self: *Request) void {
            self.headers.deinit();
        }
    };

    pub const Response = struct {
        status: u16 = 200,
        body: []const u8 = "",
        content_type: []const u8 = "text/plain; charset=utf-8",
    };
};

pub const handle_form = struct {
    pub fn parseFormUrlEncoded(
        allocator: std.mem.Allocator,
        payload: []const u8,
    ) !std.StringHashMap([]const u8) {
        var out = std.StringHashMap([]const u8).init(allocator);
        errdefer out.deinit();

        var it = std.mem.splitScalar(u8, payload, '&');
        while (it.next()) |pair| {
            if (pair.len == 0) continue;
            var kv = std.mem.splitScalar(u8, pair, '=');
            const key = kv.next() orelse continue;
            const value = kv.next() orelse "";
            try out.put(try allocator.dupe(u8, key), try allocator.dupe(u8, value));
        }

        return out;
    }
};

pub const matcher = struct {
    pub fn startsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
        if (needle.len > haystack.len) return false;
        return std.ascii.eqlIgnoreCase(haystack[0..needle.len], needle);
    }
};

pub const md5 = struct {
    pub fn digestHex(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
        var hash: [16]u8 = undefined;
        std.crypto.hash.Md5.hash(input, &hash, .{});
        return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    }
};

pub const response = struct {
    pub fn text(status: u16, body: []const u8) types.Response {
        return .{
            .status = status,
            .body = body,
            .content_type = "text/plain; charset=utf-8",
        };
    }

    pub fn json(status: u16, body: []const u8) types.Response {
        return .{
            .status = status,
            .body = body,
            .content_type = "application/json; charset=utf-8",
        };
    }
};

pub const sha1 = struct {
    pub fn digestHex(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
        var hash: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(input, &hash, .{});
        return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    }
};

pub const sort = struct {
    pub fn sortStrings(items: [][]const u8) void {
        std.mem.sort([]const u8, items, {}, lessThan);
    }

    fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
        return std.mem.order(u8, lhs, rhs) == .lt;
    }
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    port: u16,

    pub fn init(allocator: std.mem.Allocator, port: u16) Server {
        return .{ .allocator = allocator, .port = port };
    }

    pub fn deinit(self: *Server) void {
        _ = self;
    }

    pub fn start(self: *Server) !void {
        if (self.port == 0) return error.InvalidPort;
    }
};

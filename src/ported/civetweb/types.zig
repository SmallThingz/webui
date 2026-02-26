const std = @import("std");

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

const types = @import("types.zig");

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

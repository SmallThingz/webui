const std = @import("std");
const api_types = @import("api_types.zig");

pub fn bridgeOptionsEqual(lhs: api_types.BridgeOptions, rhs: api_types.BridgeOptions) bool {
    return std.mem.eql(u8, lhs.namespace, rhs.namespace) and
        std.mem.eql(u8, lhs.script_route, rhs.script_route) and
        std.mem.eql(u8, lhs.rpc_route, rhs.rpc_route);
}

pub fn replaceOwned(allocator: std.mem.Allocator, target: *?[]u8, value: []const u8) !void {
    if (target.*) |buf| {
        allocator.free(buf);
    }
    target.* = try allocator.dupe(u8, value);
}

pub fn isHttpUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "http://") or std.mem.startsWith(u8, url, "https://");
}

pub fn isLikelyUrl(url: []const u8) bool {
    return isHttpUrl(url) or std.mem.startsWith(u8, url, "file://");
}

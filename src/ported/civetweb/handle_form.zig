const std = @import("std");

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

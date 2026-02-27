const std = @import("std");
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

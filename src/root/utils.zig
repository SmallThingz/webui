const std = @import("std");

/// Replaces an owned optional byte slice with a freshly duplicated value.
pub fn replaceOwned(allocator: std.mem.Allocator, target: *?[]u8, value: []const u8) !void {
    if (target.*) |buf| {
        allocator.free(buf);
    }
    target.* = try allocator.dupe(u8, value);
}

/// Returns whether `url` is an `http://` or `https://` URL.
pub fn isHttpUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "http://") or std.mem.startsWith(u8, url, "https://");
}

/// Returns whether `url` looks like a supported URL input.
pub fn isLikelyUrl(url: []const u8) bool {
    return isHttpUrl(url) or std.mem.startsWith(u8, url, "file://");
}

const std = @import("std");

pub fn digestHex(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var hash: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(input, &hash, .{});
    return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&hash)});
}

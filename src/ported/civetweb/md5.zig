const std = @import("std");

pub fn digestHex(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var hash: [16]u8 = undefined;
    std.crypto.hash.Md5.hash(input, &hash, .{});
    return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&hash)});
}

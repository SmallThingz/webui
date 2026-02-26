const std = @import("std");

pub fn sortStrings(items: [][]const u8) void {
    std.mem.sort([]const u8, items, {}, lessThan);
}

fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

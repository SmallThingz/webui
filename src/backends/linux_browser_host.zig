const std = @import("std");

pub const LaunchResult = struct {
    pid: i64,
    is_child_process: bool = true,
};

pub fn launchTracked(
    allocator: std.mem.Allocator,
    browser_path: []const u8,
    args: []const []const u8,
) !?LaunchResult {
    var argv = std.array_list.Managed([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append(browser_path);
    if (args.len > 0) try argv.appendSlice(args);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    child.pgid = 0;

    child.spawn() catch return null;
    return .{
        .pid = @as(i64, @intCast(child.id)),
        .is_child_process = true,
    };
}

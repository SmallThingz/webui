const std = @import("std");
const window_style_types = @import("../root/window_style.zig");

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

pub fn openUrlInExistingInstall(
    allocator: std.mem.Allocator,
    browser_path: []const u8,
    url: []const u8,
) bool {
    const launched = launchTracked(allocator, browser_path, &.{url}) catch null;
    return launched != null;
}

pub fn terminateProcess(_: std.mem.Allocator, pid_value: i64) void {
    if (pid_value <= 0) return;
    const pid: std.posix.pid_t = @intCast(pid_value);
    std.posix.kill(pid, std.posix.SIG.TERM) catch {};
    std.posix.kill(pid, std.posix.SIG.KILL) catch {};
}

pub fn isProcessAlive(_: std.mem.Allocator, pid_value: i64) bool {
    if (pid_value <= 0) return false;

    const pid: std.posix.pid_t = @intCast(pid_value);
    std.posix.kill(pid, 0) catch |err| {
        return switch (err) {
            error.PermissionDenied => true,
            else => false,
        };
    };

    return !isZombieProcessLinux(pid);
}

pub fn controlWindow(allocator: std.mem.Allocator, pid: i64, cmd: window_style_types.WindowControl) bool {
    if (pid <= 0) return false;

    if (cmd == .close) {
        terminateProcess(allocator, pid);
        return true;
    }

    const win_id = firstLinuxWindowIdForPid(allocator, pid) orelse return false;
    const win_id_hex = std.fmt.allocPrint(allocator, "0x{x}", .{win_id}) catch return false;
    defer allocator.free(win_id_hex);

    return switch (cmd) {
        .minimize => (runCommandNoCapture(allocator, &.{ "xdotool", "windowminimize", win_id_hex }) catch false) or
            (runCommandNoCapture(allocator, &.{ "wmctrl", "-ir", win_id_hex, "-b", "add,hidden" }) catch false),
        .maximize => runCommandNoCapture(allocator, &.{ "wmctrl", "-ir", win_id_hex, "-b", "add,maximized_vert,maximized_horz" }) catch false,
        .restore => runCommandNoCapture(allocator, &.{ "wmctrl", "-ir", win_id_hex, "-b", "remove,maximized_vert,maximized_horz" }) catch false,
        .hide => runCommandNoCapture(allocator, &.{ "wmctrl", "-ir", win_id_hex, "-b", "add,hidden" }) catch false,
        .show => (runCommandNoCapture(allocator, &.{ "wmctrl", "-ia", win_id_hex }) catch false) or
            (runCommandNoCapture(allocator, &.{ "wmctrl", "-ir", win_id_hex, "-b", "remove,hidden" }) catch false),
        .close => unreachable,
    };
}

fn runCommandCaptureStdout(allocator: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();
    defer {
        _ = child.wait() catch {};
    }

    const out = if (child.stdout) |*stdout_file|
        try stdout_file.readToEndAlloc(allocator, 32 * 1024)
    else
        try allocator.dupe(u8, "");
    return out;
}

fn runCommandNoCapture(allocator: std.mem.Allocator, argv: []const []const u8) !bool {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    const term = child.spawnAndWait() catch return false;
    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

fn firstLinuxWindowIdForPid(allocator: std.mem.Allocator, pid: i64) ?u64 {
    const pid_txt = std.fmt.allocPrint(allocator, "{d}", .{pid}) catch return null;
    defer allocator.free(pid_txt);

    const output = runCommandCaptureStdout(allocator, &.{ "xdotool", "search", "--pid", pid_txt }) catch return null;
    defer allocator.free(output);

    var it = std.mem.splitScalar(u8, output, '\n');
    while (it.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0) continue;
        if (std.fmt.parseInt(u64, line, 10)) |id| return id else |_| {}
    }
    return null;
}

fn isZombieProcessLinux(pid: std.posix.pid_t) bool {
    var path_buf: [64]u8 = undefined;
    const stat_path = std.fmt.bufPrint(&path_buf, "/proc/{d}/stat", .{pid}) catch return false;

    var stat_file = std.fs.openFileAbsolute(stat_path, .{}) catch return false;
    defer stat_file.close();

    var stat_buf: [1024]u8 = undefined;
    const stat_len = stat_file.readAll(&stat_buf) catch return false;
    const stat = stat_buf[0..stat_len];

    const close_paren = std.mem.lastIndexOfScalar(u8, stat, ')') orelse return false;
    if (close_paren + 2 >= stat.len) return false;
    return stat[close_paren + 2] == 'Z';
}

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
    return .{ .pid = @as(i64, @intCast(child.id)), .is_child_process = true };
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
    return true;
}

pub fn controlWindow(allocator: std.mem.Allocator, pid: i64, cmd: window_style_types.WindowControl) bool {
    if (pid <= 0) return false;

    if (cmd == .close) {
        terminateProcess(allocator, pid);
        return true;
    }

    const script = buildAppleScriptForControl(allocator, pid, cmd) catch return false;
    defer allocator.free(script);

    if (runCommandNoCapture(allocator, &.{ "osascript", "-e", script }) catch false) return true;
    if (cmd == .maximize) {
        const alt = buildAppleScriptForZoomFallback(allocator, pid) catch return false;
        defer allocator.free(alt);
        return runCommandNoCapture(allocator, &.{ "osascript", "-e", alt }) catch false;
    }
    return false;
}

fn buildAppleScriptForControl(
    allocator: std.mem.Allocator,
    pid: i64,
    cmd: window_style_types.WindowControl,
) ![]u8 {
    return switch (cmd) {
        .hide => std.fmt.allocPrint(
            allocator,
            "tell application \"System Events\" to tell (first process whose unix id is {d}) to set visible to false",
            .{pid},
        ),
        .show => std.fmt.allocPrint(
            allocator,
            "tell application \"System Events\" to tell (first process whose unix id is {d}) to set visible to true",
            .{pid},
        ),
        .minimize => std.fmt.allocPrint(
            allocator,
            "tell application \"System Events\" to tell (first window of (first process whose unix id is {d})) to set value of attribute \"AXMinimized\" to true",
            .{pid},
        ),
        .restore => std.fmt.allocPrint(
            allocator,
            "tell application \"System Events\" to tell (first window of (first process whose unix id is {d})) to set value of attribute \"AXMinimized\" to false",
            .{pid},
        ),
        .maximize => std.fmt.allocPrint(
            allocator,
            "tell application \"System Events\" to tell (first window of (first process whose unix id is {d})) to set value of attribute \"AXFullScreen\" to true",
            .{pid},
        ),
        .close => error.InvalidWindowControl,
    };
}

fn buildAppleScriptForZoomFallback(allocator: std.mem.Allocator, pid: i64) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "tell application \"System Events\" to tell (first window of (first process whose unix id is {d})) to set value of attribute \"AXZoomed\" to true",
        .{pid},
    );
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

test "applescript control template contains target pid and command semantics" {
    const script = try buildAppleScriptForControl(std.testing.allocator, 4242, .minimize);
    defer std.testing.allocator.free(script);
    try std.testing.expect(std.mem.indexOf(u8, script, "unix id is 4242") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "AXMinimized") != null);
}

test "applescript zoom fallback template contains target pid" {
    const script = try buildAppleScriptForZoomFallback(std.testing.allocator, 3001);
    defer std.testing.allocator.free(script);
    try std.testing.expect(std.mem.indexOf(u8, script, "unix id is 3001") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "AXZoomed") != null);
}

test "process alive rejects non-positive pid" {
    try std.testing.expect(!isProcessAlive(std.testing.allocator, 0));
    try std.testing.expect(!isProcessAlive(std.testing.allocator, -9));
}

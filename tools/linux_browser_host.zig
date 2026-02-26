const std = @import("std");
const linux = std.os.linux;

fn parentAlive(expected_parent: std.posix.pid_t) bool {
    return linux.getppid() == expected_parent;
}

fn processGroupAlive(pgid: std.posix.pid_t) bool {
    std.posix.kill(-pgid, 0) catch |err| {
        return switch (err) {
            error.PermissionDenied => true,
            else => false,
        };
    };
    return true;
}

fn terminateProcessGroup(pgid: std.posix.pid_t) void {
    std.posix.kill(-pgid, std.posix.SIG.TERM) catch {};
    var attempt: usize = 0;
    while (attempt < 10 and processGroupAlive(pgid)) : (attempt += 1) {
        std.Thread.sleep(35 * std.time.ns_per_ms);
    }
    std.posix.kill(-pgid, std.posix.SIG.KILL) catch {};
}

fn reapChildNoHang(child_pid: std.posix.pid_t, reaped: *bool) void {
    if (reaped.*) return;
    const result = std.posix.waitpid(child_pid, std.posix.W.NOHANG);
    if (result.pid == child_pid) reaped.* = true;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) return error.InvalidArguments;

    const parent_pid = try std.fmt.parseInt(std.posix.pid_t, args[1], 10);
    const browser_argv = args[2..];

    var child = std.process.Child.init(browser_argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    child.pgid = 0;
    try child.spawn();

    const browser_pid: std.posix.pid_t = child.id;
    var pid_buf: [64]u8 = undefined;
    const pid_line = try std.fmt.bufPrint(&pid_buf, "{d}\n", .{browser_pid});
    _ = try std.posix.write(std.posix.STDOUT_FILENO, pid_line);
    std.posix.close(std.posix.STDOUT_FILENO);

    var child_reaped = false;
    while (true) {
        reapChildNoHang(browser_pid, &child_reaped);

        if (!parentAlive(parent_pid)) {
            terminateProcessGroup(browser_pid);
            if (!child_reaped) {
                _ = std.posix.waitpid(browser_pid, 0);
            }
            return;
        }

        if (!processGroupAlive(browser_pid)) {
            if (!child_reaped) {
                _ = std.posix.waitpid(browser_pid, 0);
            }
            return;
        }

        std.Thread.sleep(120 * std.time.ns_per_ms);
    }
}

const std = @import("std");
const builtin = @import("builtin");

var installed = std.atomic.Value(bool).init(false);
var caught_signal = std.atomic.Value(i32).init(0);

fn recordSignal(sig: i32) void {
    if (caught_signal.load(.acquire) == 0) {
        caught_signal.store(sig, .release);
    }
}

fn installPosix() void {
    installPosixSignal(std.posix.SIG.INT);
    installPosixSignal(std.posix.SIG.TERM);
    installPosixSignal(std.posix.SIG.HUP);
    installPosixSignal(std.posix.SIG.QUIT);
}

fn installPosixSignal(sig: u8) void {
    var action = std.posix.Sigaction{
        .handler = .{ .handler = onPosixSignal },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(sig, &action, null);
}

fn onPosixSignal(sig: i32) callconv(.c) void {
    recordSignal(sig);
}

fn installWindows() void {
    std.os.windows.SetConsoleCtrlHandler(onWindowsCtrl, true) catch {};
}

fn onWindowsCtrl(ctrl_type: std.os.windows.DWORD) callconv(.winapi) std.os.windows.BOOL {
    switch (ctrl_type) {
        std.os.windows.CTRL_C_EVENT => recordSignal(2),
        std.os.windows.CTRL_BREAK_EVENT => recordSignal(21),
        std.os.windows.CTRL_CLOSE_EVENT => recordSignal(15),
        std.os.windows.CTRL_LOGOFF_EVENT => recordSignal(1),
        std.os.windows.CTRL_SHUTDOWN_EVENT => recordSignal(15),
        else => return std.os.windows.FALSE,
    }
    return std.os.windows.TRUE;
}

pub fn install() void {
    if (installed.swap(true, .acq_rel)) return;

    switch (builtin.os.tag) {
        .windows => installWindows(),
        .wasi => {},
        else => installPosix(),
    }
}

pub fn stopRequested() bool {
    return caught_signal.load(.acquire) != 0;
}

pub fn caughtSignal() i32 {
    return caught_signal.load(.acquire);
}

pub fn reset() void {
    caught_signal.store(0, .release);
}

pub fn exitCode() u8 {
    const sig = caughtSignal();
    if (sig <= 0 or sig > 127) return 1;
    return @as(u8, @intCast(128 + sig));
}

pub fn terminateProcess() noreturn {
    const code = exitCode();
    if (builtin.os.tag == .windows) {
        std.process.exit(code);
    } else {
        std.posix.exit(code);
    }
}

test "signal exit code mapping" {
    reset();
    try std.testing.expectEqual(@as(u8, 1), exitCode());

    caught_signal.store(2, .release);
    try std.testing.expectEqual(@as(u8, 130), exitCode());
}

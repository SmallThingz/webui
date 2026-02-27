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
    const script = try buildPowershellLaunchScript(allocator, browser_path, args);
    defer allocator.free(script);

    if (try launchWindowsPowershell(allocator, "powershell", script)) |launch| return launch;
    return try launchWindowsPowershell(allocator, "pwsh", script);
}

pub fn openUrlInExistingInstall(
    allocator: std.mem.Allocator,
    browser_path: []const u8,
    url: []const u8,
) bool {
    const launched = launchTracked(allocator, browser_path, &.{url}) catch null;
    return launched != null;
}

pub fn terminateProcess(allocator: std.mem.Allocator, pid_value: i64) void {
    if (pid_value <= 0) return;

    const pid_text = std.fmt.allocPrint(allocator, "{d}", .{pid_value}) catch return;
    defer allocator.free(pid_text);

    _ = runCommandNoCapture(allocator, &.{ "taskkill", "/PID", pid_text, "/T", "/F" }) catch {};
}

pub fn isProcessAlive(allocator: std.mem.Allocator, pid_value: i64) bool {
    if (pid_value <= 0) return false;

    const pid_text = std.fmt.allocPrint(allocator, "{d}", .{pid_value}) catch return false;
    defer allocator.free(pid_text);
    const filter = std.fmt.allocPrint(allocator, "PID eq {s}", .{pid_text}) catch return false;
    defer allocator.free(filter);

    const out = runCommandCaptureStdout(allocator, &.{ "tasklist", "/FI", filter, "/FO", "CSV", "/NH" }) catch return false;
    defer allocator.free(out);

    if (std.mem.indexOf(u8, out, "No tasks are running") != null) return false;
    return std.mem.indexOf(u8, out, pid_text) != null;
}

pub fn controlWindow(allocator: std.mem.Allocator, pid: i64, cmd: window_style_types.WindowControl) bool {
    if (pid <= 0) return false;

    if (cmd == .close) {
        terminateProcess(allocator, pid);
        return true;
    }

    const show_code = windowsShowWindowCode(cmd) orelse return false;
    const script = std.fmt.allocPrint(
        allocator,
        "$ErrorActionPreference='Stop';" ++
            "Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class WebuiUser32{{[DllImport(\"user32.dll\")] public static extern bool ShowWindowAsync(IntPtr hWnd,int nCmdShow);}}' -ErrorAction SilentlyContinue | Out-Null;" ++
            "$p=Get-Process -Id {d} -ErrorAction Stop;" ++
            "if($p.MainWindowHandle -eq 0){{exit 2}};" ++
            "[WebuiUser32]::ShowWindowAsync($p.MainWindowHandle,{d}) | Out-Null;" ++
            "exit 0;",
        .{ pid, show_code },
    ) catch return false;
    defer allocator.free(script);

    if (runCommandNoCapture(allocator, &.{ "powershell", "-NoProfile", "-NonInteractive", "-Command", script }) catch false) return true;
    return runCommandNoCapture(allocator, &.{ "pwsh", "-NoProfile", "-NonInteractive", "-Command", script }) catch false;
}

fn launchWindowsPowershell(allocator: std.mem.Allocator, shell_exe: []const u8, script: []const u8) !?LaunchResult {
    const out = runCommandCaptureStdout(allocator, &.{ shell_exe, "-NoProfile", "-NonInteractive", "-Command", script }) catch return null;
    defer allocator.free(out);

    const pid = parsePidFromOutput(out) orelse return null;
    return .{ .pid = pid, .is_child_process = true };
}

fn windowsShowWindowCode(cmd: window_style_types.WindowControl) ?i32 {
    return switch (cmd) {
        .hide => 0,
        .show => 5,
        .maximize => 3,
        .minimize => 6,
        .restore => 9,
        .close => null,
    };
}

fn parsePidFromOutput(output: []const u8) ?i64 {
    const trimmed = std.mem.trim(u8, output, " \t\r\n");
    if (trimmed.len == 0) return null;
    return std.fmt.parseInt(i64, trimmed, 10) catch null;
}

fn buildPowershellLaunchScript(
    allocator: std.mem.Allocator,
    browser_path: []const u8,
    args: []const []const u8,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    const w = out.writer();
    try w.writeAll("$ErrorActionPreference='Stop';$p=Start-Process -FilePath '");
    try appendPowershellSingleQuoted(&out, browser_path);
    try w.writeAll("' -ArgumentList @(");

    for (args, 0..) |arg, i| {
        if (i != 0) try w.writeAll(",");
        try w.writeAll("'");
        try appendPowershellSingleQuoted(&out, arg);
        try w.writeAll("'");
    }

    try w.writeAll(") -PassThru -WindowStyle Hidden;[Console]::Out.Write($p.Id)");
    return out.toOwnedSlice();
}

fn appendPowershellSingleQuoted(out: *std.array_list.Managed(u8), value: []const u8) !void {
    for (value) |ch| {
        if (ch == '\'') {
            try out.appendSlice("''");
        } else {
            try out.append(ch);
        }
    }
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

test "windows show window command mapping is stable" {
    try std.testing.expectEqual(@as(?i32, 0), windowsShowWindowCode(.hide));
    try std.testing.expectEqual(@as(?i32, 5), windowsShowWindowCode(.show));
    try std.testing.expectEqual(@as(?i32, 6), windowsShowWindowCode(.minimize));
    try std.testing.expectEqual(@as(?i32, 3), windowsShowWindowCode(.maximize));
    try std.testing.expectEqual(@as(?i32, 9), windowsShowWindowCode(.restore));
    try std.testing.expectEqual(@as(?i32, null), windowsShowWindowCode(.close));
}

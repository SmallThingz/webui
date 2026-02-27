const std = @import("std");
const browser_discovery = @import("../ported/browser_discovery.zig");
const windows_browser_host = @import("windows_browser_host.zig");
const window_style_types = @import("../root/window_style.zig");

const WindowStyle = window_style_types.WindowStyle;
const WindowControl = window_style_types.WindowControl;

const Command = union(enum) {
    navigate: []u8,
    apply_style: WindowStyle,
    control: WindowControl,
    shutdown,

    fn deinit(self: *Command, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .navigate => |buf| allocator.free(buf),
            .apply_style, .control, .shutdown => {},
        }
    }
};

pub const Host = struct {
    allocator: std.mem.Allocator,
    title: []u8,
    style: WindowStyle,

    thread: ?std.Thread = null,
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    queue: std.array_list.Managed(Command),

    startup_done: bool = false,
    startup_error: ?anyerror = null,
    ui_ready: bool = false,
    closed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    shutdown_requested: bool = false,

    browser_path: ?[]u8 = null,
    browser_kind: ?browser_discovery.BrowserKind = null,
    browser_pid: ?i64 = null,

    pub fn start(allocator: std.mem.Allocator, title: []const u8, style: WindowStyle) !*Host {
        if (!runtimeAvailable()) return error.NativeBackendUnavailable;

        const host = try allocator.create(Host);
        errdefer allocator.destroy(host);

        host.* = .{
            .allocator = allocator,
            .title = try allocator.dupe(u8, title),
            .style = style,
            .queue = std.array_list.Managed(Command).init(allocator),
        };
        errdefer {
            allocator.free(host.title);
            host.queue.deinit();
        }

        host.thread = try std.Thread.spawn(.{}, threadMain, .{host});

        host.mutex.lock();
        while (!host.startup_done) host.cond.wait(&host.mutex);
        const startup_error = host.startup_error;
        const ready = host.ui_ready;
        host.mutex.unlock();

        if (startup_error) |err| {
            host.deinit();
            return err;
        }
        if (!ready) {
            host.deinit();
            return error.NativeBackendUnavailable;
        }
        return host;
    }

    pub fn deinit(self: *Host) void {
        self.enqueue(.shutdown) catch {};

        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }

        self.mutex.lock();
        for (self.queue.items) |*cmd| cmd.deinit(self.allocator);
        self.queue.clearRetainingCapacity();
        self.mutex.unlock();

        self.queue.deinit();

        if (self.browser_path) |path| self.allocator.free(path);
        self.allocator.free(self.title);
        self.allocator.destroy(self);
    }

    pub fn isReady(self: *Host) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.ui_ready and !self.closed.load(.acquire);
    }

    pub fn isClosed(self: *Host) bool {
        return self.closed.load(.acquire);
    }

    pub fn navigate(self: *Host, url: []const u8) !void {
        const duped = try self.allocator.dupe(u8, url);
        errdefer self.allocator.free(duped);
        try self.enqueue(.{ .navigate = duped });
    }

    pub fn applyStyle(self: *Host, style: WindowStyle) !void {
        try self.enqueue(.{ .apply_style = style });
    }

    pub fn control(self: *Host, cmd: WindowControl) !void {
        try self.enqueue(.{ .control = cmd });
    }

    fn enqueue(self: *Host, command: Command) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.closed.load(.acquire) or self.shutdown_requested) {
            var cmd = command;
            cmd.deinit(self.allocator);
            return error.NativeWindowClosed;
        }

        try self.queue.append(command);
        self.cond.signal();
    }
};

pub fn runtimeAvailable() bool {
    if (@import("builtin").os.tag != .windows) return false;

    if (std.DynLib.open("WebView2Loader.dll")) |opened| {
        var lib = opened;
        lib.close();
        return true;
    } else |_| {}

    const installs = browser_discovery.discoverInstalledBrowsers(std.heap.page_allocator) catch return false;
    defer if (installs.len > 0) browser_discovery.freeInstalls(std.heap.page_allocator, installs);
    return installs.len > 0;
}

fn threadMain(host: *Host) void {
    host.mutex.lock();
    host.ui_ready = true;
    host.startup_done = true;
    host.cond.broadcast();
    host.mutex.unlock();

    while (true) {
        host.mutex.lock();
        while (host.queue.items.len == 0 and !host.shutdown_requested) {
            host.cond.wait(&host.mutex);
        }
        if (host.shutdown_requested and host.queue.items.len == 0) {
            host.mutex.unlock();
            break;
        }

        var cmd = host.queue.orderedRemove(0);
        host.mutex.unlock();

        executeCommand(host, &cmd);
        cmd.deinit(host.allocator);
    }

    host.mutex.lock();
    host.closed.store(true, .release);
    host.ui_ready = false;
    host.cond.broadcast();
    host.mutex.unlock();
}

fn executeCommand(host: *Host, command: *Command) void {
    switch (command.*) {
        .navigate => |url| {
            if (!launchOrNavigate(host, url)) {
                host.mutex.lock();
                host.startup_error = error.NativeBackendUnavailable;
                host.closed.store(true, .release);
                host.shutdown_requested = true;
                host.cond.broadcast();
                host.mutex.unlock();
            }
        },
        .apply_style => |style| {
            host.style = style;
            if (host.browser_pid) |pid| {
                if (style.hidden) {
                    _ = windows_browser_host.controlWindow(host.allocator, pid, .hide);
                } else {
                    _ = windows_browser_host.controlWindow(host.allocator, pid, .show);
                }
            }
        },
        .control => |cmd| {
            if (host.browser_pid) |pid| {
                _ = windows_browser_host.controlWindow(host.allocator, pid, cmd);
                if (cmd == .close) {
                    host.mutex.lock();
                    host.closed.store(true, .release);
                    host.shutdown_requested = true;
                    host.mutex.unlock();
                }
            }
        },
        .shutdown => {
            if (host.browser_pid) |pid| {
                windows_browser_host.terminateProcess(host.allocator, pid);
            }
            host.mutex.lock();
            host.shutdown_requested = true;
            host.closed.store(true, .release);
            host.cond.broadcast();
            host.mutex.unlock();
        },
    }
}

fn launchOrNavigate(host: *Host, url: []const u8) bool {
    if (host.browser_path) |path| {
        if (windows_browser_host.openUrlInExistingInstall(host.allocator, path, url)) return true;
    }

    const installs = browser_discovery.discoverInstalledBrowsers(host.allocator) catch return false;
    defer if (installs.len > 0) browser_discovery.freeInstalls(host.allocator, installs);

    var selected: ?browser_discovery.BrowserInstall = null;
    for (installs) |install| {
        if (!supportsChromiumAppMode(install.kind)) continue;
        selected = install;
        break;
    }
    if (selected == null and installs.len > 0) selected = installs[0];

    const chosen = selected orelse return false;

    var args = std.array_list.Managed([]const u8).init(host.allocator);
    defer args.deinit();
    var owned = std.array_list.Managed([]u8).init(host.allocator);
    defer {
        for (owned.items) |buf| host.allocator.free(buf);
        owned.deinit();
    }

    if (supportsChromiumAppMode(chosen.kind)) {
        args.append("--new-window") catch return false;

        const app_arg = std.fmt.allocPrint(host.allocator, "--app={s}", .{url}) catch return false;
        owned.append(app_arg) catch return false;
        args.append(app_arg) catch return false;

        if (host.style.kiosk) args.append("--kiosk") catch return false;
        if (host.style.transparent) args.append("--enable-transparent-visuals") catch return false;
        if (host.style.hidden) args.append("--start-minimized") catch return false;
        if (host.style.size) |size| {
            const size_arg = std.fmt.allocPrint(host.allocator, "--window-size={d},{d}", .{ size.width, size.height }) catch return false;
            owned.append(size_arg) catch return false;
            args.append(size_arg) catch return false;
        }
        if (host.style.position) |pos| {
            const pos_arg = std.fmt.allocPrint(host.allocator, "--window-position={d},{d}", .{ pos.x, pos.y }) catch return false;
            owned.append(pos_arg) catch return false;
            args.append(pos_arg) catch return false;
        }
    } else {
        args.append(url) catch return false;
    }

    const launched = windows_browser_host.launchTracked(host.allocator, chosen.path, args.items) catch null;
    const result = launched orelse return false;

    if (host.browser_path) |path| host.allocator.free(path);
    host.browser_path = host.allocator.dupe(u8, chosen.path) catch null;
    host.browser_kind = chosen.kind;
    host.browser_pid = result.pid;
    return true;
}

fn supportsChromiumAppMode(kind: browser_discovery.BrowserKind) bool {
    return switch (kind) {
        .chrome,
        .edge,
        .chromium,
        .opera,
        .brave,
        .vivaldi,
        .epic,
        .yandex,
        .duckduckgo,
        .arc,
        .sidekick,
        .shift,
        .operagx,
        => true,
        else => false,
    };
}

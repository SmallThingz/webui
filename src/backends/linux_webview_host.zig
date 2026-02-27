const std = @import("std");
const common = @import("linux_webview/common.zig");
const symbols_mod = @import("linux_webview/symbols.zig");
const rounded_shape = @import("linux_webview/rounded_shape.zig");

const WindowStyle = common.WindowStyle;
const WindowControl = common.WindowControl;
const Symbols = symbols_mod.Symbols;
const Queue = std.array_list.Managed(Command);

const default_width: c_int = 980;
const default_height: c_int = 660;

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
    queue: Queue,

    symbols: ?Symbols = null,
    window_widget: ?*common.GtkWidget = null,
    webview: ?*common.WebKitWebView = null,
    main_loop: ?*common.GMainLoop = null,

    startup_done: bool = false,
    startup_error: ?anyerror = null,
    ui_ready: bool = false,
    closed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    shutdown_requested: bool = false,

    pub fn start(allocator: std.mem.Allocator, title: []const u8, style: WindowStyle) !*Host {
        if (!hasDisplaySession()) return error.NativeBackendUnavailable;

        const host = try allocator.create(Host);
        errdefer allocator.destroy(host);

        host.* = .{
            .allocator = allocator,
            .title = try allocator.dupe(u8, title),
            .style = style,
            .queue = Queue.init(allocator),
        };
        errdefer {
            allocator.free(host.title);
            host.queue.deinit();
        }

        host.thread = try std.Thread.spawn(.{}, threadMain, .{host});
        errdefer if (host.thread) |thread| thread.detach();

        host.mutex.lock();
        while (!host.startup_done) {
            host.cond.wait(&host.mutex);
        }
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
        if (self.symbols) |*symbols| {
            symbols.deinit();
            self.symbols = null;
        }
        self.mutex.unlock();

        self.queue.deinit();
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

        // Reject new work once shutdown starts; callers treat this as a closed window.
        if (self.closed.load(.acquire) or self.shutdown_requested) {
            var cmd = command;
            cmd.deinit(self.allocator);
            return error.NativeWindowClosed;
        }

        try self.queue.append(command);
        scheduleDrainLocked(self);
    }

    fn scheduleDrainLocked(self: *Host) void {
        if (!self.ui_ready) return;
        if (self.symbols) |symbols| {
            _ = symbols.g_idle_add(&onIdleDrain, self);
        }
    }
};

pub fn runtimeAvailable() bool {
    if (!hasDisplaySession()) return false;
    var symbols = Symbols.load() catch return false;
    symbols.deinit();
    return true;
}

fn threadMain(host: *Host) void {
    const loaded = Symbols.load() catch |err| {
        failStartup(host, err);
        return;
    };

    host.mutex.lock();
    host.symbols = loaded;
    host.mutex.unlock();

    const symbols = &host.symbols.?;
    symbols.initToolkit();

    const window_widget = symbols.newTopLevelWindow() orelse {
        failStartup(host, error.NativeBackendUnavailable);
        return;
    };
    const webview_widget = symbols.webkit_web_view_new() orelse {
        failStartup(host, error.NativeBackendUnavailable);
        return;
    };
    const webview: *common.WebKitWebView = @ptrCast(webview_widget);

    const title_z = host.allocator.dupeZ(u8, host.title) catch {
        failStartup(host, error.OutOfMemory);
        return;
    };
    defer host.allocator.free(title_z);

    const window: *common.GtkWindow = @ptrCast(window_widget);
    symbols.gtk_window_set_title(window, title_z);

    const width: c_int = if (host.style.size) |size| @as(c_int, @intCast(size.width)) else default_width;
    const height: c_int = if (host.style.size) |size| @as(c_int, @intCast(size.height)) else default_height;
    symbols.gtk_window_set_default_size(window, width, height);
    symbols.addWindowChild(window_widget, webview_widget);

    const main_loop = symbols.g_main_loop_new(null, 0) orelse {
        failStartup(host, error.NativeBackendUnavailable);
        return;
    };

    host.mutex.lock();
    host.window_widget = window_widget;
    host.webview = webview;
    host.main_loop = main_loop;
    host.mutex.unlock();

    applyStyleUiThread(host, host.style);
    connectWindowSignals(symbols, window_widget, host);

    symbols.showWindow(window_widget, webview_widget);

    host.mutex.lock();
    host.ui_ready = true;
    host.startup_done = true;
    host.cond.broadcast();
    host.mutex.unlock();

    if (host.main_loop) |loop_ptr| {
        symbols.g_main_loop_run(loop_ptr);
    }
    finishThreadShutdown(host);
}

fn connectWindowSignals(symbols: *const Symbols, window_widget: *common.GtkWidget, host: *Host) void {
    _ = symbols.g_signal_connect_data(@ptrCast(window_widget), "destroy", @ptrCast(&onDestroy), host, null, 0);
    _ = symbols.g_signal_connect_data(@ptrCast(window_widget), "realize", @ptrCast(&onRealize), host, null, 0);
    _ = symbols.g_signal_connect_data(@ptrCast(window_widget), "size-allocate", @ptrCast(&onSizeAllocate), host, null, 0);
}

fn failStartup(host: *Host, err: anyerror) void {
    host.mutex.lock();
    defer host.mutex.unlock();

    if (host.symbols) |*symbols| {
        symbols.deinit();
        host.symbols = null;
    }

    host.startup_error = err;
    host.startup_done = true;
    host.closed.store(true, .release);
    host.cond.broadcast();
}

fn finishThreadShutdown(host: *Host) void {
    host.mutex.lock();
    defer host.mutex.unlock();

    host.closed.store(true, .release);
    host.ui_ready = false;
    host.window_widget = null;
    host.webview = null;
    if (host.main_loop) |loop_ptr| {
        if (host.symbols) |symbols| {
            symbols.g_main_loop_unref(loop_ptr);
        }
    }
    host.main_loop = null;

    for (host.queue.items) |*cmd| cmd.deinit(host.allocator);
    host.queue.clearRetainingCapacity();

    if (host.symbols) |*symbols| {
        symbols.deinit();
    }
    host.symbols = null;
    host.cond.broadcast();
}

fn onIdleDrain(data: ?*anyopaque) callconv(.c) c_int {
    const host = data orelse return 0;
    const typed: *Host = @ptrCast(@alignCast(host));
    drainCommandsUiThread(typed);
    return 0;
}

fn onDestroy(_: ?*anyopaque, data: ?*anyopaque) callconv(.c) void {
    const host = data orelse return;
    const typed: *Host = @ptrCast(@alignCast(host));
    // Keep close-state transitions under the same lock used by enqueue/deinit.
    typed.mutex.lock();
    defer typed.mutex.unlock();
    typed.closed.store(true, .release);
    typed.shutdown_requested = true;
    if (typed.symbols) |symbols| {
        if (typed.main_loop) |main_loop| symbols.g_main_loop_quit(main_loop);
    }
}

fn onRealize(widget: ?*anyopaque, data: ?*anyopaque) callconv(.c) void {
    const raw_widget = widget orelse return;
    const raw_host = data orelse return;
    const host: *Host = @ptrCast(@alignCast(raw_host));
    const window_widget: *common.GtkWidget = @ptrCast(@alignCast(raw_widget));

    host.mutex.lock();
    defer host.mutex.unlock();
    const symbols = host.symbols orelse return;
    applyRoundedShape(&symbols, host.style.corner_radius, window_widget);
}

fn onSizeAllocate(widget: ?*anyopaque, allocation: ?*anyopaque, data: ?*anyopaque) callconv(.c) void {
    const raw_widget = widget orelse return;
    const raw_host = data orelse return;
    const host: *Host = @ptrCast(@alignCast(raw_host));
    const window_widget: *common.GtkWidget = @ptrCast(@alignCast(raw_widget));

    host.mutex.lock();
    defer host.mutex.unlock();
    const symbols = host.symbols orelse return;

    if (allocation) |raw_alloc| {
        const alloc: *common.GtkAllocation = @ptrCast(@alignCast(raw_alloc));
        rounded_shape.applyRoundedWindowShape(&symbols, host.style.corner_radius, window_widget, alloc.width, alloc.height);
        return;
    }
    applyRoundedShape(&symbols, host.style.corner_radius, window_widget);
}

fn drainCommandsUiThread(host: *Host) void {
    // Drain one command at a time so command execution does not hold queue lock.
    while (true) {
        host.mutex.lock();
        if (host.queue.items.len == 0) {
            host.mutex.unlock();
            break;
        }
        var cmd = host.queue.orderedRemove(0);
        host.mutex.unlock();

        executeUiCommand(host, &cmd);
        cmd.deinit(host.allocator);
    }
}

fn executeUiCommand(host: *Host, command: *Command) void {
    host.mutex.lock();
    defer host.mutex.unlock();

    if (host.closed.load(.acquire)) return;
    const symbols = host.symbols orelse return;

    switch (command.*) {
        .navigate => |url| {
            const webview = host.webview orelse return;
            const url_z = host.allocator.dupeZ(u8, url) catch return;
            defer host.allocator.free(url_z);
            symbols.webkit_web_view_load_uri(webview, url_z);
        },
        .apply_style => |style| applyStyleUiThread(host, style),
        .control => |cmd| applyControlUiThread(host, cmd),
        .shutdown => {
            host.shutdown_requested = true;
            if (host.window_widget) |window_widget| {
                symbols.gtk_widget_destroy(window_widget);
            }
            if (host.main_loop) |main_loop| symbols.g_main_loop_quit(main_loop);
        },
    }
}

fn applyStyleUiThread(host: *Host, style: WindowStyle) void {
    host.style = style;

    const symbols = host.symbols orelse return;
    const window_widget = host.window_widget orelse return;
    const window: *common.GtkWindow = @ptrCast(window_widget);

    symbols.gtk_window_set_decorated(window, if (style.frameless) 0 else 1);
    symbols.gtk_window_set_resizable(window, if (style.resizable) 1 else 0);

    if (style.size) |size| {
        symbols.gtk_window_set_default_size(window, @as(c_int, @intCast(size.width)), @as(c_int, @intCast(size.height)));
    }

    if (style.center or style.position == null) {
        symbols.setWindowPositionCenter(window);
    } else if (style.position) |pos| {
        symbols.setWindowPosition(window, @as(c_int, @intCast(pos.x)), @as(c_int, @intCast(pos.y)));
    }

    if (style.transparent) {
        symbols.applyTransparentVisual(window_widget);
    }

    if (host.webview) |webview| {
        const bg = if (style.transparent)
            common.GdkRGBA{ .red = 0.0, .green = 0.0, .blue = 0.0, .alpha = 0.0 }
        else
            common.GdkRGBA{ .red = 1.0, .green = 1.0, .blue = 1.0, .alpha = 1.0 };
        symbols.webkit_web_view_set_background_color(webview, &bg);
    }

    applyRoundedShape(&symbols, style.corner_radius, window_widget);

    if (style.hidden) {
        symbols.gtk_widget_hide(window_widget);
    } else {
        symbols.gtk_widget_show(window_widget);
    }
}

fn applyControlUiThread(host: *Host, cmd: WindowControl) void {
    const symbols = host.symbols orelse return;
    const window_widget = host.window_widget orelse return;
    const window: *common.GtkWindow = @ptrCast(window_widget);

    switch (cmd) {
        .minimize => symbols.minimizeWindow(window),
        .maximize => symbols.gtk_window_maximize(window),
        .restore => {
            symbols.gtk_window_unmaximize(window);
            symbols.gtk_widget_show(window_widget);
        },
        .close => {
            host.shutdown_requested = true;
            symbols.gtk_widget_destroy(window_widget);
            if (host.main_loop) |main_loop| symbols.g_main_loop_quit(main_loop);
        },
        .hide => symbols.gtk_widget_hide(window_widget),
        .show => symbols.gtk_widget_show(window_widget),
    }
}

fn hasDisplaySession() bool {
    return envVarNonEmpty("DISPLAY") or envVarNonEmpty("WAYLAND_DISPLAY");
}

fn envVarNonEmpty(name: []const u8) bool {
    const value = std.process.getEnvVarOwned(std.heap.page_allocator, name) catch return false;
    defer std.heap.page_allocator.free(value);
    return value.len > 0;
}

fn applyRoundedShape(symbols: *const Symbols, corner_radius: ?u16, window_widget: *common.GtkWidget) void {
    rounded_shape.applyRoundedWindowShape(
        symbols,
        corner_radius,
        window_widget,
        symbols.gtk_widget_get_allocated_width(window_widget),
        symbols.gtk_widget_get_allocated_height(window_widget),
    );
}

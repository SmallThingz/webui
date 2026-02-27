const std = @import("std");
const common = @import("linux_webview/common.zig");
const symbols_mod = @import("linux_webview/symbols.zig");
const rounded_shape = @import("linux_webview/rounded_shape.zig");

const WindowStyle = common.WindowStyle;
const WindowControl = common.WindowControl;
const WindowIcon = common.WindowIcon;
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
    content_widget: ?*common.GtkWidget = null,
    webview: ?*common.WebKitWebView = null,
    main_loop: ?*common.GMainLoop = null,
    icon_temp_path: ?[]u8 = null,

    startup_done: bool = false,
    startup_error: ?anyerror = null,
    ui_ready: bool = false,
    closed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    shutdown_requested: bool = false,

    pub fn start(allocator: std.mem.Allocator, title: []const u8, style: WindowStyle) !*Host {
        if (!hasDisplaySession()) return error.NativeBackendUnavailable;

        const host = try allocator.create(Host);
        var cleanup_host = true;
        errdefer if (cleanup_host) allocator.destroy(host);

        host.* = .{
            .allocator = allocator,
            .title = try allocator.dupe(u8, title),
            .style = style,
            .queue = Queue.init(allocator),
        };
        var cleanup_title = true;
        var cleanup_queue = true;
        errdefer if (cleanup_title) allocator.free(host.title);
        errdefer if (cleanup_queue) host.queue.deinit();

        host.thread = try std.Thread.spawn(.{}, threadMain, .{host});
        var detach_thread = true;
        errdefer if (detach_thread) if (host.thread) |thread| thread.detach();

        host.mutex.lock();
        while (!host.startup_done) {
            host.cond.wait(&host.mutex);
        }
        const startup_error = host.startup_error;
        const ready = host.ui_ready;
        host.mutex.unlock();

        if (startup_error) |err| {
            // Hand off cleanup to host.deinit() to avoid errdefer double-free.
            detach_thread = false;
            cleanup_queue = false;
            cleanup_title = false;
            cleanup_host = false;
            host.deinit();
            return err;
        }
        if (!ready) {
            // Hand off cleanup to host.deinit() to avoid errdefer double-free.
            detach_thread = false;
            cleanup_queue = false;
            cleanup_title = false;
            cleanup_host = false;
            host.deinit();
            return error.NativeBackendUnavailable;
        }

        // Success path: caller owns host lifecycle.
        detach_thread = false;
        cleanup_queue = false;
        cleanup_title = false;
        cleanup_host = false;
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
        cleanupIconTempFile(self);
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
    const content_widget = symbols.addWindowChild(window_widget, webview_widget) orelse {
        failStartup(host, error.NativeBackendUnavailable);
        return;
    };

    const main_loop = symbols.g_main_loop_new(null, 0) orelse {
        failStartup(host, error.NativeBackendUnavailable);
        return;
    };

    host.mutex.lock();
    host.window_widget = window_widget;
    host.content_widget = content_widget;
    host.webview = webview;
    host.main_loop = main_loop;
    host.mutex.unlock();

    applyStyleUiThread(host, host.style);
    connectWindowSignals(symbols, window_widget, host);

    symbols.showWindow(window_widget, content_widget);
    if (content_widget != webview_widget) {
        symbols.gtk_widget_show(webview_widget);
    }

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
    // Keep realize callback for all GTK variants so style/transparency can be
    // re-applied once the native surface exists. GTK4 size-allocate ABI differs.
    _ = symbols.g_signal_connect_data(@ptrCast(window_widget), "realize", @ptrCast(&onRealize), host, null, 0);
    if (symbols.gtk_api == .gtk3) {
        _ = symbols.g_signal_connect_data(@ptrCast(window_widget), "size-allocate", @ptrCast(&onSizeAllocate), host, null, 0);
    }
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
    host.content_widget = null;
    host.webview = null;
    cleanupIconTempFile(host);
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
    // Destroy can be emitted while other UI callbacks are active.
    // Never take a blocking lock here; just publish closed state and
    // best-effort mark shutdown to avoid recursive-lock deadlocks.
    typed.closed.store(true, .release);
    if (typed.mutex.tryLock()) {
        typed.shutdown_requested = true;
        typed.mutex.unlock();
    }
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
    const clip_widget = host.content_widget orelse window_widget;
    if (host.style.transparent) symbols.applyTransparentVisual(window_widget);
    symbols.applyGtk4WindowStyle(window_widget, clip_widget, host.style);
    applyRoundedShape(&symbols, host.style.corner_radius, window_widget);
    queueDrawTargets(host, &symbols, window_widget, clip_widget);
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
    const is_closed = host.closed.load(.acquire);
    const symbols = host.symbols;
    const webview = host.webview;
    const window_widget = host.window_widget;
    const main_loop = host.main_loop;
    host.mutex.unlock();

    if (is_closed) return;
    const syms = symbols orelse return;

    switch (command.*) {
        .navigate => |url| {
            const target = webview orelse return;
            const url_z = host.allocator.dupeZ(u8, url) catch return;
            defer host.allocator.free(url_z);
            syms.webkit_web_view_load_uri(target, url_z);
        },
        .apply_style => |style| applyStyleUiThread(host, style),
        .control => |cmd| applyControlUiThread(host, cmd),
        .shutdown => {
            host.mutex.lock();
            host.shutdown_requested = true;
            host.mutex.unlock();

            if (window_widget) |widget| {
                syms.destroyWindow(widget);
            }
            if (main_loop) |loop| syms.g_main_loop_quit(loop);
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
    symbols.setWindowMinSize(window_widget, style.min_size);

    if (style.center or style.position == null) {
        symbols.setWindowPositionCenter(window);
    } else if (style.position) |pos| {
        symbols.setWindowPosition(window, @as(c_int, @intCast(pos.x)), @as(c_int, @intCast(pos.y)));
    }

    if (style.transparent) {
        symbols.applyTransparentVisual(window_widget);
    }

    if (host.webview) |webview| {
        if (symbols.gtk_api == .gtk4) {
            const bg = if (style.transparent)
                common.GdkRGBA4{ .red = 0.0, .green = 0.0, .blue = 0.0, .alpha = 0.0 }
            else
                common.GdkRGBA4{ .red = 1.0, .green = 1.0, .blue = 1.0, .alpha = 1.0 };
            symbols.webkit_web_view_set_background_color(webview, @ptrCast(&bg));
        } else {
            const bg = if (style.transparent)
                common.GdkRGBA3{ .red = 0.0, .green = 0.0, .blue = 0.0, .alpha = 0.0 }
            else
                common.GdkRGBA3{ .red = 1.0, .green = 1.0, .blue = 1.0, .alpha = 1.0 };
            symbols.webkit_web_view_set_background_color(webview, @ptrCast(&bg));
        }
        symbols.applyGtk4WindowStyle(window_widget, host.content_widget orelse @ptrCast(webview), style);
    } else {
        symbols.applyGtk4WindowStyle(window_widget, host.content_widget orelse window_widget, style);
    }

    applyRoundedShape(&symbols, style.corner_radius, window_widget);
    symbols.setWindowKiosk(window, style.kiosk);
    symbols.setWindowHighContrast(window_widget, host.content_widget, style.high_contrast);
    applyWindowIconUiThread(host, &symbols, window_widget, style.icon);

    if (style.hidden) {
        symbols.gtk_widget_hide(window_widget);
    } else {
        symbols.gtk_widget_show(window_widget);
    }
    queueDrawTargets(host, &symbols, window_widget, host.content_widget orelse window_widget);
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
            host.mutex.lock();
            host.shutdown_requested = true;
            host.mutex.unlock();
            symbols.destroyWindow(window_widget);
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

fn queueDrawTargets(host: *Host, symbols: *const Symbols, window_widget: *common.GtkWidget, clip_widget: *common.GtkWidget) void {
    symbols.queueWidgetDraw(window_widget);
    symbols.queueWidgetDraw(clip_widget);
    if (host.webview) |webview| symbols.queueWidgetDraw(@ptrCast(webview));
}

fn applyWindowIconUiThread(host: *Host, symbols: *const Symbols, window_widget: *common.GtkWidget, icon: ?WindowIcon) void {
    if (icon) |window_icon| {
        const icon_path = writeIconTempFile(host, window_icon) catch return;
        const icon_path_z = host.allocator.dupeZ(u8, icon_path) catch return;
        defer host.allocator.free(icon_path_z);
        symbols.setWindowIconFromPath(window_widget, icon_path_z);
        return;
    }
    cleanupIconTempFile(host);
    symbols.clearWindowIcon(window_widget);
}

fn writeIconTempFile(host: *Host, icon: WindowIcon) ![]u8 {
    cleanupIconTempFile(host);

    const ext = iconExtensionForMime(icon.mime_type);
    const name = try std.fmt.allocPrint(host.allocator, "webui-icon-{d}{s}", .{ std.time.nanoTimestamp(), ext });
    defer host.allocator.free(name);

    const dir_path = std.process.getEnvVarOwned(host.allocator, "XDG_RUNTIME_DIR") catch try host.allocator.dupe(u8, "/tmp");
    defer host.allocator.free(dir_path);

    const full_path = try std.fs.path.join(host.allocator, &.{ dir_path, name });
    errdefer host.allocator.free(full_path);

    var file = try std.fs.createFileAbsolute(full_path, .{ .truncate = true, .read = false });
    defer file.close();
    try file.writeAll(icon.bytes);

    host.icon_temp_path = full_path;
    return full_path;
}

fn iconExtensionForMime(mime_type: []const u8) []const u8 {
    if (std.mem.eql(u8, mime_type, "image/png")) return ".png";
    if (std.mem.eql(u8, mime_type, "image/jpeg") or std.mem.eql(u8, mime_type, "image/jpg")) return ".jpg";
    if (std.mem.eql(u8, mime_type, "image/x-icon") or std.mem.eql(u8, mime_type, "image/vnd.microsoft.icon")) return ".ico";
    if (std.mem.eql(u8, mime_type, "image/webp")) return ".webp";
    return ".img";
}

fn cleanupIconTempFile(host: *Host) void {
    if (host.icon_temp_path) |path| {
        std.fs.deleteFileAbsolute(path) catch {};
        host.allocator.free(path);
        host.icon_temp_path = null;
    }
}

test "onDestroy avoids recursive mutex deadlock when lock is already held" {
    var host: Host = undefined;
    host.mutex = .{};
    host.closed = std.atomic.Value(bool).init(false);
    host.shutdown_requested = false;
    host.symbols = null;
    host.main_loop = null;

    host.mutex.lock();
    defer host.mutex.unlock();
    onDestroy(null, @ptrCast(&host));

    try std.testing.expect(host.closed.load(.acquire));
}

const std = @import("std");
const common = @import("linux_webview/common.zig");
const symbols_mod = @import("linux_webview/symbols.zig");
const rounded_shape = @import("linux_webview/rounded_shape.zig");

const WindowStyle = common.WindowStyle;
const WindowControl = common.WindowControl;
const WindowIcon = common.WindowIcon;
const Symbols = symbols_mod.Symbols;
pub const RuntimeTarget = symbols_mod.RuntimeTarget;
const Queue = std.array_list.Managed(Command);

const default_width: c_int = 980;
const default_height: c_int = 660;
const ProbeCache = enum(u8) {
    unknown = 0,
    unavailable = 1,
    available = 2,
};
var probe_cache_webview: std.atomic.Value(u8) = std.atomic.Value(u8).init(@intFromEnum(ProbeCache.unknown));
var probe_cache_webkitgtk6: std.atomic.Value(u8) = std.atomic.Value(u8).init(@intFromEnum(ProbeCache.unknown));

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
    runtime_target: RuntimeTarget = .webview,

    mutex: std.Thread.Mutex = .{},
    queue: Queue,

    symbols: ?Symbols = null,
    window_widget: ?*common.GtkWidget = null,
    content_widget: ?*common.GtkWidget = null,
    webview: ?*common.WebKitWebView = null,
    icon_temp_path: ?[]u8 = null,

    ui_ready: bool = false,
    closed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    shutdown_requested: bool = false,

    pub fn start(
        allocator: std.mem.Allocator,
        title: []const u8,
        style: WindowStyle,
        runtime_target: RuntimeTarget,
    ) !*Host {
        if (!hasDisplaySession()) return error.NativeBackendUnavailable;

        const host = try allocator.create(Host);
        errdefer allocator.destroy(host);

        host.* = .{
            .allocator = allocator,
            .title = try allocator.dupe(u8, title),
            .style = style,
            .runtime_target = runtime_target,
            .queue = Queue.init(allocator),
        };
        errdefer allocator.free(host.title);
        errdefer host.queue.deinit();
        errdefer cleanupIconTempFile(host);

        try initOnCurrentThread(host);
        return host;
    }

    pub fn deinit(self: *Host) void {
        _ = self.enqueue(.shutdown) catch {};

        var spins: usize = 0;
        while (spins < 2048 and !self.closed.load(.acquire)) : (spins += 1) {
            self.pump();
            std.Thread.sleep(std.time.ns_per_ms);
        }
        self.pump();

        self.mutex.lock();
        if (!self.closed.load(.acquire)) {
            if (self.symbols) |symbols| {
                if (self.window_widget) |window_widget| {
                    symbols.destroyWindow(window_widget);
                }
            }
            self.closed.store(true, .release);
            self.ui_ready = false;
            self.shutdown_requested = true;
        }

        for (self.queue.items) |*cmd| cmd.deinit(self.allocator);
        self.queue.clearRetainingCapacity();

        cleanupIconTempFile(self);
        self.window_widget = null;
        self.content_widget = null;
        self.webview = null;
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

    pub fn pump(self: *Host) void {
        drainCommandsUiThread(self);

        const symbols = self.symbols orelse return;
        const iterate = symbols.g_main_context_iteration orelse return;

        var spins: usize = 0;
        while (spins < 64) : (spins += 1) {
            if (iterate(null, 0) == 0) break;
        }

        drainCommandsUiThread(self);
    }

    fn enqueue(self: *Host, command: Command) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const is_shutdown_cmd = switch (command) {
            .shutdown => true,
            else => false,
        };

        if (self.closed.load(.acquire) or (self.shutdown_requested and !is_shutdown_cmd)) {
            var cmd = command;
            cmd.deinit(self.allocator);
            return error.NativeWindowClosed;
        }

        if (is_shutdown_cmd) self.shutdown_requested = true;
        try self.queue.append(command);
    }
};

fn initOnCurrentThread(host: *Host) !void {
    const loaded = Symbols.loadFor(host.runtime_target) catch return error.NativeBackendUnavailable;
    host.symbols = loaded;
    errdefer {
        if (host.symbols) |*symbols| {
            symbols.deinit();
            host.symbols = null;
        }
    }

    const symbols = &host.symbols.?;
    symbols.initToolkit();

    const window_widget = symbols.newTopLevelWindow() orelse return error.NativeBackendUnavailable;
    var should_destroy_window = true;
    errdefer if (should_destroy_window) symbols.destroyWindow(window_widget);

    const webview_widget = symbols.webkit_web_view_new() orelse return error.NativeBackendUnavailable;
    const webview: *common.WebKitWebView = @ptrCast(webview_widget);

    const title_z = try host.allocator.dupeZ(u8, host.title);
    defer host.allocator.free(title_z);

    const window: *common.GtkWindow = @ptrCast(window_widget);
    symbols.gtk_window_set_title(window, title_z);

    const width: c_int = if (host.style.size) |size| @as(c_int, @intCast(size.width)) else default_width;
    const height: c_int = if (host.style.size) |size| @as(c_int, @intCast(size.height)) else default_height;
    symbols.gtk_window_set_default_size(window, width, height);

    const content_widget = symbols.addWindowChild(window_widget, webview_widget) orelse return error.NativeBackendUnavailable;

    host.window_widget = window_widget;
    host.content_widget = content_widget;
    host.webview = webview;
    host.ui_ready = true;
    host.shutdown_requested = false;
    host.closed.store(false, .release);

    applyStyleUiThread(host, host.style);
    connectWindowSignals(symbols, window_widget, host);

    symbols.showWindow(window_widget, content_widget);
    if (content_widget != webview_widget) {
        symbols.gtk_widget_show(webview_widget);
    }

    should_destroy_window = false;
}

pub fn runtimeAvailableFor(target: RuntimeTarget) bool {
    const cache_ptr = switch (target) {
        .webview => &probe_cache_webview,
        .webkitgtk_6 => &probe_cache_webkitgtk6,
    };
    const cached = @as(ProbeCache, @enumFromInt(cache_ptr.load(.acquire)));
    switch (cached) {
        .available => return true,
        .unavailable => return false,
        .unknown => {},
    }

    const available = blk: {
        if (!hasDisplaySession()) break :blk false;
        var symbols = Symbols.loadFor(target) catch break :blk false;
        symbols.deinit();
        break :blk true;
    };

    cache_ptr.store(
        @intFromEnum(if (available) ProbeCache.available else ProbeCache.unavailable),
        .release,
    );
    return available;
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

fn onDestroy(_: ?*anyopaque, data: ?*anyopaque) callconv(.c) void {
    const host = data orelse return;
    const typed: *Host = @ptrCast(@alignCast(host));

    typed.mutex.lock();
    typed.closed.store(true, .release);
    typed.ui_ready = false;
    typed.shutdown_requested = true;
    typed.window_widget = null;
    typed.content_widget = null;
    typed.webview = null;
    typed.mutex.unlock();
}

fn onRealize(widget: ?*anyopaque, data: ?*anyopaque) callconv(.c) void {
    const raw_widget = widget orelse return;
    const raw_host = data orelse return;
    const host: *Host = @ptrCast(@alignCast(raw_host));
    const window_widget: *common.GtkWidget = @ptrCast(@alignCast(raw_widget));

    host.mutex.lock();
    defer host.mutex.unlock();
    if (host.closed.load(.acquire) or host.shutdown_requested) return;
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
    if (host.closed.load(.acquire) or host.shutdown_requested) return;
    const symbols = host.symbols orelse return;

    if (allocation) |raw_alloc| {
        const alloc: *common.GtkAllocation = @ptrCast(@alignCast(raw_alloc));
        rounded_shape.applyRoundedWindowShape(&symbols, host.style.corner_radius, window_widget, alloc.width, alloc.height);
        return;
    }
    applyRoundedShape(&symbols, host.style.corner_radius, window_widget);
}

fn drainCommandsUiThread(host: *Host) void {
    // Swap queued work into a local batch so we keep lock hold-time short and
    // avoid O(n^2) ordered-removal when command bursts arrive.
    var batch = Queue.init(host.allocator);
    defer batch.deinit();

    while (true) {
        host.mutex.lock();
        if (host.queue.items.len == 0) {
            if (host.queue.capacity == 0 and batch.capacity > 0) {
                std.mem.swap(Queue, &host.queue, &batch);
            }
            host.mutex.unlock();
            break;
        }
        std.mem.swap(Queue, &host.queue, &batch);
        host.mutex.unlock();

        for (batch.items) |*cmd| {
            executeUiCommand(host, cmd);
            cmd.deinit(host.allocator);
        }
        batch.clearRetainingCapacity();
    }
}

fn executeUiCommand(host: *Host, command: *Command) void {
    host.mutex.lock();
    const is_closed = host.closed.load(.acquire);
    const symbols = host.symbols;
    const webview = host.webview;
    const window_widget = host.window_widget;
    host.mutex.unlock();

    const syms = symbols orelse return;
    if (is_closed and command.* != .shutdown) return;

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
            } else {
                host.mutex.lock();
                host.closed.store(true, .release);
                host.ui_ready = false;
                host.mutex.unlock();
            }
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
            host.shutdown_requested = true;
            symbols.destroyWindow(window_widget);
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

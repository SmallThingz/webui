const std = @import("std");
const builtin = @import("builtin");
const window_style_types = @import("../root/window_style.zig");
const objc = @import("macos_webview/bindings.zig");

const WindowStyle = window_style_types.WindowStyle;
const WindowControl = window_style_types.WindowControl;

const default_width: f64 = 980;
const default_height: f64 = 660;

const NSWindowStyleMaskTitled: u64 = 1 << 0;
const NSWindowStyleMaskClosable: u64 = 1 << 1;
const NSWindowStyleMaskMiniaturizable: u64 = 1 << 2;
const NSWindowStyleMaskResizable: u64 = 1 << 3;
const NSWindowStyleMaskBorderless: u64 = 0;

const NSBackingStoreBuffered: u64 = 2;
const NSApplicationActivationPolicyRegular: i64 = 0;
const NSEventMaskAny: u64 = std.math.maxInt(u64);

const NSViewWidthSizable: u64 = 1 << 1;
const NSViewHeightSizable: u64 = 1 << 4;

const ObjcBool = u8;

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

const NSPoint = extern struct {
    x: f64,
    y: f64,
};

const NSSize = extern struct {
    width: f64,
    height: f64,
};

const NSRect = extern struct {
    origin: NSPoint,
    size: NSSize,
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

    symbols: ?objc.Symbols = null,

    ns_app: ?*anyopaque = null,
    ns_window: ?*anyopaque = null,
    wk_webview: ?*anyopaque = null,

    explicit_hidden: bool = false,

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
    if (builtin.os.tag != .macos) return false;
    var symbols = objc.Symbols.load() catch return false;
    symbols.deinit();
    return true;
}

fn threadMain(host: *Host) void {
    const symbols = objc.Symbols.load() catch {
        failStartup(host, error.NativeBackendUnavailable);
        return;
    };

    host.mutex.lock();
    host.symbols = symbols;
    host.mutex.unlock();
    defer {
        host.mutex.lock();
        if (host.symbols) |*syms| syms.deinit();
        host.symbols = null;
        host.mutex.unlock();
    }

    const startup_pool = host.symbols.?.autorelease_pool_push();
    defer host.symbols.?.autorelease_pool_pop(startup_pool);

    if (!initializeApp(host)) {
        failStartup(host, error.NativeBackendUnavailable);
        return;
    }

    if (!createWindowAndWebView(host)) {
        failStartup(host, error.NativeBackendUnavailable);
        return;
    }

    host.mutex.lock();
    host.ui_ready = true;
    host.startup_done = true;
    host.cond.broadcast();
    host.mutex.unlock();

    var idle_ticks: usize = 0;
    while (true) {
        const syms = host.symbols orelse break;
        const pool = syms.autorelease_pool_push();

        var had_activity = false;

        drainCommandsUiThread(host, &had_activity);
        if (pumpEvents(host)) {
            had_activity = true;
        }

        if (windowUserClosed(host)) {
            host.mutex.lock();
            host.shutdown_requested = true;
            host.closed.store(true, .release);
            host.cond.broadcast();
            host.mutex.unlock();
        }

        host.mutex.lock();
        const stop = host.shutdown_requested;
        host.mutex.unlock();
        if (stop) {
            syms.autorelease_pool_pop(pool);
            break;
        }

        if (!had_activity) {
            idle_ticks += 1;
            if (idle_ticks > 5) {
                std.Thread.sleep(8 * std.time.ns_per_ms);
            }
        } else {
            idle_ticks = 0;
        }

        syms.autorelease_pool_pop(pool);
    }

    cleanupUiThread(host);
}

fn failStartup(host: *Host, err: anyerror) void {
    host.mutex.lock();
    defer host.mutex.unlock();

    host.startup_error = err;
    host.startup_done = true;
    host.ui_ready = false;
    host.closed.store(true, .release);
    host.cond.broadcast();
}

fn initializeApp(host: *Host) bool {
    const app_class = objcClass(host, "NSApplication") orelse return false;
    const app = msgSendId(host, app_class, sel(host, "sharedApplication"));
    if (app == null) return false;

    host.ns_app = app;

    msgSendVoidI64(host, app, sel(host, "setActivationPolicy:"), NSApplicationActivationPolicyRegular);
    msgSendVoid(host, app, sel(host, "finishLaunching"));
    msgSendVoidBool(host, app, sel(host, "activateIgnoringOtherApps:"), true);
    return true;
}

fn createWindowAndWebView(host: *Host) bool {
    const frame = styleRect(host.style);
    const style_mask = computeWindowStyleMask(host.style);

    const window_class = objcClass(host, "NSWindow") orelse return false;
    const window_alloc = msgSendId(host, window_class, sel(host, "alloc")) orelse return false;

    const window = msgSendIdRectU64U64Bool(
        host,
        window_alloc,
        sel(host, "initWithContentRect:styleMask:backing:defer:"),
        frame,
        style_mask,
        NSBackingStoreBuffered,
        false,
    ) orelse return false;

    host.ns_window = window;
    msgSendVoidBool(host, window, sel(host, "setReleasedWhenClosed:"), false);

    if (host.style.frameless) {
        msgSendVoidBool(host, window, sel(host, "setMovableByWindowBackground:"), true);
    }

    const title = nsString(host, host.title) orelse return false;
    msgSendVoidId(host, window, sel(host, "setTitle:"), title);

    const webview_class = objcClass(host, "WKWebView") orelse return false;
    const webview_alloc = msgSendId(host, webview_class, sel(host, "alloc")) orelse return false;
    const webview = msgSendIdRect(host, webview_alloc, sel(host, "initWithFrame:"), frame) orelse return false;

    host.wk_webview = webview;

    msgSendVoidU64(host, webview, sel(host, "setAutoresizingMask:"), NSViewWidthSizable | NSViewHeightSizable);

    const content_view = msgSendId(host, window, sel(host, "contentView")) orelse return false;
    msgSendVoidId(host, content_view, sel(host, "addSubview:"), webview);

    applyStyleUiThread(host, host.style);

    if (host.style.hidden) {
        host.explicit_hidden = true;
        msgSendVoidId(host, window, sel(host, "orderOut:"), null);
    } else {
        host.explicit_hidden = false;
        msgSendVoidId(host, window, sel(host, "makeKeyAndOrderFront:"), null);
    }

    return true;
}

fn cleanupUiThread(host: *Host) void {
    if (host.wk_webview) |webview| {
        msgSendVoid(host, webview, sel(host, "release"));
        host.wk_webview = null;
    }

    if (host.ns_window) |window| {
        msgSendVoidId(host, window, sel(host, "orderOut:"), null);
        msgSendVoid(host, window, sel(host, "close"));
        msgSendVoid(host, window, sel(host, "release"));
        host.ns_window = null;
    }

    host.mutex.lock();
    host.ui_ready = false;
    host.closed.store(true, .release);
    host.shutdown_requested = true;
    host.cond.broadcast();
    host.mutex.unlock();
}

fn drainCommandsUiThread(host: *Host, had_activity: *bool) void {
    while (true) {
        host.mutex.lock();
        if (host.queue.items.len == 0) {
            host.mutex.unlock();
            return;
        }
        var cmd = host.queue.orderedRemove(0);
        host.mutex.unlock();

        had_activity.* = true;
        executeCommandUiThread(host, &cmd);
        cmd.deinit(host.allocator);
    }
}

fn executeCommandUiThread(host: *Host, command: *Command) void {
    switch (command.*) {
        .navigate => |url| {
            _ = navigateUiThread(host, url);
        },
        .apply_style => |style| applyStyleUiThread(host, style),
        .control => |cmd| applyControlUiThread(host, cmd),
        .shutdown => {
            host.mutex.lock();
            host.shutdown_requested = true;
            host.closed.store(true, .release);
            host.cond.broadcast();
            host.mutex.unlock();
        },
    }
}

fn navigateUiThread(host: *Host, url: []const u8) bool {
    const webview = host.wk_webview orelse return false;

    const ns_url_str = nsString(host, url) orelse return false;
    const nsurl_class = objcClass(host, "NSURL") orelse return false;
    const nsurl = msgSendIdId(host, nsurl_class, sel(host, "URLWithString:"), ns_url_str) orelse return false;

    const request_class = objcClass(host, "NSURLRequest") orelse return false;
    const request = msgSendIdId(host, request_class, sel(host, "requestWithURL:"), nsurl) orelse return false;

    msgSendVoidId(host, webview, sel(host, "loadRequest:"), request);
    return true;
}

fn applyStyleUiThread(host: *Host, style: WindowStyle) void {
    host.style = style;

    const window = host.ns_window orelse return;

    msgSendVoidU64(host, window, sel(host, "setStyleMask:"), computeWindowStyleMask(style));

    if (style.size) |size| {
        const ns_size = NSSize{ .width = @floatFromInt(size.width), .height = @floatFromInt(size.height) };
        msgSendVoidSize(host, window, sel(host, "setContentSize:"), ns_size);
    }

    if (style.center) {
        msgSendVoid(host, window, sel(host, "center"));
    } else if (style.position) |pos| {
        msgSendVoidPoint(host, window, sel(host, "setFrameTopLeftPoint:"), .{ .x = @floatFromInt(pos.x), .y = @floatFromInt(pos.y) });
    }

    if (style.transparent) {
        const ns_color_class = objcClass(host, "NSColor") orelse return;
        const clear = msgSendId(host, ns_color_class, sel(host, "clearColor"));
        msgSendVoidBool(host, window, sel(host, "setOpaque:"), false);
        if (clear) |clear_color| msgSendVoidId(host, window, sel(host, "setBackgroundColor:"), clear_color);
        if (host.wk_webview) |webview| {
            msgSendVoidBool(host, webview, sel(host, "setOpaque:"), false);
        }
    } else {
        msgSendVoidBool(host, window, sel(host, "setOpaque:"), true);
    }

    applyCornerRadius(host, style.corner_radius);

    if (style.hidden) {
        host.explicit_hidden = true;
        msgSendVoidId(host, window, sel(host, "orderOut:"), null);
    } else {
        host.explicit_hidden = false;
        msgSendVoidId(host, window, sel(host, "makeKeyAndOrderFront:"), null);
    }
}

fn applyCornerRadius(host: *Host, radius: ?u16) void {
    const window = host.ns_window orelse return;
    const content_view = msgSendId(host, window, sel(host, "contentView")) orelse return;

    if (radius == null) {
        msgSendVoidBool(host, content_view, sel(host, "setWantsLayer:"), false);
        return;
    }

    msgSendVoidBool(host, content_view, sel(host, "setWantsLayer:"), true);
    const layer = msgSendId(host, content_view, sel(host, "layer")) orelse return;

    msgSendVoidF64(host, layer, sel(host, "setCornerRadius:"), @floatFromInt(radius.?));
    msgSendVoidBool(host, layer, sel(host, "setMasksToBounds:"), true);
}

fn applyControlUiThread(host: *Host, cmd: WindowControl) void {
    const window = host.ns_window orelse return;

    switch (cmd) {
        .minimize => {
            host.explicit_hidden = true;
            msgSendVoidId(host, window, sel(host, "miniaturize:"), null);
        },
        .maximize => {
            host.explicit_hidden = false;
            msgSendVoidId(host, window, sel(host, "zoom:"), null);
        },
        .restore => {
            host.explicit_hidden = false;
            msgSendVoidId(host, window, sel(host, "deminiaturize:"), null);
            msgSendVoidId(host, window, sel(host, "makeKeyAndOrderFront:"), null);
        },
        .close => {
            host.mutex.lock();
            host.shutdown_requested = true;
            host.closed.store(true, .release);
            host.cond.broadcast();
            host.mutex.unlock();
            msgSendVoid(host, window, sel(host, "close"));
        },
        .hide => {
            host.explicit_hidden = true;
            msgSendVoidId(host, window, sel(host, "orderOut:"), null);
        },
        .show => {
            host.explicit_hidden = false;
            msgSendVoidId(host, window, sel(host, "makeKeyAndOrderFront:"), null);
        },
    }
}

fn windowUserClosed(host: *Host) bool {
    if (host.explicit_hidden) return false;
    const window = host.ns_window orelse return false;
    const visible = msgSendBool(host, window, sel(host, "isVisible"));
    if (visible) return false;

    const miniaturized = msgSendBool(host, window, sel(host, "isMiniaturized"));
    return !miniaturized;
}

fn pumpEvents(host: *Host) bool {
    const app = host.ns_app orelse return false;

    const date_class = objcClass(host, "NSDate") orelse return false;
    const distant_past = msgSendId(host, date_class, sel(host, "distantPast")) orelse return false;

    const default_mode = nsString(host, "NSDefaultRunLoopMode") orelse return false;

    const event = msgSendIdU64IdIdBool(
        host,
        app,
        sel(host, "nextEventMatchingMask:untilDate:inMode:dequeue:"),
        NSEventMaskAny,
        distant_past,
        default_mode,
        true,
    );

    if (event == null) return false;

    msgSendVoidId(host, app, sel(host, "sendEvent:"), event);
    msgSendVoid(host, app, sel(host, "updateWindows"));
    return true;
}

fn styleRect(style: WindowStyle) NSRect {
    const width: f64 = if (style.size) |s| @floatFromInt(s.width) else default_width;
    const height: f64 = if (style.size) |s| @floatFromInt(s.height) else default_height;
    const x: f64 = if (style.position) |p| @floatFromInt(p.x) else 160;
    const y: f64 = if (style.position) |p| @floatFromInt(p.y) else 120;
    return .{
        .origin = .{ .x = x, .y = y },
        .size = .{ .width = width, .height = height },
    };
}

fn computeWindowStyleMask(style: WindowStyle) u64 {
    if (style.frameless) {
        var out: u64 = NSWindowStyleMaskBorderless;
        if (style.resizable) out |= NSWindowStyleMaskResizable;
        return out;
    }

    var out: u64 = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
    if (style.resizable) out |= NSWindowStyleMaskResizable;
    return out;
}

fn nsString(host: *Host, value: []const u8) ?*anyopaque {
    const cls = objcClass(host, "NSString") orelse return null;

    const z = host.allocator.dupeZ(u8, value) catch return null;
    defer host.allocator.free(z);

    return msgSendIdCString(host, cls, sel(host, "stringWithUTF8String:"), z.ptr);
}

fn objcClass(host: *Host, name: [*:0]const u8) ?*anyopaque {
    const syms = host.symbols orelse return null;
    return syms.objc_get_class(name);
}

fn sel(host: *Host, name: [*:0]const u8) objc.SEL {
    return host.symbols.?.sel_register_name(name);
}

fn asBool(value: bool) ObjcBool {
    return if (value) 1 else 0;
}

fn msgSendId(host: *Host, receiver: ?*anyopaque, selector: objc.SEL) ?*anyopaque {
    const Fn = *const fn (?*anyopaque, objc.SEL) callconv(.c) ?*anyopaque;
    const f: Fn = @ptrCast(@alignCast(host.symbols.?.objc_msg_send));
    return f(receiver, selector);
}

fn msgSendBool(host: *Host, receiver: ?*anyopaque, selector: objc.SEL) bool {
    const Fn = *const fn (?*anyopaque, objc.SEL) callconv(.c) ObjcBool;
    const f: Fn = @ptrCast(@alignCast(host.symbols.?.objc_msg_send));
    return f(receiver, selector) != 0;
}

fn msgSendVoid(host: *Host, receiver: ?*anyopaque, selector: objc.SEL) void {
    const Fn = *const fn (?*anyopaque, objc.SEL) callconv(.c) void;
    const f: Fn = @ptrCast(@alignCast(host.symbols.?.objc_msg_send));
    f(receiver, selector);
}

fn msgSendVoidBool(host: *Host, receiver: ?*anyopaque, selector: objc.SEL, value: bool) void {
    const Fn = *const fn (?*anyopaque, objc.SEL, ObjcBool) callconv(.c) void;
    const f: Fn = @ptrCast(@alignCast(host.symbols.?.objc_msg_send));
    f(receiver, selector, asBool(value));
}

fn msgSendVoidI64(host: *Host, receiver: ?*anyopaque, selector: objc.SEL, value: i64) void {
    const Fn = *const fn (?*anyopaque, objc.SEL, i64) callconv(.c) void;
    const f: Fn = @ptrCast(@alignCast(host.symbols.?.objc_msg_send));
    f(receiver, selector, value);
}

fn msgSendVoidU64(host: *Host, receiver: ?*anyopaque, selector: objc.SEL, value: u64) void {
    const Fn = *const fn (?*anyopaque, objc.SEL, u64) callconv(.c) void;
    const f: Fn = @ptrCast(@alignCast(host.symbols.?.objc_msg_send));
    f(receiver, selector, value);
}

fn msgSendVoidF64(host: *Host, receiver: ?*anyopaque, selector: objc.SEL, value: f64) void {
    const Fn = *const fn (?*anyopaque, objc.SEL, f64) callconv(.c) void;
    const f: Fn = @ptrCast(@alignCast(host.symbols.?.objc_msg_send));
    f(receiver, selector, value);
}

fn msgSendVoidId(host: *Host, receiver: ?*anyopaque, selector: objc.SEL, value: ?*anyopaque) void {
    const Fn = *const fn (?*anyopaque, objc.SEL, ?*anyopaque) callconv(.c) void;
    const f: Fn = @ptrCast(@alignCast(host.symbols.?.objc_msg_send));
    f(receiver, selector, value);
}

fn msgSendVoidPoint(host: *Host, receiver: ?*anyopaque, selector: objc.SEL, value: NSPoint) void {
    const Fn = *const fn (?*anyopaque, objc.SEL, NSPoint) callconv(.c) void;
    const f: Fn = @ptrCast(@alignCast(host.symbols.?.objc_msg_send));
    f(receiver, selector, value);
}

fn msgSendVoidSize(host: *Host, receiver: ?*anyopaque, selector: objc.SEL, value: NSSize) void {
    const Fn = *const fn (?*anyopaque, objc.SEL, NSSize) callconv(.c) void;
    const f: Fn = @ptrCast(@alignCast(host.symbols.?.objc_msg_send));
    f(receiver, selector, value);
}

fn msgSendIdId(host: *Host, receiver: ?*anyopaque, selector: objc.SEL, arg: ?*anyopaque) ?*anyopaque {
    const Fn = *const fn (?*anyopaque, objc.SEL, ?*anyopaque) callconv(.c) ?*anyopaque;
    const f: Fn = @ptrCast(@alignCast(host.symbols.?.objc_msg_send));
    return f(receiver, selector, arg);
}

fn msgSendIdCString(host: *Host, receiver: ?*anyopaque, selector: objc.SEL, arg: [*:0]const u8) ?*anyopaque {
    const Fn = *const fn (?*anyopaque, objc.SEL, [*:0]const u8) callconv(.c) ?*anyopaque;
    const f: Fn = @ptrCast(@alignCast(host.symbols.?.objc_msg_send));
    return f(receiver, selector, arg);
}

fn msgSendIdRect(host: *Host, receiver: ?*anyopaque, selector: objc.SEL, rect: NSRect) ?*anyopaque {
    const Fn = *const fn (?*anyopaque, objc.SEL, NSRect) callconv(.c) ?*anyopaque;
    const f: Fn = @ptrCast(@alignCast(host.symbols.?.objc_msg_send));
    return f(receiver, selector, rect);
}

fn msgSendIdRectU64U64Bool(
    host: *Host,
    receiver: ?*anyopaque,
    selector: objc.SEL,
    rect: NSRect,
    style_mask: u64,
    backing: u64,
    defer_flag: bool,
) ?*anyopaque {
    const Fn = *const fn (?*anyopaque, objc.SEL, NSRect, u64, u64, ObjcBool) callconv(.c) ?*anyopaque;
    const f: Fn = @ptrCast(@alignCast(host.symbols.?.objc_msg_send));
    return f(receiver, selector, rect, style_mask, backing, asBool(defer_flag));
}

fn msgSendIdU64IdIdBool(
    host: *Host,
    receiver: ?*anyopaque,
    selector: objc.SEL,
    mask: u64,
    date: ?*anyopaque,
    mode: ?*anyopaque,
    dequeue: bool,
) ?*anyopaque {
    const Fn = *const fn (?*anyopaque, objc.SEL, u64, ?*anyopaque, ?*anyopaque, ObjcBool) callconv(.c) ?*anyopaque;
    const f: Fn = @ptrCast(@alignCast(host.symbols.?.objc_msg_send));
    return f(receiver, selector, mask, date, mode, asBool(dequeue));
}

test "runtimeAvailable false on non-macos targets" {
    if (builtin.os.tag != .macos) {
        try std.testing.expect(!runtimeAvailable());
    }
}

test "computeWindowStyleMask follows frameless and resizable flags" {
    const frameless_fixed = computeWindowStyleMask(.{
        .frameless = true,
        .resizable = false,
    });
    try std.testing.expectEqual(@as(u64, NSWindowStyleMaskBorderless), frameless_fixed);

    const frameless_resizable = computeWindowStyleMask(.{
        .frameless = true,
        .resizable = true,
    });
    try std.testing.expect((frameless_resizable & NSWindowStyleMaskResizable) != 0);

    const classic_fixed = computeWindowStyleMask(.{
        .frameless = false,
        .resizable = false,
    });
    try std.testing.expect((classic_fixed & NSWindowStyleMaskTitled) != 0);
    try std.testing.expect((classic_fixed & NSWindowStyleMaskResizable) == 0);
}

test "styleRect uses explicit size and position when provided" {
    const rect = styleRect(.{
        .size = .{ .width = 1234, .height = 777 },
        .position = .{ .x = 42, .y = 84 },
    });
    try std.testing.expectEqual(@as(f64, 1234), rect.size.width);
    try std.testing.expectEqual(@as(f64, 777), rect.size.height);
    try std.testing.expectEqual(@as(f64, 42), rect.origin.x);
    try std.testing.expectEqual(@as(f64, 84), rect.origin.y);
}

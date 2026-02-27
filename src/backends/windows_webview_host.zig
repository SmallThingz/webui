const std = @import("std");
const builtin = @import("builtin");
const window_style_types = @import("../root/window_style.zig");
const wv2 = @import("windows_webview/bindings.zig");

const win = std.os.windows;

const WindowStyle = window_style_types.WindowStyle;
const WindowControl = window_style_types.WindowControl;

const default_width: i32 = 980;
const default_height: i32 = 660;
const wm_app_drain: u32 = 0x8000 + 41;

const WM_SIZE: u32 = 0x0005;
const WM_MOVE: u32 = 0x0003;
const WM_CLOSE: u32 = 0x0010;
const WM_DESTROY: u32 = 0x0002;
const WM_NCCREATE: u32 = 0x0081;
const WM_QUIT: u32 = 0x0012;

const PM_REMOVE: u32 = 0x0001;

const SW_HIDE: i32 = 0;
const SW_SHOW: i32 = 5;
const SW_MINIMIZE: i32 = 6;
const SW_MAXIMIZE: i32 = 3;
const SW_RESTORE: i32 = 9;

const CW_USEDEFAULT: i32 = @as(i32, @bitCast(@as(u32, 0x80000000)));

const WS_OVERLAPPED: u32 = 0x00000000;
const WS_POPUP: u32 = 0x80000000;
const WS_VISIBLE: u32 = 0x10000000;
const WS_THICKFRAME: u32 = 0x00040000;
const WS_CAPTION: u32 = 0x00C00000;
const WS_SYSMENU: u32 = 0x00080000;
const WS_MINIMIZEBOX: u32 = 0x00020000;
const WS_MAXIMIZEBOX: u32 = 0x00010000;
const WS_OVERLAPPEDWINDOW: u32 = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX;

const WS_EX_LAYERED: u32 = 0x00080000;

const GWL_STYLE: i32 = -16;
const GWL_EXSTYLE: i32 = -20;
const GWLP_USERDATA: i32 = -21;

const SWP_NOSIZE: u32 = 0x0001;
const SWP_NOMOVE: u32 = 0x0002;
const SWP_NOZORDER: u32 = 0x0004;
const SWP_FRAMECHANGED: u32 = 0x0020;

const LWA_ALPHA: u32 = 0x00000002;

const COINIT_APARTMENTTHREADED: u32 = 0x2;

const window_class_name = std.unicode.utf8ToUtf16LeStringLiteral("WebUiZigHost");

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

const POINT = extern struct {
    x: i32,
    y: i32,
};

const MSG = extern struct {
    hwnd: ?win.HWND,
    message: u32,
    wParam: win.WPARAM,
    lParam: win.LPARAM,
    time: u32,
    pt: POINT,
    lPrivate: u32,
};

const CREATESTRUCTW = extern struct {
    lpCreateParams: ?*anyopaque,
    hInstance: ?win.HINSTANCE,
    hMenu: ?*anyopaque,
    hwndParent: ?win.HWND,
    cy: i32,
    cx: i32,
    y: i32,
    x: i32,
    style: i32,
    lpszName: ?win.LPCWSTR,
    lpszClass: ?win.LPCWSTR,
    dwExStyle: u32,
};

const WNDPROC = *const fn (win.HWND, u32, win.WPARAM, win.LPARAM) callconv(.winapi) win.LRESULT;

const WNDCLASSEXW = extern struct {
    cbSize: u32,
    style: u32,
    lpfnWndProc: ?WNDPROC,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: ?win.HINSTANCE,
    hIcon: ?win.HICON,
    hCursor: ?win.HCURSOR,
    hbrBackground: ?win.HBRUSH,
    lpszMenuName: ?win.LPCWSTR,
    lpszClassName: win.LPCWSTR,
    hIconSm: ?win.HICON,
};

extern "ole32" fn CoInitializeEx(?*anyopaque, u32) callconv(.winapi) wv2.HRESULT;
extern "ole32" fn CoUninitialize() callconv(.winapi) void;
extern "ole32" fn CoTaskMemFree(?*anyopaque) callconv(.winapi) void;

extern "user32" fn RegisterClassExW(*const WNDCLASSEXW) callconv(.winapi) win.ATOM;
extern "user32" fn UnregisterClassW(win.LPCWSTR, ?win.HINSTANCE) callconv(.winapi) win.BOOL;
extern "user32" fn CreateWindowExW(
    u32,
    win.LPCWSTR,
    win.LPCWSTR,
    u32,
    i32,
    i32,
    i32,
    i32,
    ?win.HWND,
    ?*anyopaque,
    ?win.HINSTANCE,
    ?*anyopaque,
) callconv(.winapi) ?win.HWND;
extern "user32" fn DefWindowProcW(win.HWND, u32, win.WPARAM, win.LPARAM) callconv(.winapi) win.LRESULT;
extern "user32" fn DestroyWindow(win.HWND) callconv(.winapi) win.BOOL;
extern "user32" fn PostQuitMessage(i32) callconv(.winapi) void;
extern "user32" fn ShowWindow(win.HWND, i32) callconv(.winapi) win.BOOL;
extern "user32" fn UpdateWindow(win.HWND) callconv(.winapi) win.BOOL;
extern "user32" fn PeekMessageW(*MSG, ?win.HWND, u32, u32, u32) callconv(.winapi) win.BOOL;
extern "user32" fn TranslateMessage(*const MSG) callconv(.winapi) win.BOOL;
extern "user32" fn DispatchMessageW(*const MSG) callconv(.winapi) win.LRESULT;
extern "user32" fn GetClientRect(win.HWND, *win.RECT) callconv(.winapi) win.BOOL;
extern "user32" fn SetWindowPos(win.HWND, ?win.HWND, i32, i32, i32, i32, u32) callconv(.winapi) win.BOOL;
extern "user32" fn SetWindowLongPtrW(win.HWND, i32, win.LONG_PTR) callconv(.winapi) win.LONG_PTR;
extern "user32" fn GetWindowLongPtrW(win.HWND, i32) callconv(.winapi) win.LONG_PTR;
extern "user32" fn SetWindowLongW(win.HWND, i32, i32) callconv(.winapi) i32;
extern "user32" fn GetWindowLongW(win.HWND, i32) callconv(.winapi) i32;
extern "user32" fn SetLayeredWindowAttributes(win.HWND, u32, u8, u32) callconv(.winapi) win.BOOL;
extern "user32" fn PostMessageW(win.HWND, u32, win.WPARAM, win.LPARAM) callconv(.winapi) win.BOOL;
extern "user32" fn SetWindowTextW(win.HWND, win.LPCWSTR) callconv(.winapi) win.BOOL;

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

    instance: ?win.HINSTANCE = null,
    class_registered: bool = false,
    hwnd: ?win.HWND = null,

    symbols: ?wv2.Symbols = null,
    com_initialized: bool = false,

    environment: ?*wv2.ICoreWebView2Environment = null,
    controller: ?*wv2.ICoreWebView2Controller = null,
    webview: ?*wv2.ICoreWebView2 = null,

    pending_url: ?[]u8 = null,

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
        if (self.pending_url) |url| {
            self.allocator.free(url);
            self.pending_url = null;
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

        if (self.closed.load(.acquire) or self.shutdown_requested) {
            var cmd = command;
            cmd.deinit(self.allocator);
            return error.NativeWindowClosed;
        }

        try self.queue.append(command);
        if (self.hwnd) |hwnd| {
            _ = PostMessageW(hwnd, wm_app_drain, 0, 0);
        }
        self.cond.signal();
    }
};

pub fn runtimeAvailable() bool {
    if (builtin.os.tag != .windows) return false;
    var symbols = wv2.Symbols.load() catch return false;
    symbols.deinit();
    return true;
}

fn threadMain(host: *Host) void {
    if (CoInitializeEx(null, COINIT_APARTMENTTHREADED) < 0) {
        failStartup(host, error.NativeBackendUnavailable);
        return;
    }
    host.com_initialized = true;
    defer CoUninitialize();

    const symbols = wv2.Symbols.load() catch {
        failStartup(host, error.NativeBackendUnavailable);
        return;
    };

    host.mutex.lock();
    host.symbols = symbols;
    host.mutex.unlock();
    defer {
        host.mutex.lock();
        if (host.symbols) |*owned| owned.deinit();
        host.symbols = null;
        host.mutex.unlock();
    }

    if (std.os.windows.kernel32.GetModuleHandleW(null)) |module_handle| {
        host.instance = @ptrCast(module_handle);
    } else {
        host.instance = null;
    }

    if (!registerWindowClass(host)) {
        failStartup(host, error.NativeBackendUnavailable);
        return;
    }
    defer unregisterWindowClass(host);

    const hwnd = createNativeWindow(host) orelse {
        failStartup(host, error.NativeBackendUnavailable);
        return;
    };

    host.mutex.lock();
    host.hwnd = hwnd;
    host.ui_ready = true;
    host.startup_done = true;
    host.cond.broadcast();
    host.mutex.unlock();

    _ = createWebViewEnvironment(host);

    if (host.style.hidden) {
        _ = ShowWindow(hwnd, SW_HIDE);
    } else {
        _ = ShowWindow(hwnd, SW_SHOW);
        _ = UpdateWindow(hwnd);
    }

    var msg: MSG = undefined;
    while (true) {
        var had_activity = false;

        while (PeekMessageW(&msg, null, 0, 0, PM_REMOVE) != 0) {
            had_activity = true;
            if (msg.message == WM_QUIT) {
                host.mutex.lock();
                host.shutdown_requested = true;
                host.closed.store(true, .release);
                host.mutex.unlock();
                break;
            }
            _ = TranslateMessage(&msg);
            _ = DispatchMessageW(&msg);
        }

        drainCommandsUiThread(host, &had_activity);

        host.mutex.lock();
        const stop = host.shutdown_requested;
        host.mutex.unlock();
        if (stop) break;

        if (!had_activity) std.Thread.sleep(8 * std.time.ns_per_ms);
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

fn registerWindowClass(host: *Host) bool {
    const wc = WNDCLASSEXW{
        .cbSize = @sizeOf(WNDCLASSEXW),
        .style = 0,
        .lpfnWndProc = wndProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = host.instance,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = window_class_name,
        .hIconSm = null,
    };

    if (RegisterClassExW(&wc) == 0) return false;
    host.class_registered = true;
    return true;
}

fn unregisterWindowClass(host: *Host) void {
    if (!host.class_registered) return;
    _ = UnregisterClassW(window_class_name, host.instance);
    host.class_registered = false;
}

fn createNativeWindow(host: *Host) ?win.HWND {
    const title_w = std.unicode.utf8ToUtf16LeAllocZ(host.allocator, host.title) catch return null;
    defer host.allocator.free(title_w);

    const style_bits = computeWindowStyle(host.style);

    const width = if (host.style.size) |size| @as(i32, @intCast(size.width)) else default_width;
    const height = if (host.style.size) |size| @as(i32, @intCast(size.height)) else default_height;
    const x = if (host.style.position) |p| p.x else CW_USEDEFAULT;
    const y = if (host.style.position) |p| p.y else CW_USEDEFAULT;

    const hwnd = CreateWindowExW(
        0,
        window_class_name,
        title_w.ptr,
        style_bits,
        x,
        y,
        width,
        height,
        null,
        null,
        host.instance,
        host,
    ) orelse return null;

    applyStyleUiThread(host, host.style);
    return hwnd;
}

fn cleanupUiThread(host: *Host) void {
    const hwnd = host.hwnd;
    host.hwnd = null;

    if (hwnd) |handle| {
        _ = DestroyWindow(handle);
    }

    if (host.webview) |webview| {
        _ = webview.lpVtbl.Release(webview);
        host.webview = null;
    }

    if (host.controller) |controller| {
        _ = controller.lpVtbl.Close(controller);
        _ = controller.lpVtbl.Release(controller);
        host.controller = null;
    }

    if (host.environment) |environment| {
        _ = environment.lpVtbl.Release(environment);
        host.environment = null;
    }

    host.mutex.lock();
    if (host.pending_url) |url| {
        host.allocator.free(url);
        host.pending_url = null;
    }
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
            navigateUiThread(host, url) catch {};
        },
        .apply_style => |style| applyStyleUiThread(host, style),
        .control => |cmd| applyControlUiThread(host, cmd),
        .shutdown => {
            host.mutex.lock();
            host.shutdown_requested = true;
            host.closed.store(true, .release);
            host.mutex.unlock();
            if (host.hwnd) |hwnd| {
                _ = DestroyWindow(hwnd);
            }
            PostQuitMessage(0);
        },
    }
}

fn navigateUiThread(host: *Host, url: []const u8) !void {
    if (host.webview) |webview| {
        const url_w = try std.unicode.utf8ToUtf16LeAllocZ(host.allocator, url);
        defer host.allocator.free(url_w);

        const hr = webview.lpVtbl.Navigate(webview, url_w.ptr);
        if (!wv2.succeeded(hr)) return error.NativeBackendUnavailable;
        return;
    }

    if (host.pending_url) |old| host.allocator.free(old);
    host.pending_url = try host.allocator.dupe(u8, url);
}

fn applyStyleUiThread(host: *Host, style: WindowStyle) void {
    host.style = style;
    const hwnd = host.hwnd orelse return;

    const style_bits = computeWindowStyle(style);
    _ = SetWindowLongW(hwnd, GWL_STYLE, @as(i32, @bitCast(style_bits)));

    const ex_before = @as(u32, @bitCast(@as(i32, @truncate(GetWindowLongW(hwnd, GWL_EXSTYLE)))));
    var ex_after = ex_before;
    if (style.transparent) {
        ex_after |= WS_EX_LAYERED;
    } else {
        ex_after &= ~WS_EX_LAYERED;
    }
    _ = SetWindowLongW(hwnd, GWL_EXSTYLE, @as(i32, @bitCast(ex_after)));

    if (style.transparent) {
        _ = SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);
    }

    _ = SetWindowPos(hwnd, null, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);

    if (style.size) |size| {
        _ = SetWindowPos(hwnd, null, 0, 0, @as(i32, @intCast(size.width)), @as(i32, @intCast(size.height)), SWP_NOMOVE | SWP_NOZORDER);
    }
    if (style.position) |pos| {
        _ = SetWindowPos(hwnd, null, pos.x, pos.y, 0, 0, SWP_NOSIZE | SWP_NOZORDER);
    }

    if (style.hidden) {
        _ = ShowWindow(hwnd, SW_HIDE);
    } else {
        _ = ShowWindow(hwnd, SW_SHOW);
    }

    updateControllerBounds(host);
}

fn applyControlUiThread(host: *Host, cmd: WindowControl) void {
    const hwnd = host.hwnd orelse return;

    switch (cmd) {
        .minimize => {
            _ = ShowWindow(hwnd, SW_MINIMIZE);
        },
        .maximize => {
            _ = ShowWindow(hwnd, SW_MAXIMIZE);
        },
        .restore => {
            _ = ShowWindow(hwnd, SW_RESTORE);
        },
        .close => {
            host.mutex.lock();
            host.shutdown_requested = true;
            host.closed.store(true, .release);
            host.mutex.unlock();
            _ = DestroyWindow(hwnd);
            PostQuitMessage(0);
        },
        .hide => {
            _ = ShowWindow(hwnd, SW_HIDE);
        },
        .show => {
            _ = ShowWindow(hwnd, SW_SHOW);
        },
    }

    updateControllerBounds(host);
}

fn computeWindowStyle(style: WindowStyle) u32 {
    if (style.frameless) {
        var out: u32 = WS_POPUP | WS_VISIBLE;
        if (style.resizable) out |= WS_THICKFRAME;
        return out;
    }

    var out: u32 = WS_OVERLAPPEDWINDOW;
    if (!style.resizable) {
        out &= ~WS_THICKFRAME;
        out &= ~WS_MAXIMIZEBOX;
    }
    return out;
}

fn createWebViewEnvironment(host: *Host) bool {
    const symbols = host.symbols orelse return false;

    var env_handler = host.allocator.create(EnvironmentCompletedHandler) catch return false;
    env_handler.* = .{
        .iface = .{ .lpVtbl = &environment_completed_handler_vtbl },
        .refs = std.atomic.Value(u32).init(1),
        .host = host,
    };

    const hr = symbols.create_environment(null, null, null, &env_handler.iface);
    if (!wv2.succeeded(hr)) {
        _ = environmentHandlerRelease(&env_handler.iface);
        return false;
    }
    _ = environmentHandlerRelease(&env_handler.iface);
    return true;
}

fn updateControllerBounds(host: *Host) void {
    const hwnd = host.hwnd orelse return;
    const controller = host.controller orelse return;

    var rect: win.RECT = undefined;
    if (GetClientRect(hwnd, &rect) == 0) return;
    _ = controller.lpVtbl.put_Bounds(controller, rect);
}

const EnvironmentCompletedHandler = extern struct {
    iface: wv2.ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler,
    refs: std.atomic.Value(u32),
    host: *Host,
};

const ControllerCompletedHandler = extern struct {
    iface: wv2.ICoreWebView2CreateCoreWebView2ControllerCompletedHandler,
    refs: std.atomic.Value(u32),
    host: *Host,
};

const TitleChangedHandler = extern struct {
    iface: wv2.ICoreWebView2DocumentTitleChangedEventHandler,
    refs: std.atomic.Value(u32),
    host: *Host,
};

const environment_completed_handler_vtbl = wv2.ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl{
    .QueryInterface = environmentHandlerQueryInterface,
    .AddRef = environmentHandlerAddRef,
    .Release = environmentHandlerRelease,
    .Invoke = environmentHandlerInvoke,
};

const controller_completed_handler_vtbl = wv2.ICoreWebView2CreateCoreWebView2ControllerCompletedHandlerVtbl{
    .QueryInterface = controllerHandlerQueryInterface,
    .AddRef = controllerHandlerAddRef,
    .Release = controllerHandlerRelease,
    .Invoke = controllerHandlerInvoke,
};

const title_changed_handler_vtbl = wv2.ICoreWebView2DocumentTitleChangedEventHandlerVtbl{
    .QueryInterface = titleHandlerQueryInterface,
    .AddRef = titleHandlerAddRef,
    .Release = titleHandlerRelease,
    .Invoke = titleHandlerInvoke,
};

fn environmentHandlerQueryInterface(
    self: *wv2.ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler,
    _: *const win.GUID,
    out: *?*anyopaque,
) callconv(.winapi) wv2.HRESULT {
    out.* = self;
    _ = environmentHandlerAddRef(self);
    return win.S_OK;
}

fn environmentHandlerAddRef(self: *wv2.ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler) callconv(.winapi) u32 {
    const handler: *EnvironmentCompletedHandler = @fieldParentPtr("iface", self);
    return handler.refs.fetchAdd(1, .acq_rel) + 1;
}

fn environmentHandlerRelease(self: *wv2.ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler) callconv(.winapi) u32 {
    const handler: *EnvironmentCompletedHandler = @fieldParentPtr("iface", self);
    const refs = handler.refs.fetchSub(1, .acq_rel) - 1;
    if (refs == 0) {
        handler.host.allocator.destroy(handler);
    }
    return refs;
}

fn environmentHandlerInvoke(
    self: *wv2.ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler,
    error_code: wv2.HRESULT,
    created_environment: ?*wv2.ICoreWebView2Environment,
) callconv(.winapi) wv2.HRESULT {
    const handler: *EnvironmentCompletedHandler = @fieldParentPtr("iface", self);
    const host = handler.host;

    if (!wv2.succeeded(error_code) or created_environment == null) {
        host.mutex.lock();
        host.startup_error = error.NativeBackendUnavailable;
        host.shutdown_requested = true;
        host.closed.store(true, .release);
        host.cond.broadcast();
        host.mutex.unlock();
        return win.S_OK;
    }

    const environment = created_environment.?;
    _ = environment.lpVtbl.AddRef(environment);
    host.environment = environment;

    var controller_handler = host.allocator.create(ControllerCompletedHandler) catch return win.S_OK;
    controller_handler.* = .{
        .iface = .{ .lpVtbl = &controller_completed_handler_vtbl },
        .refs = std.atomic.Value(u32).init(1),
        .host = host,
    };

    const hwnd = host.hwnd orelse {
        _ = controllerHandlerRelease(&controller_handler.iface);
        return win.S_OK;
    };

    const hr = environment.lpVtbl.CreateCoreWebView2Controller(environment, hwnd, &controller_handler.iface);
    if (!wv2.succeeded(hr)) {
        _ = controllerHandlerRelease(&controller_handler.iface);
    }

    _ = controllerHandlerRelease(&controller_handler.iface);
    return win.S_OK;
}

fn controllerHandlerQueryInterface(
    self: *wv2.ICoreWebView2CreateCoreWebView2ControllerCompletedHandler,
    _: *const win.GUID,
    out: *?*anyopaque,
) callconv(.winapi) wv2.HRESULT {
    out.* = self;
    _ = controllerHandlerAddRef(self);
    return win.S_OK;
}

fn controllerHandlerAddRef(self: *wv2.ICoreWebView2CreateCoreWebView2ControllerCompletedHandler) callconv(.winapi) u32 {
    const handler: *ControllerCompletedHandler = @fieldParentPtr("iface", self);
    return handler.refs.fetchAdd(1, .acq_rel) + 1;
}

fn controllerHandlerRelease(self: *wv2.ICoreWebView2CreateCoreWebView2ControllerCompletedHandler) callconv(.winapi) u32 {
    const handler: *ControllerCompletedHandler = @fieldParentPtr("iface", self);
    const refs = handler.refs.fetchSub(1, .acq_rel) - 1;
    if (refs == 0) {
        handler.host.allocator.destroy(handler);
    }
    return refs;
}

fn controllerHandlerInvoke(
    self: *wv2.ICoreWebView2CreateCoreWebView2ControllerCompletedHandler,
    error_code: wv2.HRESULT,
    created_controller: ?*wv2.ICoreWebView2Controller,
) callconv(.winapi) wv2.HRESULT {
    const handler: *ControllerCompletedHandler = @fieldParentPtr("iface", self);
    const host = handler.host;

    if (!wv2.succeeded(error_code) or created_controller == null) {
        host.mutex.lock();
        host.startup_error = error.NativeBackendUnavailable;
        host.shutdown_requested = true;
        host.closed.store(true, .release);
        host.cond.broadcast();
        host.mutex.unlock();
        return win.S_OK;
    }

    const controller = created_controller.?;
    _ = controller.lpVtbl.AddRef(controller);
    host.controller = controller;

    var webview: ?*wv2.ICoreWebView2 = null;
    if (wv2.succeeded(controller.lpVtbl.get_CoreWebView2(controller, &webview))) {
        if (webview) |core| {
            _ = core.lpVtbl.AddRef(core);
            host.webview = core;
            configureWebViewSettings(core);
            attachTitleHandler(host, core);
        }
    }

    updateControllerBounds(host);

    if (host.pending_url) |pending| {
        _ = navigateUiThread(host, pending) catch {};
        host.allocator.free(pending);
        host.pending_url = null;
    }

    return win.S_OK;
}

fn configureWebViewSettings(webview: *wv2.ICoreWebView2) void {
    var settings: ?*wv2.ICoreWebView2Settings = null;
    if (!wv2.succeeded(webview.lpVtbl.get_Settings(webview, &settings))) return;
    const s = settings orelse return;
    defer _ = s.lpVtbl.Release(s);

    _ = s.lpVtbl.put_IsScriptEnabled(s, 1);
    _ = s.lpVtbl.put_IsWebMessageEnabled(s, 1);
    _ = s.lpVtbl.put_AreDefaultScriptDialogsEnabled(s, 1);
    _ = s.lpVtbl.put_AreDevToolsEnabled(s, if (builtin.mode == .Debug) 1 else 0);
}

fn attachTitleHandler(host: *Host, webview: *wv2.ICoreWebView2) void {
    var handler = host.allocator.create(TitleChangedHandler) catch return;
    handler.* = .{
        .iface = .{ .lpVtbl = &title_changed_handler_vtbl },
        .refs = std.atomic.Value(u32).init(1),
        .host = host,
    };

    var token: wv2.EventRegistrationToken = .{ .value = 0 };
    const hr = webview.lpVtbl.add_DocumentTitleChanged(webview, &handler.iface, &token);
    if (!wv2.succeeded(hr)) {
        _ = titleHandlerRelease(&handler.iface);
        return;
    }
    _ = titleHandlerRelease(&handler.iface);
}

fn titleHandlerQueryInterface(
    self: *wv2.ICoreWebView2DocumentTitleChangedEventHandler,
    _: *const win.GUID,
    out: *?*anyopaque,
) callconv(.winapi) wv2.HRESULT {
    out.* = self;
    _ = titleHandlerAddRef(self);
    return win.S_OK;
}

fn titleHandlerAddRef(self: *wv2.ICoreWebView2DocumentTitleChangedEventHandler) callconv(.winapi) u32 {
    const handler: *TitleChangedHandler = @fieldParentPtr("iface", self);
    return handler.refs.fetchAdd(1, .acq_rel) + 1;
}

fn titleHandlerRelease(self: *wv2.ICoreWebView2DocumentTitleChangedEventHandler) callconv(.winapi) u32 {
    const handler: *TitleChangedHandler = @fieldParentPtr("iface", self);
    const refs = handler.refs.fetchSub(1, .acq_rel) - 1;
    if (refs == 0) {
        handler.host.allocator.destroy(handler);
    }
    return refs;
}

fn titleHandlerInvoke(
    self: *wv2.ICoreWebView2DocumentTitleChangedEventHandler,
    sender: ?*wv2.ICoreWebView2,
    _: ?*wv2.IUnknown,
) callconv(.winapi) wv2.HRESULT {
    const handler: *TitleChangedHandler = @fieldParentPtr("iface", self);
    const host = handler.host;
    _ = sender;

    const webview = host.webview orelse return win.S_OK;

    var raw_title: ?win.PWSTR = null;
    if (!wv2.succeeded(webview.lpVtbl.get_DocumentTitle(webview, &raw_title))) return win.S_OK;
    const title_ptr = raw_title orelse return win.S_OK;
    defer CoTaskMemFree(title_ptr);

    if (host.hwnd) |hwnd| {
        _ = SetWindowTextW(hwnd, title_ptr);
    }

    return win.S_OK;
}

fn wndProc(hwnd: win.HWND, msg: u32, wparam: win.WPARAM, lparam: win.LPARAM) callconv(.winapi) win.LRESULT {
    if (msg == WM_NCCREATE) {
        const create_struct: *const CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));
        if (create_struct.lpCreateParams) |param| {
            _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, @as(win.LONG_PTR, @intCast(@intFromPtr(param))));
        }
    }

    const user_data = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
    const host: ?*Host = if (user_data == 0) null else @ptrFromInt(@as(usize, @intCast(user_data)));

    switch (msg) {
        WM_SIZE => {
            if (host) |h| updateControllerBounds(h);
            return 0;
        },
        WM_MOVE => {
            if (host) |h| updateControllerBounds(h);
            return 0;
        },
        WM_CLOSE => {
            if (host) |h| {
                h.mutex.lock();
                h.shutdown_requested = true;
                h.closed.store(true, .release);
                h.cond.broadcast();
                h.mutex.unlock();
            }
            _ = DestroyWindow(hwnd);
            return 0;
        },
        WM_DESTROY => {
            PostQuitMessage(0);
            return 0;
        },
        wm_app_drain => {
            return 0;
        },
        else => {},
    }

    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

test "runtimeAvailable false on non-windows targets" {
    if (builtin.os.tag != .windows) {
        try std.testing.expect(!runtimeAvailable());
    }
}

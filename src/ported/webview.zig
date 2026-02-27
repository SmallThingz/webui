const std = @import("std");
const builtin = @import("builtin");

const style_types = @import("../root/window_style.zig");
const browser_discovery = @import("browser_discovery.zig");
const browser_host = switch (builtin.os.tag) {
    .linux => @import("../backends/linux_browser_host.zig"),
    .windows => @import("../backends/windows_browser_host.zig"),
    .macos => @import("../backends/macos_browser_host.zig"),
    else => @compileError("Unsupported Backend"),
};
const platform_webview_host = switch (builtin.os.tag) {
    .linux => @import("../backends/linux_webview_host.zig"),
    .windows => @import("../backends/windows_webview_host.zig"),
    .macos => @import("../backends/macos_webview_host.zig"),
    else => @compileError("Unsupported Backend"),
};

pub const WindowContent = union(enum) {
    html: []const u8,
    file: []const u8,
    url: []const u8,
};

pub const NativeBackend = switch (builtin.os.tag) {
    .linux, .windows, .macos => PlatformWebView,
    else => @compileError("Unsupported Backend"),
};

test "native backend selects platform or none" {
    const native = NativeBackend.init(true);
    const fallback = NativeBackend.init(false);
    try std.testing.expect(native.isNative());
    try std.testing.expect(!fallback.isNative());
}

pub const PlatformWebView = struct {
    native_enabled: bool = false,
    window_id: usize = 0,
    title: []const u8 = "",
    style: style_types.WindowStyle = .{},
    hidden: bool = false,
    maximized: bool = false,
    native_host_ready: bool = false,
    host: ?*platform_webview_host.Host = null,
    browser_kind: ?browser_discovery.BrowserKind = null,
    browser_pid: ?i64 = null,
    browser_is_child: bool = false,

    pub fn init(enable_native: bool) PlatformWebView {
        return .{ .native_enabled = enable_native };
    }

    pub fn deinit(self: *PlatformWebView) void {
        if (self.host) |host| {
            host.deinit();
            self.host = null;
        }
        self.native_host_ready = false;
        self.browser_kind = null;
        self.browser_pid = null;
        self.browser_is_child = false;
    }

    pub fn isNative(self: *const PlatformWebView) bool {
        return self.native_enabled;
    }

    pub fn isReady(self: *const PlatformWebView) bool {
        if (!self.native_host_ready) return false;
        if (self.host) |host| return host.isReady();
        return false;
    }

    pub fn createWindow(self: *PlatformWebView, window_id: usize, title: []const u8, style: style_types.WindowStyle) !void {
        self.window_id = window_id;
        self.title = title;
        self.style = style;

        if (!self.native_enabled) return;
        if (builtin.is_test) {
            self.native_host_ready = false;
            return;
        }

        if (self.host == null) {
            self.host = platform_webview_host.Host.start(std.heap.page_allocator, title, style) catch {
                self.native_host_ready = false;
                return error.NativeBackendUnavailable;
            };
        }
        if (self.host) |host| {
            try host.applyStyle(style);
            self.native_host_ready = host.isReady();
            return;
        }
        self.native_host_ready = false;
        return error.NativeBackendUnavailable;
    }

    pub fn showContent(self: *PlatformWebView, content: anytype) !void {
        const Content = @TypeOf(content);
        if (@hasField(Content, "url")) {
            try self.navigate(@field(content, "url"));
            return;
        }
        return error.UnsupportedWindowContent;
    }

    pub fn attachBrowserProcess(self: *PlatformWebView, kind: ?browser_discovery.BrowserKind, pid: ?i64, is_child_process: bool) void {
        self.browser_kind = kind;
        self.browser_pid = pid;
        self.browser_is_child = is_child_process;
        if (self.host) |host| {
            self.native_host_ready = host.isReady();
        } else {
            self.native_host_ready = false;
        }
    }

    pub fn navigate(self: *PlatformWebView, url: []const u8) !void {
        if (!self.native_host_ready) return error.NativeBackendUnavailable;
        const host = self.host orelse return error.NativeBackendUnavailable;
        try host.navigate(url);
    }

    pub fn applyStyle(self: *PlatformWebView, style: style_types.WindowStyle) !void {
        self.style = style;
        if (!self.native_host_ready) return;
        const host = self.host orelse return;
        try host.applyStyle(style);
    }

    pub fn control(self: *PlatformWebView, cmd: style_types.WindowControl) !void {
        if (self.native_host_ready) {
            const host = self.host orelse return error.NativeBackendUnavailable;
            try host.control(cmd);
            switch (cmd) {
                .close => self.native_host_ready = false,
                .hide, .minimize => self.hidden = true,
                .show => self.hidden = false,
                .maximize => self.maximized = true,
                .restore => {
                    self.maximized = false;
                    self.hidden = false;
                },
            }
            return;
        }

        if (!self.browser_is_child) return error.UnsupportedWindowControl;
        const pid = self.browser_pid orelse return error.UnsupportedWindowControl;
        if (!browser_host.controlWindow(std.heap.page_allocator, pid, cmd)) return error.UnsupportedWindowControl;

        switch (cmd) {
            .close, .hide, .minimize => self.hidden = true,
            .show => self.hidden = false,
            .maximize => self.maximized = true,
            .restore => {
                self.maximized = false;
                self.hidden = false;
            },
        }
    }

    pub fn pumpEvents(self: *PlatformWebView) !void {
        if (self.host) |host| {
            if (host.isClosed()) {
                self.native_host_ready = false;
                return error.NativeWindowClosed;
            }
        }
    }

    pub fn destroyWindow(self: *PlatformWebView) void {
        if (self.host) |host| {
            host.deinit();
            self.host = null;
        }
        self.native_host_ready = false;
        self.browser_kind = null;
        self.browser_pid = null;
        self.browser_is_child = false;
    }

    pub fn capabilities(self: *const PlatformWebView) []const style_types.WindowCapability {
        if (self.native_host_ready and self.host != null) {
            return &.{
                .native_frameless,
                .native_transparency,
                .native_corner_radius,
                .native_positioning,
                .native_minmax,
                .native_icon,
                .native_kiosk,
            };
        }
        return &.{};
    }

    test "platform backend capabilities require host readiness" {
        var backend: PlatformWebView = .{};
        try std.testing.expectEqual(@as(usize, 0), backend.capabilities().len);

        backend.attachBrowserProcess(.chrome, 1234, true);
        try std.testing.expectEqual(@as(usize, 0), backend.capabilities().len);
    }

    test "platform backend control requires child-owned browser process" {
        var backend: PlatformWebView = .{};
        backend.attachBrowserProcess(.chrome, 1234, false);
        try std.testing.expectError(error.UnsupportedWindowControl, backend.control(.maximize));
    }
};

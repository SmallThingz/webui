const std = @import("std");
const builtin = @import("builtin");
const style_types = @import("../root/window_style.zig");
const browser_discovery = @import("browser_discovery.zig");
const core_runtime = @import("webui.zig");

pub const WindowContent = union(enum) {
    html: []const u8,
    file: []const u8,
    url: []const u8,
};

pub const NativeBackend = switch (builtin.os.tag) {
    .linux => LinuxWebView,
    .windows => Win32WebView,
    .macos => MacWebView,
    else => @compileError("Unsupported Backend"),
};

test "native backend selects platform or none" {
    const native = NativeBackend.init(true);
    const fallback = NativeBackend.init(false);
    try std.testing.expect(native.isNative());
    try std.testing.expect(!fallback.isNative());
}

pub const LinuxWebView = struct {
    native_enabled: bool = false,
    window_id: usize = 0,
    title: []const u8 = "",
    style: style_types.WindowStyle = .{},
    hidden: bool = false,
    maximized: bool = false,
    native_host_ready: bool = false,
    browser_kind: ?browser_discovery.BrowserKind = null,
    browser_pid: ?i64 = null,
    browser_is_child: bool = false,

    pub fn init(enable_native: bool) LinuxWebView {
        return .{ .native_enabled = enable_native };
    }

    pub fn deinit(self: *LinuxWebView) void {
        self.native_host_ready = false;
        self.browser_kind = null;
        self.browser_pid = null;
        self.browser_is_child = false;
    }

    pub fn isNative(self: *const LinuxWebView) bool {
        return self.native_enabled;
    }

    pub fn isReady(self: *const LinuxWebView) bool {
        return self.native_host_ready;
    }

    pub fn createWindow(self: *LinuxWebView, window_id: usize, title: []const u8, style: style_types.WindowStyle) !void {
        self.window_id = window_id;
        self.title = title;
        self.style = style;
    }

    pub fn showContent(self: *LinuxWebView, content: anytype) !void {
        const Content = @TypeOf(content);
        if (@hasField(Content, "url")) {
            self.navigate(@field(content, "url"));
            return;
        }
        return error.UnsupportedWindowContent;
    }

    pub fn attachBrowserProcess(self: *LinuxWebView, kind: ?browser_discovery.BrowserKind, pid: ?i64, is_child_process: bool) void {
        self.browser_kind = kind;
        self.browser_pid = pid;
        self.browser_is_child = is_child_process;
        self.native_host_ready = pid != null;
    }

    pub fn navigate(self: *LinuxWebView, url: []const u8) void {
        if (!self.native_host_ready) return;
        if (self.browser_kind) |kind| {
            _ = core_runtime.openUrlInExistingBrowserKind(std.heap.page_allocator, kind, url);
        }
    }

    pub fn applyStyle(self: *LinuxWebView, style: style_types.WindowStyle) !void {
        self.style = style;
        if (!self.native_host_ready) return;
        if (self.browser_kind) |kind| {
            if (!core_runtime.supportsRequestedStyleInBrowser(kind, style)) return error.UnsupportedWindowStyle;
        }
    }

    pub fn control(self: *LinuxWebView, cmd: style_types.WindowControl) !void {
        if (!self.native_host_ready) return error.NativeBackendUnavailable;
        if (!self.browser_is_child) return error.UnsupportedWindowControl;
        switch (cmd) {
            .close => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.hidden = true;
                        return;
                    }
                }
                return error.UnsupportedWindowControl;
            },
            .hide => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.hidden = true;
                        return;
                    }
                }
                self.hidden = true;
                return error.UnsupportedWindowControl;
            },
            .show => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.hidden = false;
                        return;
                    }
                }
                self.hidden = false;
                return error.UnsupportedWindowControl;
            },
            .maximize => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.maximized = true;
                        return;
                    }
                }
                self.maximized = true;
                return error.UnsupportedWindowControl;
            },
            .restore => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.maximized = false;
                        self.hidden = false;
                        return;
                    }
                }
                self.maximized = false;
                return error.UnsupportedWindowControl;
            },
            .minimize => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.hidden = true;
                        return;
                    }
                }
                self.hidden = true;
                return error.UnsupportedWindowControl;
            },
        }
    }

    pub fn pumpEvents(self: *LinuxWebView) !void {
        _ = self;
    }

    pub fn destroyWindow(self: *LinuxWebView) void {
        self.native_host_ready = false;
        self.browser_kind = null;
        self.browser_pid = null;
        self.browser_is_child = false;
    }

    pub fn capabilities(self: *const LinuxWebView) []const style_types.WindowCapability {
        if (!self.native_host_ready) return &.{};
        if (self.browser_kind == null) {
            return &.{
                .native_frameless,
                .native_transparency,
                .native_corner_radius,
                .native_positioning,
                .native_minmax,
                .native_kiosk,
            };
        }
        if (self.browser_kind) |kind| {
            if (supportsChromiumStyle(kind)) {
                return &.{
                    .native_frameless,
                    .native_transparency,
                    .native_corner_radius,
                    .native_positioning,
                    .native_minmax,
                    .native_kiosk,
                };
            }
            if (kind == .firefox or kind == .tor or kind == .librewolf or kind == .mullvad or kind == .palemoon) {
                return &.{ .native_kiosk, .native_minmax };
            }
        }
        return &.{};
    }

    test "linux backend capabilities require host readiness" {
        var backend: LinuxWebView = .{};
        try std.testing.expectEqual(@as(usize, 0), backend.capabilities().len);

        backend.attachBrowserProcess(.chrome, 1234, true);
        const caps = backend.capabilities();
        try std.testing.expect(caps.len > 0);
        try std.testing.expect(style_types.hasCapability(.native_frameless, caps));
        try std.testing.expect(style_types.hasCapability(.native_minmax, caps));
    }

    test "linux backend control requires child-owned browser process" {
        var backend: LinuxWebView = .{};
        backend.attachBrowserProcess(.chrome, 1234, false);
        try std.testing.expectError(error.UnsupportedWindowControl, backend.control(.maximize));
    }
};

pub const Win32WebView = struct {
    native_enabled: bool = false,
    window_id: usize = 0,
    title: []const u8 = "",
    style: style_types.WindowStyle = .{},
    hidden: bool = false,
    maximized: bool = false,
    native_host_ready: bool = false,
    browser_kind: ?browser_discovery.BrowserKind = null,
    browser_pid: ?i64 = null,
    browser_is_child: bool = false,

    pub fn init(enable_native: bool) Win32WebView {
        return .{ .native_enabled = enable_native };
    }

    pub fn deinit(self: *Win32WebView) void {
        self.native_host_ready = false;
        self.browser_kind = null;
        self.browser_pid = null;
        self.browser_is_child = false;
    }

    pub fn isNative(self: *const Win32WebView) bool {
        return self.native_enabled;
    }

    pub fn isReady(self: *const Win32WebView) bool {
        return self.native_host_ready;
    }

    pub fn createWindow(self: *Win32WebView, window_id: usize, title: []const u8, style: style_types.WindowStyle) !void {
        self.window_id = window_id;
        self.title = title;
        self.style = style;
    }

    pub fn showContent(self: *Win32WebView, content: anytype) !void {
        const Content = @TypeOf(content);
        if (@hasField(Content, "url")) {
            self.navigate(@field(content, "url"));
            return;
        }
        return error.UnsupportedWindowContent;
    }

    pub fn attachBrowserProcess(self: *Win32WebView, kind: ?browser_discovery.BrowserKind, pid: ?i64, is_child_process: bool) void {
        self.browser_kind = kind;
        self.browser_pid = pid;
        self.browser_is_child = is_child_process;
        self.native_host_ready = pid != null;
    }

    pub fn navigate(self: *Win32WebView, url: []const u8) void {
        if (!self.native_host_ready) return;
        if (self.browser_kind) |kind| {
            _ = core_runtime.openUrlInExistingBrowserKind(std.heap.page_allocator, kind, url);
        }
    }

    pub fn applyStyle(self: *Win32WebView, style: style_types.WindowStyle) !void {
        self.style = style;
        if (!self.native_host_ready) return;
        if (self.browser_kind) |kind| {
            if (!core_runtime.supportsRequestedStyleInBrowser(kind, style)) return error.UnsupportedWindowStyle;
        }
    }

    pub fn control(self: *Win32WebView, cmd: style_types.WindowControl) !void {
        if (!self.native_host_ready) return error.NativeBackendUnavailable;
        if (!self.browser_is_child) return error.UnsupportedWindowControl;
        switch (cmd) {
            .close => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.hidden = true;
                        return;
                    }
                }
                return error.UnsupportedWindowControl;
            },
            .hide => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.hidden = true;
                        return;
                    }
                }
                self.hidden = true;
                return error.UnsupportedWindowControl;
            },
            .show => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.hidden = false;
                        return;
                    }
                }
                self.hidden = false;
                return error.UnsupportedWindowControl;
            },
            .maximize => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.maximized = true;
                        return;
                    }
                }
                self.maximized = true;
                return error.UnsupportedWindowControl;
            },
            .restore => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.maximized = false;
                        self.hidden = false;
                        return;
                    }
                }
                self.maximized = false;
                return error.UnsupportedWindowControl;
            },
            .minimize => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.hidden = true;
                        return;
                    }
                }
                self.hidden = true;
                return error.UnsupportedWindowControl;
            },
        }
    }

    pub fn pumpEvents(self: *Win32WebView) !void {
        _ = self;
    }

    pub fn destroyWindow(self: *Win32WebView) void {
        self.native_host_ready = false;
        self.browser_kind = null;
        self.browser_pid = null;
        self.browser_is_child = false;
    }

    pub fn capabilities(self: *const Win32WebView) []const style_types.WindowCapability {
        if (!self.native_host_ready) return &.{};
        if (self.browser_kind == null) {
            return &.{
                .native_frameless,
                .native_transparency,
                .native_corner_radius,
                .native_positioning,
                .native_minmax,
                .native_kiosk,
            };
        }
        if (self.browser_kind) |kind| {
            if (supportsChromiumStyle(kind)) {
                return &.{
                    .native_frameless,
                    .native_transparency,
                    .native_corner_radius,
                    .native_positioning,
                    .native_minmax,
                    .native_kiosk,
                };
            }
            if (kind == .firefox or kind == .tor or kind == .librewolf or kind == .mullvad or kind == .palemoon) {
                return &.{ .native_kiosk, .native_minmax };
            }
        }
        return &.{};
    }

    test "win backend capabilities require host readiness" {
        var backend: Win32WebView = .{};
        try std.testing.expectEqual(@as(usize, 0), backend.capabilities().len);

        backend.attachBrowserProcess(.chrome, 1234, true);
        const caps = backend.capabilities();
        try std.testing.expect(caps.len > 0);
        try std.testing.expect(style_types.hasCapability(.native_frameless, caps));
        try std.testing.expect(style_types.hasCapability(.native_minmax, caps));
    }

    test "win backend control requires child-owned browser process" {
        var backend: Win32WebView = .{};
        backend.attachBrowserProcess(.chrome, 1234, false);
        try std.testing.expectError(error.UnsupportedWindowControl, backend.control(.maximize));
    }
};

pub const MacWebView = struct {
    native_enabled: bool = false,
    window_id: usize = 0,
    title: []const u8 = "",
    style: style_types.WindowStyle = .{},
    hidden: bool = false,
    maximized: bool = false,
    native_host_ready: bool = false,
    browser_kind: ?browser_discovery.BrowserKind = null,
    browser_pid: ?i64 = null,
    browser_is_child: bool = false,

    pub fn init(enable_native: bool) MacWebView {
        return .{ .native_enabled = enable_native };
    }

    pub fn deinit(self: *MacWebView) void {
        self.native_host_ready = false;
        self.browser_kind = null;
        self.browser_pid = null;
        self.browser_is_child = false;
    }

    pub fn isNative(self: *const MacWebView) bool {
        return self.native_enabled;
    }

    pub fn isReady(self: *const MacWebView) bool {
        return self.native_host_ready;
    }

    pub fn createWindow(self: *MacWebView, window_id: usize, title: []const u8, style: style_types.WindowStyle) !void {
        self.window_id = window_id;
        self.title = title;
        self.style = style;
    }

    pub fn showContent(self: *MacWebView, content: anytype) !void {
        const Content = @TypeOf(content);
        if (@hasField(Content, "url")) {
            self.navigate(@field(content, "url"));
            return;
        }
        return error.UnsupportedWindowContent;
    }

    pub fn attachBrowserProcess(self: *MacWebView, kind: ?browser_discovery.BrowserKind, pid: ?i64, is_child_process: bool) void {
        self.browser_kind = kind;
        self.browser_pid = pid;
        self.browser_is_child = is_child_process;
        self.native_host_ready = pid != null;
    }

    pub fn navigate(self: *MacWebView, url: []const u8) void {
        if (!self.native_host_ready) return;
        if (self.browser_kind) |kind| {
            _ = core_runtime.openUrlInExistingBrowserKind(std.heap.page_allocator, kind, url);
        }
    }

    pub fn applyStyle(self: *MacWebView, style: style_types.WindowStyle) !void {
        self.style = style;
        if (!self.native_host_ready) return;
        if (self.browser_kind) |kind| {
            if (!core_runtime.supportsRequestedStyleInBrowser(kind, style)) return error.UnsupportedWindowStyle;
        }
    }

    pub fn control(self: *MacWebView, cmd: style_types.WindowControl) !void {
        if (!self.native_host_ready) return error.NativeBackendUnavailable;
        if (!self.browser_is_child) return error.UnsupportedWindowControl;
        switch (cmd) {
            .close => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.hidden = true;
                        return;
                    }
                }
                return error.UnsupportedWindowControl;
            },
            .hide => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.hidden = true;
                        return;
                    }
                }
                self.hidden = true;
                return error.UnsupportedWindowControl;
            },
            .show => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.hidden = false;
                        return;
                    }
                }
                self.hidden = false;
                return error.UnsupportedWindowControl;
            },
            .maximize => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.maximized = true;
                        return;
                    }
                }
                self.maximized = true;
                return error.UnsupportedWindowControl;
            },
            .restore => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.maximized = false;
                        self.hidden = false;
                        return;
                    }
                }
                self.maximized = false;
                return error.UnsupportedWindowControl;
            },
            .minimize => {
                if (self.browser_pid) |pid| {
                    if (core_runtime.controlBrowserWindow(std.heap.page_allocator, pid, cmd)) {
                        self.hidden = true;
                        return;
                    }
                }
                self.hidden = true;
                return error.UnsupportedWindowControl;
            },
        }
    }

    pub fn pumpEvents(self: *MacWebView) !void {
        _ = self;
    }

    pub fn destroyWindow(self: *MacWebView) void {
        self.native_host_ready = false;
        self.browser_kind = null;
        self.browser_pid = null;
        self.browser_is_child = false;
    }

    pub fn capabilities(self: *const MacWebView) []const style_types.WindowCapability {
        if (!self.native_host_ready) return &.{};
        if (self.browser_kind == null) {
            return &.{
                .native_frameless,
                .native_transparency,
                .native_corner_radius,
                .native_positioning,
                .native_minmax,
                .native_kiosk,
            };
        }
        if (self.browser_kind) |kind| {
            if (supportsChromiumStyle(kind)) {
                return &.{
                    .native_frameless,
                    .native_transparency,
                    .native_corner_radius,
                    .native_positioning,
                    .native_minmax,
                    .native_kiosk,
                };
            }
            if (kind == .firefox or kind == .tor or kind == .librewolf or kind == .mullvad or kind == .palemoon or kind == .safari) {
                return &.{ .native_kiosk, .native_minmax };
            }
        }
        return &.{};
    }

    test "mac backend capabilities require host readiness" {
        var backend: MacWebView = .{};
        try std.testing.expectEqual(@as(usize, 0), backend.capabilities().len);

        backend.attachBrowserProcess(.chrome, 1234, true);
        const caps = backend.capabilities();
        try std.testing.expect(caps.len > 0);
        try std.testing.expect(style_types.hasCapability(.native_frameless, caps));
        try std.testing.expect(style_types.hasCapability(.native_minmax, caps));
    }

    test "mac backend control requires child-owned browser process" {
        var backend: MacWebView = .{};
        backend.attachBrowserProcess(.chrome, 1234, false);
        try std.testing.expectError(error.UnsupportedWindowControl, backend.control(.maximize));
    }
};

fn supportsChromiumStyle(kind: browser_discovery.BrowserKind) bool {
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

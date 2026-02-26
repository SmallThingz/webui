const std = @import("std");
const style_types = @import("../../window_style.zig");
const browser_discovery = @import("../browser_discovery.zig");
const core_runtime = @import("../webui.zig");

pub const MacWebView = struct {
    style: style_types.WindowStyle = .{},
    hidden: bool = false,
    maximized: bool = false,
    native_host_ready: bool = false,
    browser_kind: ?browser_discovery.BrowserKind = null,
    browser_pid: ?i64 = null,
    browser_is_child: bool = false,

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
        .lightpanda,
        => true,
        else => false,
    };
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

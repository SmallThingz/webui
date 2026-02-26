const std = @import("std");
const builtin = @import("builtin");
const style_types = @import("../../window_style.zig");
const browser_discovery = @import("../browser_discovery.zig");
const win32 = @import("win32_wv2.zig");
const mac = @import("wkwebview.zig");
const linux = @import("linux_webkit.zig");

pub const WindowContent = union(enum) {
    html: []const u8,
    file: []const u8,
    url: []const u8,
};

pub const NativeBackend = union(enum) {
    none: void,
    windows: win32.Win32WebView,
    macos: mac.MacWebView,
    linux: linux.LinuxWebView,

    pub fn init(use_native: bool) NativeBackend {
        if (!use_native) return .{ .none = {} };

        return switch (builtin.os.tag) {
            .windows => .{ .windows = .{} },
            .macos => .{ .macos = .{} },
            .linux => .{ .linux = .{} },
            else => .{ .none = {} },
        };
    }

    pub fn deinit(self: *NativeBackend) void {
        _ = self;
    }

    pub fn isNative(self: NativeBackend) bool {
        return switch (self) {
            .none => false,
            else => true,
        };
    }

    pub fn isReady(self: *const NativeBackend) bool {
        return switch (self.*) {
            .none => false,
            .windows => |*w| w.isReady(),
            .macos => |*m| m.isReady(),
            .linux => |*l| l.isReady(),
        };
    }

    pub fn createWindow(self: *NativeBackend, window_id: usize, title: []const u8, style: style_types.WindowStyle) !void {
        switch (self.*) {
            .none => {},
            .windows => |*w| try w.createWindow(window_id, title, style),
            .macos => |*m| try m.createWindow(window_id, title, style),
            .linux => |*l| try l.createWindow(window_id, title, style),
        }
    }

    pub fn showContent(self: *NativeBackend, content: WindowContent) !void {
        switch (self.*) {
            .none => {},
            .windows => |*w| try w.showContent(content),
            .macos => |*m| try m.showContent(content),
            .linux => |*l| try l.showContent(content),
        }
    }

    pub fn navigate(self: *NativeBackend, url: []const u8) void {
        switch (self.*) {
            .none => {},
            .windows => |*w| w.navigate(url),
            .macos => |*m| m.navigate(url),
            .linux => |*l| l.navigate(url),
        }
    }

    pub fn attachBrowserProcess(self: *NativeBackend, kind: ?browser_discovery.BrowserKind, pid: ?i64, is_child_process: bool) void {
        switch (self.*) {
            .none => {},
            .windows => |*w| w.attachBrowserProcess(kind, pid, is_child_process),
            .macos => |*m| m.attachBrowserProcess(kind, pid, is_child_process),
            .linux => |*l| l.attachBrowserProcess(kind, pid, is_child_process),
        }
    }

    pub fn applyStyle(self: *NativeBackend, style: style_types.WindowStyle) !void {
        switch (self.*) {
            .none => {},
            .windows => |*w| try w.applyStyle(style),
            .macos => |*m| try m.applyStyle(style),
            .linux => |*l| try l.applyStyle(style),
        }
    }

    pub fn control(self: *NativeBackend, cmd: style_types.WindowControl) !void {
        switch (self.*) {
            .none => {},
            .windows => |*w| try w.control(cmd),
            .macos => |*m| try m.control(cmd),
            .linux => |*l| try l.control(cmd),
        }
    }

    pub fn pumpEvents(self: *NativeBackend) !void {
        switch (self.*) {
            .none => {},
            .windows => |*w| try w.pumpEvents(),
            .macos => |*m| try m.pumpEvents(),
            .linux => |*l| try l.pumpEvents(),
        }
    }

    pub fn destroyWindow(self: *NativeBackend) void {
        switch (self.*) {
            .none => {},
            .windows => |*w| w.destroyWindow(),
            .macos => |*m| m.destroyWindow(),
            .linux => |*l| l.destroyWindow(),
        }
    }

    pub fn capabilities(self: *const NativeBackend) []const style_types.WindowCapability {
        return switch (self.*) {
            .none => &.{},
            .windows => |*w| w.capabilities(),
            .macos => |*m| m.capabilities(),
            .linux => |*l| l.capabilities(),
        };
    }
};

test "native backend selects platform or none" {
    const native = NativeBackend.init(true);
    const fallback = NativeBackend.init(false);
    try std.testing.expect(fallback == .none);
    _ = native;
}

const std = @import("std");
const builtin = @import("builtin");
const api_types = @import("api_types.zig");
const linux_webview_host = if (builtin.os.tag == .linux)
    @import("../backends/linux_webview_host.zig")
else
    struct {};
const windows_webview_host = if (builtin.os.tag == .windows)
    @import("../backends/windows_webview_host.zig")
else
    struct {};
const macos_webview_host = if (builtin.os.tag == .macos)
    @import("../backends/macos_webview_host.zig")
else
    struct {};

pub const RuntimeRequirement = struct {
    name: []const u8,
    required: bool,
    available: bool,
    details: ?[]const u8 = null,
};

pub const ListOptions = struct {
    uses_native_webview: bool,
    uses_managed_browser: bool,
    uses_web_url: bool,
    app_mode_required: bool,
    native_backend_available: bool,
    linux_webview_target: api_types.LinuxWebViewTarget = .webview,
};

pub fn list(allocator: std.mem.Allocator, options: ListOptions) ![]RuntimeRequirement {
    var out = std.array_list.Managed(RuntimeRequirement).init(allocator);
    errdefer out.deinit();

    try out.append(.{
        .name = "native_webview_backend",
        .required = options.uses_native_webview,
        .available = options.native_backend_available,
        .details = if (!options.native_backend_available) "Native backend unavailable on this target/runtime" else null,
    });

    if (builtin.os.tag == .linux) {
        const linux_target = switch (options.linux_webview_target) {
            .webview => linux_webview_host.RuntimeTarget.webview,
            .webkitgtk_6 => linux_webview_host.RuntimeTarget.webkitgtk_6,
        };
        try out.append(.{
            .name = switch (options.linux_webview_target) {
                .webview => "linux.gtk_webkit_runtime",
                .webkitgtk_6 => "linux.webkitgtk6_runtime",
            },
            .required = options.uses_native_webview and options.app_mode_required,
            .available = linux_webview_host.runtimeAvailableFor(linux_target),
            .details = switch (options.linux_webview_target) {
                .webview => "In-process GTK3/WebKit2GTK 4.1/4.0 runtime shared libraries",
                .webkitgtk_6 => "In-process GTK4/WebKitGTK 6 runtime shared libraries",
            },
        });

        try out.append(.{
            .name = "linux.browser_process_launch",
            .required = options.uses_managed_browser or options.uses_web_url,
            .available = true,
            .details = "Direct in-process browser spawning path",
        });
    }

    if (builtin.os.tag == .windows) {
        try out.append(.{
            .name = "windows.webview2_runtime",
            .required = options.uses_native_webview and options.app_mode_required,
            .available = windows_webview_host.runtimeAvailable(),
            .details = "In-process WebView2 runtime availability",
        });
    }

    if (builtin.os.tag == .macos) {
        try out.append(.{
            .name = "macos.webkit_runtime",
            .required = options.uses_native_webview and options.app_mode_required,
            .available = macos_webview_host.runtimeAvailable(),
            .details = "In-process WebKit runtime availability",
        });
    }

    return out.toOwnedSlice();
}

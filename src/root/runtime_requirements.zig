const std = @import("std");
const builtin = @import("builtin");
const linux_webview_host = if (builtin.os.tag == .linux)
    @import("../backends/linux_webview_host.zig")
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
        try out.append(.{
            .name = "linux.gtk_webkit_runtime",
            .required = options.uses_native_webview and options.app_mode_required,
            .available = linux_webview_host.runtimeAvailable(),
            .details = "In-process GTK/WebKit runtime shared libraries",
        });

        try out.append(.{
            .name = "linux.browser_process_launch",
            .required = options.uses_managed_browser or options.uses_web_url,
            .available = true,
            .details = "Direct in-process browser spawning path",
        });
    }

    return out.toOwnedSlice();
}

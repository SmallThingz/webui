const std = @import("std");
const builtin = @import("builtin");

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
        const exe_dir = std.fs.selfExeDirPathAlloc(allocator) catch null;
        defer if (exe_dir) |d| allocator.free(d);

        const webview_helper_available = if (exe_dir) |dir| blk: {
            const path = std.fs.path.join(allocator, &.{ dir, "webui_linux_webview_host" }) catch break :blk false;
            defer allocator.free(path);
            std.fs.cwd().access(path, .{}) catch break :blk false;
            break :blk true;
        } else false;

        const browser_helper_available = if (exe_dir) |dir| blk: {
            const path = std.fs.path.join(allocator, &.{ dir, "webui_linux_browser_host" }) catch break :blk false;
            defer allocator.free(path);
            std.fs.cwd().access(path, .{}) catch break :blk false;
            break :blk true;
        } else false;

        try out.append(.{
            .name = "webui_linux_webview_host",
            .required = options.uses_native_webview and options.app_mode_required,
            .available = webview_helper_available,
            .details = if (!webview_helper_available) "Expected beside executable" else null,
        });

        try out.append(.{
            .name = "webui_linux_browser_host",
            .required = options.uses_managed_browser or options.uses_web_url,
            .available = browser_helper_available,
            .details = if (!browser_helper_available) "Expected beside executable" else null,
        });
    }

    return out.toOwnedSlice();
}

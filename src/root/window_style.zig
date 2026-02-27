const std = @import("std");

pub const Size = struct {
    width: u32,
    height: u32,
};

pub const Point = struct {
    x: i32,
    y: i32,
};

pub const WindowIcon = struct {
    bytes: []const u8,
    mime_type: []const u8,
};

pub const WindowStyle = struct {
    frameless: bool = false,
    transparent: bool = false,
    corner_radius: ?u16 = null,
    resizable: bool = true,
    kiosk: bool = false,
    hidden: bool = false,
    size: ?Size = null,
    min_size: ?Size = null,
    position: ?Point = null,
    center: bool = false,
    icon: ?WindowIcon = null,
    high_contrast: ?bool = null,
};

pub const WindowControl = enum {
    minimize,
    maximize,
    restore,
    close,
    hide,
    show,
};

pub const WindowCapability = enum {
    native_frameless,
    native_transparency,
    native_corner_radius,
    native_positioning,
    native_minmax,
    native_icon,
    native_kiosk,
};

pub const CloseHandler = *const fn (context: ?*anyopaque, window_id: usize) bool;

pub fn mergeStyle(base: WindowStyle, patch: WindowStyle) WindowStyle {
    var out = base;
    out.frameless = patch.frameless;
    out.transparent = patch.transparent;
    out.corner_radius = patch.corner_radius;
    out.resizable = patch.resizable;
    out.kiosk = patch.kiosk;
    out.hidden = patch.hidden;
    out.size = patch.size;
    out.min_size = patch.min_size;
    out.position = patch.position;
    out.center = patch.center;
    out.icon = patch.icon;
    out.high_contrast = patch.high_contrast;
    return out;
}

pub fn hasCapability(needle: WindowCapability, haystack: []const WindowCapability) bool {
    for (haystack) |cap| {
        if (cap == needle) return true;
    }
    return false;
}

test "window style merge overwrites all fields" {
    const merged = mergeStyle(.{
        .frameless = false,
        .resizable = true,
    }, .{
        .frameless = true,
        .transparent = true,
        .resizable = false,
        .corner_radius = 14,
        .size = .{ .width = 800, .height = 600 },
    });

    try std.testing.expect(merged.frameless);
    try std.testing.expect(merged.transparent);
    try std.testing.expect(!merged.resizable);
    try std.testing.expectEqual(@as(?u16, 14), merged.corner_radius);
    try std.testing.expectEqual(@as(?Size, .{ .width = 800, .height = 600 }), merged.size);
}

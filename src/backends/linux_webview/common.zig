const window_style_types = @import("../../root/window_style.zig");

pub const WindowStyle = window_style_types.WindowStyle;
pub const WindowControl = window_style_types.WindowControl;

pub const GtkWidget = opaque {};
pub const GtkWindow = opaque {};
pub const GtkContainer = opaque {};
pub const GdkScreen = opaque {};
pub const GdkVisual = opaque {};
pub const WebKitWebView = opaque {};
pub const cairo_region_t = opaque {};
pub const cairo_t = opaque {};
pub const cairo_surface_t = opaque {};

pub const GtkAllocation = extern struct {
    x: c_int,
    y: c_int,
    width: c_int,
    height: c_int,
};

pub const GdkRGBA = extern struct {
    red: f64,
    green: f64,
    blue: f64,
    alpha: f64,
};

pub const GTK_WINDOW_TOPLEVEL: c_int = 0;
pub const GTK_WIN_POS_CENTER: c_int = 1;
pub const CAIRO_FORMAT_A8: c_int = 2;


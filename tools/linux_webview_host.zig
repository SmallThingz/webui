const std = @import("std");

const GtkWidget = opaque {};
const GtkWindow = opaque {};
const GtkContainer = opaque {};
const GdkScreen = opaque {};
const GdkVisual = opaque {};
const WebKitWebView = opaque {};
const cairo_region_t = opaque {};
const cairo_t = opaque {};
const cairo_surface_t = opaque {};

const GtkAllocation = extern struct {
    x: c_int,
    y: c_int,
    width: c_int,
    height: c_int,
};

const GdkRGBA = extern struct {
    red: f64,
    green: f64,
    blue: f64,
    alpha: f64,
};

extern fn gtk_init(argc: ?*c_int, argv: ?*anyopaque) void;
extern fn gtk_main() void;
extern fn gtk_main_quit() void;
extern fn gtk_window_new(window_type: c_int) *GtkWidget;
extern fn gtk_window_set_title(window: *GtkWindow, title: [*:0]const u8) void;
extern fn gtk_window_set_default_size(window: *GtkWindow, width: c_int, height: c_int) void;
extern fn gtk_window_set_decorated(window: *GtkWindow, setting: c_int) void;
extern fn gtk_window_set_resizable(window: *GtkWindow, resizable: c_int) void;
extern fn gtk_window_set_position(window: *GtkWindow, position: c_int) void;
extern fn gtk_window_move(window: *GtkWindow, x: c_int, y: c_int) void;
extern fn gtk_widget_set_app_paintable(widget: *GtkWidget, app_paintable: c_int) void;
extern fn gtk_widget_get_screen(widget: *GtkWidget) ?*GdkScreen;
extern fn gdk_screen_get_rgba_visual(screen: *GdkScreen) ?*GdkVisual;
extern fn gtk_widget_set_visual(widget: *GtkWidget, visual: *GdkVisual) void;
extern fn gtk_widget_get_allocated_width(widget: *GtkWidget) c_int;
extern fn gtk_widget_get_allocated_height(widget: *GtkWidget) c_int;
extern fn gtk_container_add(container: *GtkContainer, widget: *GtkWidget) void;
extern fn gtk_widget_shape_combine_region(widget: *GtkWidget, shape_region: ?*cairo_region_t) void;
extern fn gtk_widget_input_shape_combine_region(widget: *GtkWidget, shape_region: ?*cairo_region_t) void;
extern fn gtk_widget_show_all(widget: *GtkWidget) void;
extern fn webkit_web_view_new() *GtkWidget;
extern fn webkit_web_view_load_uri(web_view: *WebKitWebView, uri: [*:0]const u8) void;
extern fn webkit_web_view_set_background_color(web_view: *WebKitWebView, rgba: *const GdkRGBA) void;
extern fn g_signal_connect_data(
    instance: *anyopaque,
    detailed_signal: [*:0]const u8,
    c_handler: *const anyopaque,
    data: ?*anyopaque,
    destroy_data: ?*const anyopaque,
    connect_flags: c_uint,
) c_ulong;

extern fn gdk_cairo_region_create_from_surface(surface: *cairo_surface_t) ?*cairo_region_t;
extern fn cairo_image_surface_create(format: c_int, width: c_int, height: c_int) ?*cairo_surface_t;
extern fn cairo_surface_destroy(surface: *cairo_surface_t) void;
extern fn cairo_create(target: *cairo_surface_t) ?*cairo_t;
extern fn cairo_destroy(cr: *cairo_t) void;
extern fn cairo_set_source_rgba(cr: *cairo_t, red: f64, green: f64, blue: f64, alpha: f64) void;
extern fn cairo_paint(cr: *cairo_t) void;
extern fn cairo_new_path(cr: *cairo_t) void;
extern fn cairo_arc(cr: *cairo_t, xc: f64, yc: f64, radius: f64, angle1: f64, angle2: f64) void;
extern fn cairo_close_path(cr: *cairo_t) void;
extern fn cairo_rectangle(cr: *cairo_t, x: f64, y: f64, width: f64, height: f64) void;
extern fn cairo_fill(cr: *cairo_t) void;
extern fn cairo_region_destroy(region: *cairo_region_t) void;

const GTK_WINDOW_TOPLEVEL: c_int = 0;
const GTK_WIN_POS_CENTER: c_int = 1;
const CAIRO_FORMAT_A8: c_int = 2;

var g_corner_radius: c_int = 0;

fn applyRoundedWindowShape(window_widget: *GtkWidget, width: c_int, height: c_int) void {
    if (width <= 0 or height <= 0) return;
    if (g_corner_radius <= 0) {
        gtk_widget_shape_combine_region(window_widget, null);
        gtk_widget_input_shape_combine_region(window_widget, null);
        return;
    }

    const max_radius = @min(@divTrunc(width, 2), @divTrunc(height, 2));
    const radius = @min(g_corner_radius, max_radius);
    if (radius <= 0) return;

    const region = buildRoundedRegion(width, height, radius) orelse return;
    defer cairo_region_destroy(region);

    gtk_widget_shape_combine_region(window_widget, region);
    gtk_widget_input_shape_combine_region(window_widget, region);
}

fn buildRoundedRegion(width: c_int, height: c_int, radius: c_int) ?*cairo_region_t {
    if (width <= 0 or height <= 0) return null;
    const surface = cairo_image_surface_create(CAIRO_FORMAT_A8, width, height) orelse return null;
    defer cairo_surface_destroy(surface);

    const cr = cairo_create(surface) orelse return null;
    defer cairo_destroy(cr);

    cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
    cairo_paint(cr);
    cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 1.0);

    const w = @as(f64, @floatFromInt(width));
    const h = @as(f64, @floatFromInt(height));
    const r = @as(f64, @floatFromInt(radius));

    if (radius <= 0) {
        cairo_rectangle(cr, 0.0, 0.0, w, h);
        cairo_fill(cr);
        return gdk_cairo_region_create_from_surface(surface);
    }

    const pi = std.math.pi;
    cairo_new_path(cr);
    cairo_arc(cr, w - r, r, r, -pi / 2.0, 0.0);
    cairo_arc(cr, w - r, h - r, r, 0.0, pi / 2.0);
    cairo_arc(cr, r, h - r, r, pi / 2.0, pi);
    cairo_arc(cr, r, r, r, pi, pi * 1.5);
    cairo_close_path(cr);
    cairo_fill(cr);

    return gdk_cairo_region_create_from_surface(surface);
}

fn onDestroy(_: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    gtk_main_quit();
}

fn onRealize(widget: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    const gtk_widget = widget orelse return;
    const window_widget: *GtkWidget = @ptrCast(@alignCast(gtk_widget));
    applyRoundedWindowShape(
        window_widget,
        gtk_widget_get_allocated_width(window_widget),
        gtk_widget_get_allocated_height(window_widget),
    );
}

fn onSizeAllocate(widget: ?*anyopaque, allocation: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    const gtk_widget = widget orelse return;
    const window_widget: *GtkWidget = @ptrCast(@alignCast(gtk_widget));

    if (allocation) |raw_alloc| {
        const alloc: *GtkAllocation = @ptrCast(@alignCast(raw_alloc));
        applyRoundedWindowShape(window_widget, alloc.width, alloc.height);
        return;
    }

    applyRoundedWindowShape(
        window_widget,
        gtk_widget_get_allocated_width(window_widget),
        gtk_widget_get_allocated_height(window_widget),
    );
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 2) return error.InvalidArgs;

    const url = args[1];
    const width: u32 = if (args.len > 2) (std.fmt.parseInt(u32, args[2], 10) catch 980) else 980;
    const height: u32 = if (args.len > 3) (std.fmt.parseInt(u32, args[3], 10) catch 660) else 660;
    const frameless = args.len > 4 and std.mem.eql(u8, args[4], "1");
    const transparent = args.len > 5 and std.mem.eql(u8, args[5], "1");
    const corner_radius: u16 = if (args.len > 6) (std.fmt.parseInt(u16, args[6], 10) catch 0) else 0;
    const resizable = if (args.len > 7) std.mem.eql(u8, args[7], "1") else true;
    const center = if (args.len > 8) std.mem.eql(u8, args[8], "1") else true;
    const pos_x: i32 = if (args.len > 9) (std.fmt.parseInt(i32, args[9], 10) catch 0) else 0;
    const pos_y: i32 = if (args.len > 10) (std.fmt.parseInt(i32, args[10], 10) catch 0) else 0;

    gtk_init(null, null);

    const window_widget = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    const window: *GtkWindow = @ptrCast(window_widget);
    gtk_window_set_title(window, "WebUI");
    gtk_window_set_default_size(window, @as(c_int, @intCast(width)), @as(c_int, @intCast(height)));
    gtk_window_set_resizable(window, if (resizable) 1 else 0);
    if (center) gtk_window_set_position(window, GTK_WIN_POS_CENTER) else gtk_window_move(window, @as(c_int, @intCast(pos_x)), @as(c_int, @intCast(pos_y)));

    if (frameless) gtk_window_set_decorated(window, 0);
    if (transparent) {
        gtk_widget_set_app_paintable(window_widget, 1);
        if (gtk_widget_get_screen(window_widget)) |screen| {
            if (gdk_screen_get_rgba_visual(screen)) |rgba_visual| {
                gtk_widget_set_visual(window_widget, rgba_visual);
            }
        }
    }

    g_corner_radius = @as(c_int, @intCast(corner_radius));

    const webview_widget = webkit_web_view_new();
    const webview: *WebKitWebView = @ptrCast(webview_widget);
    if (transparent) {
        const clear = GdkRGBA{
            .red = 0.0,
            .green = 0.0,
            .blue = 0.0,
            .alpha = 0.0,
        };
        webkit_web_view_set_background_color(webview, &clear);
    }

    const url_z = try allocator.dupeZ(u8, url);
    defer allocator.free(url_z);
    webkit_web_view_load_uri(webview, url_z);

    gtk_container_add(@ptrCast(window_widget), webview_widget);
    _ = g_signal_connect_data(@ptrCast(window_widget), "destroy", @ptrCast(&onDestroy), null, null, 0);
    _ = g_signal_connect_data(@ptrCast(window_widget), "realize", @ptrCast(&onRealize), null, null, 0);
    _ = g_signal_connect_data(@ptrCast(window_widget), "size-allocate", @ptrCast(&onSizeAllocate), null, null, 0);

    gtk_widget_show_all(window_widget);
    gtk_main();
}

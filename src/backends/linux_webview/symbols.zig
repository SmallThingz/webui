const std = @import("std");
const common = @import("common.zig");

pub const Symbols = struct {
    gtk: std.DynLib,
    gdk: std.DynLib,
    webkit: std.DynLib,
    gobject: std.DynLib,
    glib: std.DynLib,
    cairo: std.DynLib,

    gtk_init: *const fn (?*c_int, ?*anyopaque) callconv(.c) void,
    gtk_main: *const fn () callconv(.c) void,
    gtk_main_quit: *const fn () callconv(.c) void,
    gtk_window_new: *const fn (c_int) callconv(.c) ?*common.GtkWidget,
    gtk_window_set_title: *const fn (*common.GtkWindow, [*:0]const u8) callconv(.c) void,
    gtk_window_set_default_size: *const fn (*common.GtkWindow, c_int, c_int) callconv(.c) void,
    gtk_window_set_decorated: *const fn (*common.GtkWindow, c_int) callconv(.c) void,
    gtk_window_set_resizable: *const fn (*common.GtkWindow, c_int) callconv(.c) void,
    gtk_window_set_position: *const fn (*common.GtkWindow, c_int) callconv(.c) void,
    gtk_window_move: *const fn (*common.GtkWindow, c_int, c_int) callconv(.c) void,
    gtk_window_iconify: *const fn (*common.GtkWindow) callconv(.c) void,
    gtk_window_maximize: *const fn (*common.GtkWindow) callconv(.c) void,
    gtk_window_unmaximize: *const fn (*common.GtkWindow) callconv(.c) void,
    gtk_widget_set_app_paintable: *const fn (*common.GtkWidget, c_int) callconv(.c) void,
    gtk_widget_get_screen: *const fn (*common.GtkWidget) callconv(.c) ?*common.GdkScreen,
    gdk_screen_get_rgba_visual: *const fn (*common.GdkScreen) callconv(.c) ?*common.GdkVisual,
    gtk_widget_set_visual: *const fn (*common.GtkWidget, *common.GdkVisual) callconv(.c) void,
    gtk_widget_get_allocated_width: *const fn (*common.GtkWidget) callconv(.c) c_int,
    gtk_widget_get_allocated_height: *const fn (*common.GtkWidget) callconv(.c) c_int,
    gtk_container_add: *const fn (*common.GtkContainer, *common.GtkWidget) callconv(.c) void,
    gtk_widget_shape_combine_region: *const fn (*common.GtkWidget, ?*common.cairo_region_t) callconv(.c) void,
    gtk_widget_input_shape_combine_region: *const fn (*common.GtkWidget, ?*common.cairo_region_t) callconv(.c) void,
    gtk_widget_show_all: *const fn (*common.GtkWidget) callconv(.c) void,
    gtk_widget_show: *const fn (*common.GtkWidget) callconv(.c) void,
    gtk_widget_hide: *const fn (*common.GtkWidget) callconv(.c) void,
    gtk_widget_destroy: *const fn (*common.GtkWidget) callconv(.c) void,
    webkit_web_view_new: *const fn () callconv(.c) ?*common.GtkWidget,
    webkit_web_view_load_uri: *const fn (*common.WebKitWebView, [*:0]const u8) callconv(.c) void,
    webkit_web_view_set_background_color: *const fn (*common.WebKitWebView, *const common.GdkRGBA) callconv(.c) void,
    g_signal_connect_data: *const fn (
        *anyopaque,
        [*:0]const u8,
        *const anyopaque,
        ?*anyopaque,
        ?*const anyopaque,
        c_uint,
    ) callconv(.c) c_ulong,
    g_idle_add: *const fn (*const fn (?*anyopaque) callconv(.c) c_int, ?*anyopaque) callconv(.c) c_uint,
    gdk_cairo_region_create_from_surface: *const fn (*common.cairo_surface_t) callconv(.c) ?*common.cairo_region_t,
    cairo_image_surface_create: *const fn (c_int, c_int, c_int) callconv(.c) ?*common.cairo_surface_t,
    cairo_surface_destroy: *const fn (*common.cairo_surface_t) callconv(.c) void,
    cairo_create: *const fn (*common.cairo_surface_t) callconv(.c) ?*common.cairo_t,
    cairo_destroy: *const fn (*common.cairo_t) callconv(.c) void,
    cairo_set_source_rgba: *const fn (*common.cairo_t, f64, f64, f64, f64) callconv(.c) void,
    cairo_paint: *const fn (*common.cairo_t) callconv(.c) void,
    cairo_new_path: *const fn (*common.cairo_t) callconv(.c) void,
    cairo_arc: *const fn (*common.cairo_t, f64, f64, f64, f64, f64) callconv(.c) void,
    cairo_close_path: *const fn (*common.cairo_t) callconv(.c) void,
    cairo_rectangle: *const fn (*common.cairo_t, f64, f64, f64, f64) callconv(.c) void,
    cairo_fill: *const fn (*common.cairo_t) callconv(.c) void,
    cairo_region_destroy: *const fn (*common.cairo_region_t) callconv(.c) void,

    pub fn load() !Symbols {
        var syms: Symbols = undefined;
        try syms.loadDynLibs();
        errdefer syms.deinit();
        try syms.loadFunctions();
        return syms;
    }

    pub fn deinit(self: *Symbols) void {
        self.cairo.close();
        self.glib.close();
        self.gobject.close();
        self.webkit.close();
        self.gdk.close();
        self.gtk.close();
    }

    fn loadDynLibs(self: *Symbols) !void {
        self.gtk = try openAny(&.{ "libgtk-3.so.0", "libgtk-3.so" });
        self.gdk = try openAny(&.{ "libgdk-3.so.0", "libgdk-3.so" });
        self.webkit = try openAny(&.{ "libwebkit2gtk-4.1.so.0", "libwebkit2gtk-4.1.so", "libwebkit2gtk-4.0.so.37", "libwebkit2gtk-4.0.so" });
        self.gobject = try openAny(&.{ "libgobject-2.0.so.0", "libgobject-2.0.so" });
        self.glib = try openAny(&.{ "libglib-2.0.so.0", "libglib-2.0.so" });
        self.cairo = try openAny(&.{ "libcairo.so.2", "libcairo.so" });
    }

    fn loadFunctions(self: *Symbols) !void {
        self.gtk_init = try lookupSym(&self.gtk, @TypeOf(self.gtk_init), "gtk_init");
        self.gtk_main = try lookupSym(&self.gtk, @TypeOf(self.gtk_main), "gtk_main");
        self.gtk_main_quit = try lookupSym(&self.gtk, @TypeOf(self.gtk_main_quit), "gtk_main_quit");
        self.gtk_window_new = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_new), "gtk_window_new");
        self.gtk_window_set_title = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_set_title), "gtk_window_set_title");
        self.gtk_window_set_default_size = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_set_default_size), "gtk_window_set_default_size");
        self.gtk_window_set_decorated = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_set_decorated), "gtk_window_set_decorated");
        self.gtk_window_set_resizable = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_set_resizable), "gtk_window_set_resizable");
        self.gtk_window_set_position = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_set_position), "gtk_window_set_position");
        self.gtk_window_move = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_move), "gtk_window_move");
        self.gtk_window_iconify = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_iconify), "gtk_window_iconify");
        self.gtk_window_maximize = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_maximize), "gtk_window_maximize");
        self.gtk_window_unmaximize = try lookupSym(&self.gtk, @TypeOf(self.gtk_window_unmaximize), "gtk_window_unmaximize");
        self.gtk_widget_set_app_paintable = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_set_app_paintable), "gtk_widget_set_app_paintable");
        self.gtk_widget_get_screen = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_get_screen), "gtk_widget_get_screen");
        self.gdk_screen_get_rgba_visual = try lookupSym(&self.gdk, @TypeOf(self.gdk_screen_get_rgba_visual), "gdk_screen_get_rgba_visual");
        self.gtk_widget_set_visual = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_set_visual), "gtk_widget_set_visual");
        self.gtk_widget_get_allocated_width = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_get_allocated_width), "gtk_widget_get_allocated_width");
        self.gtk_widget_get_allocated_height = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_get_allocated_height), "gtk_widget_get_allocated_height");
        self.gtk_container_add = try lookupSym(&self.gtk, @TypeOf(self.gtk_container_add), "gtk_container_add");
        self.gtk_widget_shape_combine_region = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_shape_combine_region), "gtk_widget_shape_combine_region");
        self.gtk_widget_input_shape_combine_region = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_input_shape_combine_region), "gtk_widget_input_shape_combine_region");
        self.gtk_widget_show_all = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_show_all), "gtk_widget_show_all");
        self.gtk_widget_show = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_show), "gtk_widget_show");
        self.gtk_widget_hide = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_hide), "gtk_widget_hide");
        self.gtk_widget_destroy = try lookupSym(&self.gtk, @TypeOf(self.gtk_widget_destroy), "gtk_widget_destroy");
        self.webkit_web_view_new = try lookupSym(&self.webkit, @TypeOf(self.webkit_web_view_new), "webkit_web_view_new");
        self.webkit_web_view_load_uri = try lookupSym(&self.webkit, @TypeOf(self.webkit_web_view_load_uri), "webkit_web_view_load_uri");
        self.webkit_web_view_set_background_color = try lookupSym(&self.webkit, @TypeOf(self.webkit_web_view_set_background_color), "webkit_web_view_set_background_color");
        self.g_signal_connect_data = try lookupSym(&self.gobject, @TypeOf(self.g_signal_connect_data), "g_signal_connect_data");
        self.g_idle_add = try lookupSym(&self.glib, @TypeOf(self.g_idle_add), "g_idle_add");
        self.gdk_cairo_region_create_from_surface = try lookupSym(&self.gdk, @TypeOf(self.gdk_cairo_region_create_from_surface), "gdk_cairo_region_create_from_surface");
        self.cairo_image_surface_create = try lookupSym(&self.cairo, @TypeOf(self.cairo_image_surface_create), "cairo_image_surface_create");
        self.cairo_surface_destroy = try lookupSym(&self.cairo, @TypeOf(self.cairo_surface_destroy), "cairo_surface_destroy");
        self.cairo_create = try lookupSym(&self.cairo, @TypeOf(self.cairo_create), "cairo_create");
        self.cairo_destroy = try lookupSym(&self.cairo, @TypeOf(self.cairo_destroy), "cairo_destroy");
        self.cairo_set_source_rgba = try lookupSym(&self.cairo, @TypeOf(self.cairo_set_source_rgba), "cairo_set_source_rgba");
        self.cairo_paint = try lookupSym(&self.cairo, @TypeOf(self.cairo_paint), "cairo_paint");
        self.cairo_new_path = try lookupSym(&self.cairo, @TypeOf(self.cairo_new_path), "cairo_new_path");
        self.cairo_arc = try lookupSym(&self.cairo, @TypeOf(self.cairo_arc), "cairo_arc");
        self.cairo_close_path = try lookupSym(&self.cairo, @TypeOf(self.cairo_close_path), "cairo_close_path");
        self.cairo_rectangle = try lookupSym(&self.cairo, @TypeOf(self.cairo_rectangle), "cairo_rectangle");
        self.cairo_fill = try lookupSym(&self.cairo, @TypeOf(self.cairo_fill), "cairo_fill");
        self.cairo_region_destroy = try lookupSym(&self.cairo, @TypeOf(self.cairo_region_destroy), "cairo_region_destroy");
    }
};

fn lookupSym(lib: *std.DynLib, comptime T: type, name: [:0]const u8) !T {
    return lib.lookup(T, name) orelse error.MissingDynamicSymbol;
}

fn openAny(names: []const []const u8) !std.DynLib {
    for (names) |name| {
        if (std.DynLib.open(name)) |lib| return lib else |_| {}
    }
    return error.MissingSharedLibrary;
}

